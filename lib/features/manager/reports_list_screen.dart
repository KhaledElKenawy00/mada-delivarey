import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// اختيار مندوب لفتح تقريره (أمين المخزن: مناديب مخزنه — المدير: كل المخازن)
class ReportsListScreen extends ConsumerWidget {
  final String base; // /keeper أو /manager
  const ReportsListScreen({super.key, required this.base});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (base == '/manager') {
      final o = ref.watch(companyOverviewProvider);
      return AsyncBody(
        value: o,
        onRetry: () => ref.invalidate(companyOverviewProvider),
        builder: (c) => DesktopPage(children: [
          const PageHeader(title: 'تقارير المناديب', kicker: 'يومي وشهري لكل مندوب'),
          for (final w in c.warehouses) _group(context, w.name, w.keeper, w.reps),
        ]),
      );
    }
    final live = ref.watch(warehouseLiveProvider(null));
    return AsyncBody(
      value: live,
      onRetry: () => ref.invalidate(warehouseLiveProvider(null)),
      builder: (w) => DesktopPage(children: [
        PageHeader(title: 'تقارير المناديب', kicker: '${w.name} · يومي وشهري'),
        _group(context, w.name, w.keeperName, w.reps),
      ]),
    );
  }

  Widget _group(BuildContext context, String title, String? keeper, List<RepLive> reps) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(title, hint: keeper == null ? null : 'أمين المخزن: $keeper'),
          for (var k = 0; k < reps.length; k++)
            LinedRow(
              onTap: () => context.go('$base/report/${reps[k].id}'),
              child: Row(children: [
                Avatar(reps[k].name, bg: toneFor(k).$1, fg: toneFor(k).$2),
                const SizedBox(width: 14),
                Expanded(child: Text(reps[k].name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16))),
                MiniStat('مبيعات اليوم', money(reps[k].totals.sold), color: MC.burntText),
                const SizedBox(width: 24),
                const Icon(Icons.chevron_left_rounded, color: MC.muted),
              ]),
            ),
        ],
      );
}
