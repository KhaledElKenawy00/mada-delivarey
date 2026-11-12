import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';

enum LicenseStatus { checking, needsActivation, active, blocked }

class LicenseState {
  final LicenseStatus status;
  final Profile? profile;
  final String? message;
  final bool offline;
  const LicenseState(this.status, {this.profile, this.message, this.offline = false});
}

/// دورة الترخيص:
/// 1) أول تشغيل: مفيش بيانات → شاشة التفعيل
/// 2) التفعيل: المفتاح + بصمة الجهاز → السيرفر يربطهم مرة واحدة ويرجّع بيانات دخول الجهاز
/// 3) كل تشغيل بعد كده: دخول تلقائي + check_license (موقوف؟ منتهي؟ اتنقل لجهاز تاني؟)
/// 4) من غير إنترنت: بيشتغل لحد 72 ساعة من آخر تحقق ناجح
class LicenseController extends Notifier<LicenseState> {
  static const _storage = FlutterSecureStorage();
  static const _credKey = 'madar.credentials';
  static const _profileKey = 'madar.profile';
  static const _lastOkKey = 'madar.lastOk';
  static const offlineGrace = Duration(hours: 72);

  Timer? _timer;

  @override
  LicenseState build() {
    ref.onDispose(() => _timer?.cancel());
    Future.microtask(_boot);
    return const LicenseState(LicenseStatus.checking);
  }

  MadarRepository get _repo => ref.read(repositoryProvider);

  Future<void> _boot() async {
    final device = await ref.read(deviceIdentityProvider.future);
    final raw = await _storage.read(key: _credKey);
    if (raw == null) {
      state = const LicenseState(LicenseStatus.needsActivation);
      return;
    }
    try {
      final creds = Map<String, String>.from(jsonDecode(raw) as Map);
      final p = await _repo.restore(creds, device);
      await _remember(p);
      state = LicenseState(LicenseStatus.active, profile: p);
      _startTimer();
    } on AppException catch (e) {
      await _handle(e);
    } catch (_) {
      // بيانات دخول محفوظة ناقصة أو تالفة — نرجع لشاشة التفعيل بدل ما نكسر التطبيق
      await _storage.delete(key: _credKey);
      state = const LicenseState(LicenseStatus.needsActivation);
    }
  }

  Future<void> _handle(AppException e) async {
    if (e.code == 'NETWORK') {
      final cached = await _cachedProfile();
      if (cached != null) {
        state = LicenseState(LicenseStatus.active, profile: cached, offline: true);
        _startTimer();
      } else {
        state = LicenseState(LicenseStatus.blocked, message: 'مفيش إنترنت، ولازم اتصال للتحقق من الترخيص.');
      }
      return;
    }
    if (const ['OTHER_DEVICE', 'UNBOUND', 'INVALID_KEY', 'NO_LICENSE'].contains(e.code)) {
      await _storage.delete(key: _credKey);
      state = LicenseState(LicenseStatus.needsActivation, message: e.message);
      return;
    }
    state = LicenseState(LicenseStatus.blocked, message: e.message);
  }

  /// بترمي AppException للشاشة لو المفتاح غلط
  Future<void> activate(String key) async {
    final device = await ref.read(deviceIdentityProvider.future);
    final a = await _repo.activate(key, device);
    await _storage.write(key: _credKey, value: jsonEncode(a.credentials));
    await _remember(a.profile);
    state = LicenseState(LicenseStatus.active, profile: a.profile);
    _startTimer();
  }

  Future<void> retry() async {
    state = const LicenseState(LicenseStatus.checking);
    await _boot();
  }

  /// تسجيل خروج محلي: بيمسح بيانات الدخول المحفوظة على الجهاز ده ويرجّع
  /// لشاشة التفعيل. الربط على السيرفر (البصمة) يفضل كما هو، فنفس المفتاح
  /// يقدر يرجّع يفعّل على نفس الجهاز تاني من غير ما يحتاج فك ربط.
  Future<void> logout() async {
    _timer?.cancel();
    await _storage.delete(key: _credKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_profileKey);
    await prefs.remove(_lastOkKey);
    state = const LicenseState(LicenseStatus.needsActivation);
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 10), (_) => _recheck());
  }

  Future<void> _recheck() async {
    try {
      final device = await ref.read(deviceIdentityProvider.future);
      final p = await _repo.verify(device);
      await _remember(p);
      state = LicenseState(LicenseStatus.active, profile: p);
    } on AppException catch (e) {
      if (e.code == 'NETWORK') {
        final prefs = await SharedPreferences.getInstance();
        final last = DateTime.tryParse(prefs.getString(_lastOkKey) ?? '');
        if (last != null && DateTime.now().difference(last) < offlineGrace) {
          state = LicenseState(LicenseStatus.active, profile: state.profile, offline: true);
          return;
        }
      }
      await _handle(e);
    }
  }

  Future<void> _remember(Profile p) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileKey, jsonEncode(p.toJson()));
    await prefs.setString(_lastOkKey, DateTime.now().toIso8601String());
  }

  Future<Profile?> _cachedProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profileKey);
    final last = DateTime.tryParse(prefs.getString(_lastOkKey) ?? '');
    if (raw == null || last == null || DateTime.now().difference(last) > offlineGrace) return null;
    return Profile.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
  }
}

final licenseProvider = NotifierProvider<LicenseController, LicenseState>(LicenseController.new);

/// البروفايل الحالي (موجود دايماً جوه الشاشات اللي بعد التفعيل)
final profileProvider = Provider<Profile>((ref) {
  // لحظة قفل الترخيص الشاشة ممكن تتبني قبل التوجيه — فبنرجّع بروفايل فاضي بدل exception
  return ref.watch(licenseProvider).profile ?? const Profile(id: '', role: Role.rep, fullName: '');
});
