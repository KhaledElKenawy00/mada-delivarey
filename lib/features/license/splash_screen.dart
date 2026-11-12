import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/env.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'license_controller.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: MC.plum,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const MadarLogo(size: 72, moon: Color(0xFFFBEFE8)),
            const SizedBox(height: 18),
            Text('مدار', style: display(34, weight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 8),
            const Text('بنتحقق من الترخيص…', style: TextStyle(color: Color(0xFFE5C8D5))),
            const SizedBox(height: 24),
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(color: MC.orange, strokeWidth: 3)),
          ]),
        ),
      );
}

class WrongDeviceScreen extends ConsumerWidget {
  const WrongDeviceScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = ref.watch(targetProvider);
    final p = ref.watch(licenseProvider).profile;
    final msg = target == AppTarget.mobile
        ? 'حساب ${p == null ? '' : roleLabel(p.role)} بيشتغل على تطبيق الويندوز. تطبيق الموبايل للمناديب بس.'
        : 'حساب المندوب بيشتغل على تطبيق الموبايل بس.';
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.devices_other_rounded, size: 56, color: MC.plum),
            const SizedBox(height: 16),
            Text('الجهاز ده مش مخصص للحساب ده', style: display(22), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(msg, textAlign: TextAlign.center, style: const TextStyle(color: MC.muted, height: 1.7)),
          ]),
        ),
      ),
    );
  }
}
