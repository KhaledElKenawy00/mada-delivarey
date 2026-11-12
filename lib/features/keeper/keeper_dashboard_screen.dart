import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../common/reps_map.dart';

/// بيحدّث أي provider كل كام ثانية طول ما الشاشة مفتوحة
mixin AutoRefresh<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  Timer? _t;
  Duration get refreshEvery => const Duration(seconds: 15);
  void onRefresh();
  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(refreshEvery, (_) => onRefresh());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }
}

class KeeperDashboardScreen extends ConsumerStatefulWidget {
  const KeeperDashboardScreen({super.key});
  @override
  ConsumerState<KeeperDashboardScreen> createState() => _KeeperDashboardScreenState();
}

class _KeeperDashboardScreenState extends ConsumerState<KeeperDashboardScreen> with AutoRefresh {
  DateTime _updated = DateTime.now();

  @override
  void onRefresh() {
    ref.invalidate(warehouseLiveProvider(null));
    setState(() => _updated = DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(warehouseLiveProvider(null));
    return AsyncBody(
      value: live,
      onRetry: onRefresh,
      builder: (w) {
        final t = w.totals;
        final now = DateTime.now();
        return DesktopPage(children: [
          PageHeader(
            kicker: '${dayLabel(now)} · ${hm(now)}',
            title: 'المتابعة الحية للمناديب',
            actions: [
              Pill('متزامن · ${timeAgo(_updated)}', fg: MC.teal, bg: MC.tealTint),
              OutlinedButton.icon(onPressed: onRefresh, icon: const Icon(Icons.refresh_rounded), label: const Text('تحديث')),
              FilledButton.icon(
                onPressed: () => context.go('/keeper/issue'),
                icon: const Icon(Icons.add_rounded),
                label: const Text('إذن صرف جديد'),
              ),
            ],
          ),
          StatStrip(items: [
            StatItem('مصروف للمناديب اليوم', money(t.issued), sub: 'جنيه بسعر البيع'),
            StatItem('مبيعات حتى الآن', money(t.sold), sub: '${t.invoices} فاتورة', color: MC.burnt),
            StatItem('تحصيل نقدي', money(t.cashInHand), sub: 'في عهدة المناديب', color: MC.teal),
            StatItem('آجل على العملاء', money(t.credit), color: MC.crimson),
            StatItem('في الشارع', '${w.repsInField} / ${w.reps.length}', sub: 'مندوب', color: MC.plum),
          ]),
          LayoutBuilder(builder: (context, c) {
            final reps = _RepsList(reps: w.reps);
            final side = _Side(w: w);
            if (c.maxWidth < 1050) return Column(children: [reps, const SizedBox(height: 28), side]);
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 3, child: reps),
              const SizedBox(width: 28),
              Expanded(flex: 2, child: side),
            ]);
          }),
        ]);
      },
    );
  }
}

class _RepsList extends StatelessWidget {
  final List<RepLive> reps;
  const _RepsList({required this.reps});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionTitle('المناديب اليوم', hint: 'العهدة: مباع / متبقي بسعر البيع'),
        if (reps.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('مفيش مناديب في المخزن ده لسه')),
        WideTable(
          minWidth: 680,
          child: Column(children: [
            for (var k = 0; k < reps.length; k++) _RepRow(rep: reps[k], index: k),
          ]),
        ),
      ]);
}

class _RepRow extends StatelessWidget {
  final RepLive rep;
  final int index;
  const _RepRow({required this.rep, required this.index});
  @override
  Widget build(BuildContext context) {
    final t = rep.totals;
    final (bg, fg) = toneFor(index);
    final canSettle = rep.sessionId != null && (rep.status == RepStatus.pending || rep.inField);
    return LinedRow(
      onTap: () => context.go('/keeper/report/${rep.id}'),
      child: Row(children: [
        Avatar(rep.name, bg: bg, fg: fg, size: 48),
        const SizedBox(width: 16),
        SizedBox(
          width: 170,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(rep.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            Text('${rep.device ?? 'جهاز غير مفعّل'} · ${timeAgo(rep.lastSeen)}',
                style: const TextStyle(fontSize: 12, color: MC.muted), overflow: TextOverflow.ellipsis),
          ]),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SplitBar(segments: [(t.issued == 0 ? 0.0 : t.sold / t.issued, MC.burnt)]),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('مباع ${money(t.sold)}', style: const TextStyle(fontSize: 12, color: MC.muted)),
              Text('من ${money(t.issued)}', style: const TextStyle(fontSize: 12, color: MC.muted)),
            ]),
          ]),
        ),
        const SizedBox(width: 16),
        SizedBox(width: 100, child: MiniStat('محصّل', money(t.cashInHand), color: MC.teal, size: 17)),
        SizedBox(width: 150, child: Align(alignment: AlignmentDirectional.centerStart, child: RepStatusPill(rep.status))),
        IconButton(
          tooltip: 'تسوية العهدة',
          onPressed: canSettle ? () => context.go('/keeper/settlement/${rep.sessionId}') : null,
          icon: const Icon(Icons.balance_rounded),
          color: MC.plum,
        ),
      ]),
    );
  }
}

class _Side extends StatelessWidget {
  final WarehouseLive w;
  const _Side({required this.w});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionTitle('الخريطة', trailing: TextButton(onPressed: () => context.go('/keeper/map'), child: const Text('ملء الشاشة'))),
        SizedBox(
          height: 300,
          child: RepsMap(
            reps: w.reps.where((r) => r.inField).toList(),
            warehouses: [if (w.lat != null && w.lng != null) MapWarehouse(w.name, w.lat!, w.lng!)],
          ),
        ),
        const SizedBox(height: 24),
        const SectionTitle('آخر الأذون'),
        if (w.feed.isEmpty) const Text('مفيش حركة النهارده لسه', style: TextStyle(color: MC.muted)),
        for (final f in w.feed)
          LinedRow(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: switch (f.kind) { 'sale' => MC.burnt, 'collection' => MC.teal, _ => MC.plum },
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    switch (f.kind) {
                      'sale' => 'فاتورة بيع — ${f.title}',
                      'collection' => 'تحصيل — ${f.title}',
                      _ => 'إذن صرف — ${f.title}',
                    },
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  Text('${f.no} · ${f.rep} · ${hm(f.at)}', style: const TextStyle(fontSize: 12, color: MC.muted)),
                ]),
              ),
              Text(money(f.amount), style: display(15)),
            ]),
          ),
      ]);
}
