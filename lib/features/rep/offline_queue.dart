import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';

/// فواتير وتحصيلات اتعملت من غير إنترنت — بتترفع بالترتيب أول ما النت يرجع.
/// كل عملية ليها client_uuid ثابت، فلو اترفعت مرتين السيرفر بيرجّع نفس الفاتورة (مفيش خصم مزدوج).
class OfflineQueue extends ChangeNotifier {
  OfflineQueue(this._repo) {
    _load();
    _conn = Connectivity().onConnectivityChanged.listen((r) {
      if (!r.contains(ConnectivityResult.none)) flush();
    });
    _timer = Timer.periodic(const Duration(seconds: 45), (_) => flush());
  }

  static const _key = 'madar.offline_ops';
  final MadarRepository _repo;
  List<Map<String, dynamic>> _ops = [];
  final List<String> failures = [];
  bool _flushing = false;
  StreamSubscription<List<ConnectivityResult>>? _conn;
  Timer? _timer;

  int get length => _ops.length;

  /// كميات اتباعت أوفلاين لسه ماوصلتش السيرفر (بتتخصم من العهدة على الشاشة)
  Map<String, double> get pendingQty {
    final m = <String, double>{};
    for (final op in _ops.where((o) => o['type'] == 'sale')) {
      for (final l in (op['lines'] as List)) {
        final id = l['product_id'] as String;
        m[id] = (m[id] ?? 0) + d(l['qty']);
      }
    }
    return m;
  }

  double get pendingCash => _ops.fold<double>(0, (a, o) => a + (o['type'] == 'sale' ? d(o['paid']) : d(o['amount'])));
  double get pendingSales => _ops.where((o) => o['type'] == 'sale').fold<double>(0, (a, o) => a + d(o['total']));

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      _ops = (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      notifyListeners();
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_ops));
    notifyListeners();
  }

  Future<void> addSale(String clientUuid, String customerId, List<SaleLine> lines, double paid, double total) async {
    _ops.add({
      'type': 'sale',
      'id': clientUuid,
      'customer': customerId,
      'lines': lines.map((l) => l.toJson()).toList(),
      'paid': paid,
      'total': total,
      'at': DateTime.now().toIso8601String(),
    });
    await _save();
  }

  Future<void> addCollection(String clientUuid, String customerId, double amount) async {
    _ops.add({'type': 'collection', 'id': clientUuid, 'customer': customerId, 'amount': amount, 'at': DateTime.now().toIso8601String()});
    await _save();
  }

  /// بيرجّع عدد العمليات اللي اترفعت
  Future<int> flush() async {
    if (_flushing || _ops.isEmpty) return 0;
    _flushing = true;
    var sent = 0;
    try {
      while (_ops.isNotEmpty) {
        final op = _ops.first;
        try {
          if (op['type'] == 'sale') {
            await _repo.createSale(
              op['id'] as String,
              op['customer'] as String,
              [for (final l in (op['lines'] as List)) SaleLine(l['product_id'] as String, d(l['qty']))],
              d(op['paid']),
            );
          } else {
            await _repo.createCollection(op['id'] as String, op['customer'] as String, d(op['amount']));
          }
        } on AppException catch (e) {
          if (e.code == 'NETWORK') break;
          failures.add('${op['type'] == 'sale' ? 'فاتورة' : 'تحصيل'}: ${e.message}');
        }
        _ops.removeAt(0);
        sent++;
        await _save();
      }
    } finally {
      _flushing = false;
    }
    return sent;
  }

  @override
  void dispose() {
    _conn?.cancel();
    _timer?.cancel();
    super.dispose();
  }
}

final offlineQueueProvider = ChangeNotifierProvider<OfflineQueue>((ref) => OfflineQueue(ref.read(repositoryProvider)));
