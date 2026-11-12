import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../license/license_controller.dart';

class KeeperShell extends ConsumerWidget {
  final String location;
  final Widget child;
  const KeeperShell({super.key, required this.location, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(profileProvider);
    final pending = ref.watch(warehouseLiveProvider(null)).valueOrNull?.reps.where((r) => r.status == RepStatus.pending).length ?? 0;
    return DesktopShell(
      palette: ShellPalette.keeper,
      subtitle: p.warehouseName ?? 'أمين مخزن',
      location: location,
      entries: [
        const NavEntry('المتابعة الحية', Icons.radar_rounded, '/keeper'),
        const NavEntry('صرف بضاعة', Icons.outbox_rounded, '/keeper/issue'),
        NavEntry('تسوية العهد', Icons.balance_rounded, '/keeper/settlements', badge: pending),
        const NavEntry('الأصناف والمخزون', Icons.inventory_2_outlined, '/keeper/products'),
        const NavEntry('الموردين', Icons.local_shipping_outlined, '/keeper/suppliers'),
        const NavEntry('العملاء', Icons.storefront_outlined, '/keeper/customers'),
        const NavEntry('خريطة المناديب', Icons.map_outlined, '/keeper/map'),
        const NavEntry('الأرباح', Icons.trending_up_rounded, '/keeper/profit'),
        const NavEntry('تقارير المناديب', Icons.bar_chart_rounded, '/keeper/reports'),
      ],
      footer: LicenseFooter(palette: ShellPalette.keeper, keyText: p.licenseKey),
      child: child,
    );
  }
}

/// صندوق الترخيص أسفل القائمة
class LicenseFooter extends ConsumerWidget {
  final ShellPalette palette;
  final String? keyText;
  const LicenseFooter({super.key, required this.palette, this.keyText});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(licenseProvider).offline;
    final k = keyText ?? '';
    final masked = k.length >= 18 ? '${k.substring(0, 8)}-•••-${k.substring(k.length - 4)}' : k;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(border: Border.all(color: palette.railLine), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('ترخيص الجهاز', style: TextStyle(fontSize: 12, color: palette.railMuted)),
        const SizedBox(height: 6),
        Text(masked, style: display(14, color: palette.railFg), textDirection: TextDirection.ltr),
        const SizedBox(height: 8),
        Row(children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: offline ? MC.orange : MC.success, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              offline ? 'شغال أوفلاين' : 'مفعّل على هذا الجهاز',
              style: TextStyle(fontSize: 13, color: offline ? MC.orange : const Color(0xFF9FD7C6)),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            onPressed: () => _confirmLogout(context, ref),
            icon: Icon(Icons.logout_rounded, size: 16, color: palette.railMuted),
            label: Text('تسجيل خروج', style: TextStyle(fontSize: 13, color: palette.railMuted)),
            style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerRight),
          ),
        ),
      ]),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسجيل خروج؟'),
        content: const Text('هيتم مسح بيانات الدخول من الجهاز ده، وتحتاج تدخل مفتاح تفعيل تاني (أو نفس المفتاح) علشان تدخل تاني.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تسجيل خروج')),
        ],
      ),
    );
    if (ok == true) await ref.read(licenseProvider.notifier).logout();
  }
}
