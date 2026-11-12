import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../license/license_controller.dart';

class ManagerShell extends ConsumerWidget {
  final String location;
  final Widget child;
  const ManagerShell({super.key, required this.location, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(profileProvider);
    final o = ref.watch(companyOverviewProvider).valueOrNull;
    final p2 = ShellPalette.manager;
    final exp = p.expiresAt;
    final daysLeft = exp == null ? null : exp.difference(DateTime.now()).inDays;
    return DesktopShell(
      palette: p2,
      subtitle: '${p.companyName ?? ''} · الإدارة',
      location: location,
      entries: [
        const NavEntry('نظرة عامة', Icons.dashboard_outlined, '/manager'),
        for (final w in o?.warehouses ?? const <WarehouseSummary>[])
          NavEntry(w.name, Icons.warehouse_outlined, '/manager/warehouse/${w.id}'),
        const NavEntry('الخريطة المباشرة', Icons.map_outlined, '/manager/map'),
        const NavEntry('الأرباح', Icons.trending_up_rounded, '/manager/profit'),
        const NavEntry('تقارير المناديب', Icons.bar_chart_rounded, '/manager/reports'),
        const NavEntry('العملاء', Icons.storefront_outlined, '/manager/customers'),
      ],
      footer: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(border: Border.all(color: p2.railLine), borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('اشتراك الشركة', style: TextStyle(fontSize: 12, color: p2.railMuted)),
          const SizedBox(height: 6),
          Text('${o?.warehouses.length ?? '—'} مخازن · ${o?.maxReps ?? '—'} مندوب', style: display(15, color: p2.railFg)),
          const SizedBox(height: 8),
          if (daysLeft != null)
            SplitBar(segments: [((daysLeft / 90).clamp(0.05, 1.0).toDouble(), MC.orange)], height: 6, track: p2.railLine),
          const SizedBox(height: 6),
          Text(exp == null ? '' : 'ينتهي ${dateLabel(exp)} · باقي $daysLeft يوم', style: TextStyle(fontSize: 12, color: p2.railMuted)),
        ]),
      ),
      child: child,
    );
  }
}
