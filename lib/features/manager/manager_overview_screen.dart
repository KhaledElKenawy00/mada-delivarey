import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../keeper/keeper_dashboard_screen.dart' show AutoRefresh;

class ManagerOverviewScreen extends ConsumerStatefulWidget {
  const ManagerOverviewScreen({super.key});
  @override
  ConsumerState<ManagerOverviewScreen> createState() => _ManagerOverviewScreenState();
}

class _ManagerOverviewScreenState extends ConsumerState<ManagerOverviewScreen> with AutoRefresh {
  @override
  Duration get refreshEvery => const Duration(seconds: 20);

  @override
  void onRefresh() => ref.invalidate(companyOverviewProvider);

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(companyOverviewProvider);
    return AsyncBody(
      value: data,
      onRetry: onRefresh,
      builder: (o) {
        final t = o.totals;
        final reps = o.allReps;
        final now = DateTime.now();
        final whOf = {for (final w in o.warehouses) for (final r in w.reps) r.id: w.name};
        final top = [...reps]..sort((a, b) => b.totals.sold.compareTo(a.totals.sold));
        final alerts = <(String, String, Color)>[
          for (final r in reps.where((r) => r.status == RepStatus.lost))
            ('${r.name} — GPS مقطوع ${timeAgo(r.lastSeen)}', whOf[r.id] ?? '', const Color(0xFFFF6B7D)),
          for (final d in o.deficits) ('عجز ${money(d.diff.abs())} ج في التسوية', '${d.rep} · ${d.warehouse}', MC.orange),
          for (final b in o.expiring)
            (
              '${b.productName} ${b.daysLeft < 0 ? 'منتهي الصلاحية' : 'هتخلص صلاحيته بعد ${b.daysLeft} يوم'}',
              '${b.warehouseName} · ${qty(b.qty)} ${b.unit}',
              b.daysLeft <= 7 ? const Color(0xFFFF6B7D) : MC.orange,
            ),
          for (final r in reps.where((r) => r.status == RepStatus.pending))
            ('${r.name} مستني اعتماد التسوية', whOf[r.id] ?? '', MC.orange),
          if (o.expiresAt != null && o.expiresAt!.difference(now).inDays < 14)
            ('اشتراك الشركة بينتهي ${dateLabel(o.expiresAt!)}', 'تواصل مع الدعم للتجديد', MC.orange),
        ];
        return DesktopPage(children: [
          PageHeader(kicker: '${dayLabel(now)} · ${hm(now)} · محدّث لحظياً', title: 'كل المخازن', actions: [
            OutlinedButton.icon(onPressed: () => context.go('/manager/map'), icon: const Icon(Icons.map_outlined), label: const Text('الخريطة المباشرة')),
            FilledButton.icon(onPressed: () => context.go('/manager/reports'), icon: const Icon(Icons.bar_chart_rounded), label: const Text('التقارير')),
          ]),
          StatStrip(items: [
            StatItem('مصروف للمناديب', money(t.issued), sub: '${o.warehouses.length} مخازن · ${reps.length} مندوب'),
            StatItem('مبيعات اليوم', money(t.sold), sub: '${t.invoices} فاتورة', color: MC.burnt),
            StatItem('تحصيل نقدي', money(t.cashInHand), sub: 'في عهدة المناديب', color: MC.teal),
            StatItem('آجل جديد', money(t.credit), color: MC.crimson),
            StatItem('بضاعة في الشارع', money(t.remaining), sub: 'بسعر البيع', color: MC.plum),
          ]),
          LayoutBuilder(builder: (context, c) {
            final list = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SectionTitle('المخازن'),
              for (var k = 0; k < o.warehouses.length; k++) _WarehouseRow(w: o.warehouses[k], index: k),
              const LinedRow(
                padding: EdgeInsets.only(top: 12),
                child: Wrap(spacing: 16, children: [
                  LegendDot('مباع ومحصّل', MC.teal),
                  LegendDot('مباع آجل', MC.crimson),
                  LegendDot('لسه مع المناديب', MC.track),
                ]),
              ),
            ]);
            final side = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SectionTitle('أعلى مبيعات النهارده'),
              for (var k = 0; k < top.length && k < 5; k++)
                LinedRow(
                  onTap: () => context.go('/manager/report/${top[k].id}'),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(children: [
                    SizedBox(width: 28, child: Text('${k + 1}', style: display(18, weight: FontWeight.w700, color: MC.onDarkMuted))),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(top[k].name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(whOf[top[k].id] ?? '', style: const TextStyle(fontSize: 12, color: MC.muted)),
                      ]),
                    ),
                    Text(money(top[k].totals.sold), style: display(16)),
                  ]),
                ),
              const SizedBox(height: 28),
              DarkPanel(
                padding: const EdgeInsets.all(22),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('محتاج انتباهك', style: display(18, color: Colors.white)),
                  const SizedBox(height: 8),
                  if (alerts.isEmpty) const Text('كله تمام', style: TextStyle(color: MC.onDarkMuted)),
                  for (final (title, sub, color) in alerts)
                    LinedRow(
                      line: MC.inkSoft,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(
                          width: 10,
                          height: 10,
                          margin: const EdgeInsets.only(top: 6),
                          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white)),
                            Text(sub, style: const TextStyle(fontSize: 12, color: MC.onDarkMuted)),
                          ]),
                        ),
                      ]),
                    ),
                ]),
              ),
            ]);
            if (c.maxWidth < 1050) return Column(children: [list, const SizedBox(height: 28), side]);
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 3, child: list),
              const SizedBox(width: 28),
              Expanded(flex: 2, child: side),
            ]);
          }),
        ]);
      },
    );
  }
}

