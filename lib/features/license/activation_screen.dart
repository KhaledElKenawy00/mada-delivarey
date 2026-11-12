import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/device_identity.dart';
import '../../core/env.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/demo_repository.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import 'license_controller.dart';
import 'license_key_input.dart';

class ActivationScreen extends ConsumerStatefulWidget {
  const ActivationScreen({super.key});
  @override
  ConsumerState<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends ConsumerState<ActivationScreen> {
  final _keyInput = GlobalKey<LicenseKeyInputState>();
  String _key = '';
  bool _busy = false;
  String? _error;

  bool get _complete => RegExp(r'^MDR-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$').hasMatch(_key);

  Future<void> _activate() async {
    if (!_complete || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(licenseProvider.notifier).activate(_key);
    } on AppException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mobile = ref.watch(targetProvider) == AppTarget.mobile;
    final device = ref.watch(deviceIdentityProvider);
    final lic = ref.watch(licenseProvider);
    final banner = _error ?? lic.message;
    return mobile ? _mobile(device, lic, banner) : _desktop(device, lic, banner);
  }

  // ───────────────────────────── Desktop
  Widget _desktop(AsyncValue<DeviceIdentity> device, LicenseState lic, String? banner) => Scaffold(
        body: LayoutBuilder(builder: (context, c) {
          final narrow = c.maxWidth < 980;
          final brand = Container(
            color: MC.plum,
            padding: const EdgeInsets.all(56),
            child: Stack(clipBehavior: Clip.hardEdge, children: [
              const PositionedDirectional(bottom: -260, end: -200, child: OrbitRings(size: 760, color: Color(0xFFFBEFE8))),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const MadarLogo(size: 44, moon: Color(0xFFFBEFE8)),
                  const SizedBox(width: 12),
                  Text('مدار', style: display(26, weight: FontWeight.w700, color: Colors.white)),
                ]),
                const Spacer(),
                Text('جهاز واحد.\nترخيص واحد.\nمرة واحدة.', style: display(46, weight: FontWeight.w700, color: const Color(0xFFFBEFE8))),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: const Text(
                    'التفعيل يربط حسابك بالرقم التسلسلي لهذا الجهاز. بعد كده التطبيق يفتح على طول، ومحدش يقدر يستخدم نفس الترخيص على جهاز تاني.',
                    style: TextStyle(fontSize: 17, height: 1.7, color: Color(0xFFEAD2DC)),
                  ),
                ),
                const Spacer(),
                const Text('نسخة سطح المكتب · Windows', style: TextStyle(fontSize: 13, color: Color(0xFFD9B9C8))),
              ]),
            ]),
          );
          final form = SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 56),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 8, runSpacing: 8, children: [
                  Pill('قراءة سيريال الجهاز', fg: MC.teal, bg: MC.tealTint, dot: device.hasValue),
                  Pill('إدخال مفتاح الترخيص', fg: Colors.white, bg: MC.ink, dot: false),
                  const Pill('ربط وتسجيل الدخول', fg: MC.muted, bg: Color(0xFFF1E9E2), dot: false),
                ]),
                const SizedBox(height: 32),
                Text('تفعيل الجهاز', style: display(32)),
                const SizedBox(height: 8),
                const Text('مفتاح الترخيص بتستلمه من إدارة الشركة. اكتبه مرة واحدة بس.', style: TextStyle(fontSize: 16, color: MC.muted)),
                const SizedBox(height: 32),
                const Text('هوية هذا الجهاز', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                _DeviceStrip(device: device),
                const SizedBox(height: 28),
                const Text('مفتاح الترخيص', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                LicenseKeyInput(key: _keyInput, onChanged: (v) => setState(() => _key = v)),
                if (Env.demo) ...[const SizedBox(height: 14), _DemoKeys(onPick: (k) => _keyInput.currentState?.fill(k))],
                const SizedBox(height: 24),
                if (banner != null) _Banner(banner, onRetry: lic.status == LicenseStatus.blocked ? () => ref.read(licenseProvider.notifier).retry() : null),
                _LockNote(serial: device.valueOrNull?.serial),
                const SizedBox(height: 24),
                Wrap(spacing: 14, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  FilledButton.icon(
                    onPressed: _complete && !_busy ? _activate : null,
                    icon: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.lock_open_rounded),
                    label: const Text('تفعيل وربط الجهاز'),
                    style: FilledButton.styleFrom(minimumSize: const Size(220, 56)),
                  ),
                  TextButton(onPressed: () => _keyInput.currentState?.pasteFromClipboard(), child: const Text('لصق المفتاح من الحافظة')),
                ]),
              ]),
            ),
          );
          if (narrow) return ListView(children: [SizedBox(height: 460, child: brand), form]);
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(flex: 9, child: brand),
            Expanded(flex: 11, child: Center(child: form)),
          ]);
        }),
      );

  // ───────────────────────────── Mobile
  Widget _mobile(AsyncValue<DeviceIdentity> device, LicenseState lic, String? banner) => Scaffold(
        backgroundColor: MC.plum,
        body: Stack(children: [
          const PositionedDirectional(top: -210, end: -170, child: OrbitRings(size: 520, color: Color(0xFFFBEFE8))),
          SafeArea(
            child: ListView(padding: const EdgeInsets.fromLTRB(24, 140, 24, 32), children: [
              Text('مدار · المندوب', style: display(20, weight: FontWeight.w700, color: Colors.white)),
              const SizedBox(height: 8),
              Text('فعّل الموبايل ده\nمرة واحدة بس', style: display(32, weight: FontWeight.w700, color: Colors.white)),
              const SizedBox(height: 26),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: MC.plumDeep, borderRadius: BorderRadius.circular(16)),
                child: Row(children: [
                  const Icon(Icons.smartphone_rounded, color: MC.orange),
                  const SizedBox(width: 12),
                  Expanded(
                    child: device.when(
                      data: (d) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${d.deviceName} · رقم الجهاز', style: const TextStyle(fontSize: 12, color: Color(0xFFD9B9C8))),
                        Text(d.serial, style: display(16, color: Colors.white), textDirection: TextDirection.ltr, overflow: TextOverflow.ellipsis),
                      ]),
                      loading: () => const Text('بنقرا رقم الجهاز…', style: TextStyle(color: Colors.white)),
                      error: (e, _) => Text('$e', style: const TextStyle(color: Colors.white)),
                    ),
                  ),
                  if (device.hasValue) const Icon(Icons.check_rounded, color: Color(0xFF7FD6B8)),
                ]),
              ),
              const SizedBox(height: 26),
              const Text('مفتاح الترخيص', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
              const SizedBox(height: 10),
              LicenseKeyInput(key: _keyInput, dark: true, boxHeight: 56, onChanged: (v) => setState(() => _key = v)),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: MC.orange),
                  onPressed: () => _keyInput.currentState?.pasteFromClipboard(),
                  icon: const Icon(Icons.content_paste_rounded, size: 18),
                  label: const Text('لصق المفتاح'),
                ),
              ),
              if (Env.demo) _DemoKeys(onPick: (k) => _keyInput.currentState?.fill(k), dark: true),
              const SizedBox(height: 12),
              if (banner != null)
                _Banner(banner, onRetry: lic.status == LicenseStatus.blocked ? () => ref.read(licenseProvider.notifier).retry() : null),
              const Text(
                'الترخيص هيتربط بالموبايل ده بس. لو غيّرت الموبايل اطلب من الإدارة فك الربط.',
                style: TextStyle(fontSize: 13, height: 1.7, color: Color(0xFFE5C8D5)),
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _complete && !_busy ? _activate : null,
                style: FilledButton.styleFrom(
                  backgroundColor: MC.orange,
                  foregroundColor: MC.ink,
                  disabledBackgroundColor: const Color(0xFF7A2B5C),
                  minimumSize: const Size.fromHeight(58),
                ),
                child: _busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: MC.ink))
                    : const Text('تفعيل الجهاز'),
              ),
            ]),
          ),
        ]),
      );
}

