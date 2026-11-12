import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// المدير: مين مسؤول عن المخزن، كام مندوب، كل واحد باع بكام وباقي معاه إيه
class WarehouseDetailScreen extends ConsumerWidget {
  final String warehouseId;
  const WarehouseDetailScreen({super.key, required this.warehouseId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(warehouseLiveProvider(warehouseId));
    return AsyncBody(
      value: data,
      onRetry: () => ref.invalidate(warehouseLiveProvider(warehouseId)),
      builder: (w) {
        final t = w.totals;
        const st = TextStyle(fontSize: 13, color: MC.muted);
        return DesktopPage(maxWidth: 1360, children: [
          Wrap(spacing: 24, runSpacing: 24, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 420, maxWidth: 760),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(w.address ?? '', style: const TextStyle(fontSize: 14, color: MC.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(w.name, style: display(38, weight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 12),
                Wrap(spacing: 28, runSpacing: 12, children: [
                  MiniStat('مباع اليوم', money(t.sold), color: MC.burntText, size: 26),
                  MiniStat('محصّل', money(t.cashInHand), color: MC.teal, size: 26),
                  MiniStat('آجل', money(t.credit), color: MC.crimson, size: 26),
                  MiniStat('باقي مع المناديب', money(t.remaining), color: MC.plum, size: 26),
                ]),
              ]),
            ),
            SizedBox(
              width: 340,
              child: DarkPanel(
                padding: const EdgeInsets.all(22),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text('المسؤول عن المخزن', style: TextStyle(fontSize: 13, color: MC.onDarkMuted)),
                  const SizedBox(height: 12),
                  Row(children: [
                    Avatar(w.keeperName ?? '؟', size: 50, bg: MC.orange, fg: MC.ink),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(w.keeperName ?? 'مفيش أمين', style: display(19, color: Colors.white)),
                        Text('أمين مخزن${w.keeperPhone == null ? '' : ' · ${w.keeperPhone}'}', style: const TextStyle(fontSize: 13, color: MC.onDarkMuted)),
                      ]),
                    ),
                  ]),
                  const Divider(color: MC.inkSoft, height: 28),
                  Row(children: [
                    Text(w.keeperDevice ?? 'لسه ماتفعّلش', style: const TextStyle(fontSize: 13, color: MC.onDarkMuted)),
                    const Spacer(),
                    Pill(w.keeperActivated ? 'مفعّل' : 'غير مفعّل',
                        fg: w.keeperActivated ? const Color(0xFF9FE0CB) : MC.orange, bg: Colors.transparent, fontSize: 12),
                  ]),
                ]),
              ),
            ),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionTitle('المناديب (${w.reps.length} من ${w.maxReps} مسموح)', hint: 'اضغط على المندوب لفتح تقريره'),
            WideTable(
              minWidth: 1000,
              child: Column(children: [
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: MC.ink, width: 2), bottom: BorderSide(color: MC.line))),
                  child: const Row(children: [
                    Expanded(flex: 16, child: Text('المندوب', style: st)),
                    Expanded(flex: 10, child: Text('استلم الصبح', style: st)),
                    Expanded(flex: 10, child: Text('باع', style: st)),
                    Expanded(flex: 10, child: Text('حصّل', style: st)),
                    Expanded(flex: 10, child: Text('آجل', style: st)),
                    Expanded(flex: 10, child: Text('باقي معاه', style: st)),
                    Expanded(flex: 13, child: Text('نسبة البيع', style: st)),
                    SizedBox(width: 150, child: Text('الحالة', style: st)),
                  ]),
                ),
                for (var k = 0; k < w.reps.length; k++) _row(context, w.reps[k], k),
              ]),
            ),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SectionTitle('رصيد المخزن دلوقتي'),
            Wrap(children: [
              for (final s in w.stock)
                SizedBox(
                  width: 300,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(end: 24, top: 12, bottom: 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        Expanded(
                          child: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        Text(qty(s.inStock), style: display(22, weight: FontWeight.w700)),
                        Text(' ${s.unit}', style: const TextStyle(fontSize: 12, color: MC.muted)),
                      ]),
                      const SizedBox(height: 8),
                      SplitBar(height: 8, segments: [
                        (s.inStock + s.withReps == 0 ? 0.0 : s.inStock / (s.inStock + s.withReps), MC.teal),
                        (s.inStock + s.withReps == 0 ? 0.0 : s.withReps / (s.inStock + s.withReps), MC.orange),
                      ]),
                      const SizedBox(height: 6),
                      Text('في المخزن ${qty(s.inStock)} · مع المناديب ${qty(s.withReps)}', style: const TextStyle(fontSize: 12, color: MC.muted)),
                    ]),
                  ),
                ),
            ]),
          ]),
        ]);
      },
    );
  }

  Widget _row(BuildContext context, RepLive r, int k) {
    final t = r.totals;
    final pct = t.issued == 0 ? 0.0 : t.sold / t.issued;
    return InkWell(
      onTap: () => context.go('/manager/report/${r.id}'),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: MC.line))),
        child: Row(children: [
          Expanded(
            flex: 16,
            child: Row(children: [
              Avatar(r.name, size: 40, bg: toneFor(k).$1, fg: toneFor(k).$2),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(r.device ?? '—', style: const TextStyle(fontSize: 12, color: MC.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
            ]),
          ),
          Expanded(flex: 10, child: Text(money(t.issued), style: display(16))),
          Expanded(flex: 10, child: Text(money(t.sold), style: display(16, color: MC.burntText))),
          Expanded(flex: 10, child: Text(money(t.cashInHand), style: display(16, color: MC.teal))),
          Expanded(flex: 10, child: Text(money(t.credit), style: display(16, color: MC.crimson))),
          Expanded(flex: 10, child: Text(money(t.remaining), style: display(16, color: MC.plum))),
          Expanded(
            flex: 13,
            child: Row(children: [
              Expanded(child: SplitBar(segments: [(pct, MC.burnt)], height: 8)),
              const SizedBox(width: 8),
              SizedBox(width: 40, child: Text('${(pct * 100).round()}%', style: const TextStyle(fontSize: 12, color: MC.mutedDeep))),
            ]),
          ),
          SizedBox(width: 150, child: Align(alignment: AlignmentDirectional.centerStart, child: RepStatusPill(r.status))),
        ]),
      ),
    );
  }
}