class _WarehouseRow extends StatelessWidget {
  final WarehouseSummary w;
  final int index;
  const _WarehouseRow({required this.w, required this.index});
  @override
  Widget build(BuildContext context) {
    final t = w.totals;
    final (bg, fg) = toneFor(index);
    final paid = t.issued == 0 ? 0.0 : (t.sold - t.credit) / t.issued;
    final cred = t.issued == 0 ? 0.0 : t.credit / t.issued;
    return LinedRow(
      padding: const EdgeInsets.symmetric(vertical: 22),
      onTap: () => context.go('/manager/warehouse/${w.id}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 16, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
            child: Text('${index + 1}', style: display(22, weight: FontWeight.w700, color: fg)),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 200, maxWidth: 320),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(w.name, style: display(19), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text.rich(
                TextSpan(style: const TextStyle(fontSize: 13, color: MC.muted), children: [
                  const TextSpan(text: 'أمين المخزن: '),
                  TextSpan(text: w.keeper ?? '—', style: const TextStyle(color: MC.ink, fontWeight: FontWeight.w600)),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              height: 32,
              width: 24.0 * w.reps.take(5).length + 10,
              child: Stack(children: [
                for (var k = 0; k < w.reps.length && k < 5; k++)
                  PositionedDirectional(
                    start: k * 24.0,
                    child: Container(
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: MC.ground, width: 2)),
                      child: Avatar(w.reps[k].name, size: 30),
                    ),
                  ),
              ]),
            ),
            const SizedBox(width: 10),
            Text('${w.reps.length} مناديب · ${w.repsInField} في الشارع', style: const TextStyle(fontSize: 14, color: MC.mutedDeep)),
          ]),
        ]),
        const SizedBox(height: 16),
        SplitBar(segments: [(paid, MC.teal), (cred, MC.crimson)], height: 12),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: MiniStat('مصروف للمناديب', money(t.issued))),
          Expanded(child: MiniStat('مباع', money(t.sold), color: MC.burntText)),
          Expanded(child: MiniStat('محصّل', money(t.cashInHand), color: MC.teal)),
          Expanded(child: MiniStat('بضاعة باقية مع المناديب', money(t.remaining), color: MC.plum)),
        ]),
      ]),
    );
  }
}