class _DeviceStrip extends StatelessWidget {
  final AsyncValue<DeviceIdentity> device;
  const _DeviceStrip({required this.device});
  @override
  Widget build(BuildContext context) {
    final d = device.valueOrNull;
    Widget cell(String label, String value, {bool ltr = false}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 12, color: MC.muted)),
              const SizedBox(height: 4),
              Text(value,
                  style: display(17),
                  textDirection: ltr ? TextDirection.ltr : null,
                  overflow: TextOverflow.ellipsis),
            ]),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: MC.line), borderRadius: BorderRadius.circular(16)),
        child: IntrinsicHeight(
          child: Row(children: [
            cell('الرقم التسلسلي', d?.serial ?? '…', ltr: true),
            const VerticalDivider(width: 1, color: MC.line),
            cell('اسم الجهاز', d?.deviceName ?? '…', ltr: true),
            const VerticalDivider(width: 1, color: MC.line),
            cell('النظام', d?.osLabel ?? '…'),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      if (d != null)
        const Row(children: [
          Icon(Icons.check_rounded, size: 16, color: MC.teal),
          SizedBox(width: 6),
          Text('اتقرأ تلقائياً — مش محتاج تكتبه', style: TextStyle(fontSize: 13, color: MC.teal)),
        ]),
    ]);
  }
}

class _LockNote extends StatelessWidget {
  final String? serial;
  const _LockNote({this.serial});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0xFFFBEBDD), borderRadius: BorderRadius.circular(14)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.lock_outline_rounded, color: MC.crimson),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'بعد التفعيل الترخيص هيتقفل على ${serial ?? 'هذا الجهاز'}. لو غيّرت الجهاز، الإدارة لازم تلغي الربط من لوحة التراخيص الأول.',
              style: const TextStyle(fontSize: 14, height: 1.7, color: Color(0xFF4A2A3A)),
            ),
          ),
        ]),
      );
}

class _Banner extends StatelessWidget {
  final String text;
  final VoidCallback? onRetry;
  const _Banner(this.text, {this.onRetry});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: MC.crimsonTint, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          const Icon(Icons.error_outline_rounded, color: MC.crimson),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: MC.crimson, fontWeight: FontWeight.w600))),
          if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('حاول تاني')),
        ]),
      );
}

class _DemoKeys extends StatelessWidget {
  final ValueChanged<String> onPick;
  final bool dark;
  const _DemoKeys({required this.onPick, this.dark = false});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('وضع العرض — اختار مفتاح تجربة:', style: TextStyle(fontSize: 13, color: dark ? const Color(0xFFE5C8D5) : MC.muted)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in DemoRepository.demoKeys.entries)
            ActionChip(
              label: Text(e.value),
              avatar: const Icon(Icons.key_rounded, size: 16),
              onPressed: () => onPick(e.key),
            ),
        ]),
      ]);
}
