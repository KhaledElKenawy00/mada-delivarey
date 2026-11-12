import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../license/license_controller.dart';
import '../print/receipt.dart';
import 'offline_queue.dart';
import 'rep_widgets.dart';
import 'tracking.dart';

/// كشف حساب اليوم + إنهاء يوم العمل
class DayEndScreen extends ConsumerStatefulWidget {
  const DayEndScreen({super.key});
  @override
  ConsumerState<DayEndScreen> createState() => _DayEndScreenState();
}

class _DayEndScreenState extends ConsumerState<DayEndScreen> {
  bool _busy = false;

  Future<void> _finish() async {
    final queue = ref.read(offlineQueueProvider);
    await queue.flush();
    if (!mounted) return;
    if (queue.length > 0) {
      showError(context, 'لسه فيه ${queue.length} عملية ماترفعتش. اتصل بالنت الأول.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إنهاء يوم العمل؟'),
        content: const Text('مش هتقدر تعمل فواتير تاني النهارده. سلّم النقدية والمرتجع لأمين المخزن.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لسه')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إنهاء اليوم')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).submitDayEnd();
      await ref.read(trackingProvider.notifier).stop();
      ref.invalidate(myCustodyProvider);
      if (mounted) showDone(context, 'اتقفل يومك — مستني اعتماد أمين المخزن');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final custody = ref.watch(myCustodyProvider);
    final queue = ref.watch(offlineQueueProvider);
    return Scaffold(
      bottomNavigationBar: const RepBottomNav(index: 2),
      appBar: AppBar(
        backgroundColor: MC.ground,
        automaticallyImplyLeading: false,
        title: Text('كشف حساب اليوم', style: display(20)),
      ),
      body: AsyncBody<SessionData?>(
        value: custody,
        onRetry: () => ref.invalidate(myCustodyProvider),
        builder: (s) {
          if (s == null) return const Center(child: Text('مفيش يوم عمل النهارده'));
          final t = s.totals;
          final cash = t.cash + t.collections + queue.pendingCash;
          final sold = t.sold + queue.pendingSales;
          final returns = [for (final it in s.items) if (it.expectedReturn > 0) it];
          final retValue = s.items.fold<double>(0, (a, it) => a + it.expectedReturn * it.price);
          final whole = t.issued == 0 ? 1.0 : t.issued;
          return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 28), children: [
            Text('${dayLabel(s.startedAt ?? DateTime.now())} · ${t.invoices} فاتورة', style: const TextStyle(color: MC.muted)),
            const SizedBox(height: 12),
            const Text('النقدية اللي هتسلّمها لأمين المخزن', style: TextStyle(fontSize: 14, color: MC.muted)),
            Text.rich(TextSpan(children: [
              TextSpan(text: money(cash), style: display(52, weight: FontWeight.w700, color: MC.plum, letterSpacing: -1.5)),
              TextSpan(text: ' ج', style: display(18, weight: FontWeight.w500, color: MC.muted)),
            ])),
            const SizedBox(height: 14),
            SplitBar(height: 14, gap: 3, segments: [
              (t.cash / whole, MC.teal),
              (t.credit / whole, MC.crimson),
              (retValue / whole, const Color(0xFFD9CBBF)),
            ]),
            const SizedBox(height: 8),
            const Wrap(spacing: 14, children: [
              LegendDot('نقدي', MC.teal),
              LegendDot('آجل', MC.crimson),
              LegendDot('مرتجع', Color(0xFFD9CBBF)),
            ]),
            const SizedBox(height: 12),
            for (final (k, v, c) in [
              ('بضاعة مستلمة', t.issued, MC.ink),
              ('مبيعات', sold, MC.burntText),
              ('منها نقدي', t.cash + (queue.pendingCash), MC.teal),
              ('منها آجل على العملاء', t.credit, MC.crimson),
              ('تحصيلات مديونيات قديمة', t.collections, MC.teal),
            ])
              LinedRow(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(children: [
                  Text(k, style: const TextStyle(fontSize: 15, color: MC.mutedDeep)),
                  const Spacer(),
                  Text(money(v), style: display(17, color: c)),
                ]),
              ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: MC.line), borderRadius: BorderRadius.circular(16)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('المرتجع للمخزن', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                if (returns.isEmpty) const Text('بعت كل العهدة', style: TextStyle(color: MC.teal)),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final it in returns)
                    Chip(
                      backgroundColor: MC.plumTint,
                      side: BorderSide.none,
                      label: Text('${it.name} ${qty(it.expectedReturn)}'),
                    ),
                ]),
              ]),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: () {
                final me = ref.read(profileProvider);
                showReceiptDialog(
                  context,
                  ReceiptData(
                    company: me.companyName ?? 'مدار',
                    warehouse: me.warehouseName,
                    title: 'كشف حساب اليوم',
                    number: s.issueNo,
                    at: DateTime.now(),
                    rep: me.fullName,
                    lines: [for (final it in s.items) if (it.sold > 0) ReceiptLine(it.name, it.sold, it.price)],
                    totals: [
                      ReceiptTotal('بضاعة مستلمة', '${money(t.issued)} ج'),
                      ReceiptTotal('مبيعات', '${money(sold)} ج'),
                      ReceiptTotal('آجل على العملاء', '${money(t.credit)} ج'),
                      ReceiptTotal('تحصيلات قديمة', '${money(t.collections)} ج'),
                      for (final it in returns) ReceiptTotal('مرتجع ${it.name}', qty(it.expectedReturn)),
                      ReceiptTotal('النقدية المطلوب تسليمها', '${money(cash)} ج', bold: true),
                    ],
                    footer: 'توقيع أمين المخزن: ...............',
                  ),
                );
              },
              icon: const Icon(Icons.print_outlined),
              label: const Text('طباعة كشف اليوم'),
            ),
            const SizedBox(height: 12),
            if (s.isOpen)
              FilledButton.icon(
                onPressed: _busy ? null : _finish,
                style: FilledButton.styleFrom(backgroundColor: MC.ink, minimumSize: const Size.fromHeight(58)),
                icon: const Icon(Icons.power_settings_new_rounded, color: MC.orange),
                label: const Text('إنهاء يوم العمل'),
              )
            else
              const Pill('قفلت يومك — مستني اعتماد أمين المخزن', fg: MC.teal, bg: MC.tealTint),
            const SizedBox(height: 10),
            const Text('اليوم يتقفل والتتبع يقف بعد ما أمين المخزن يعتمد التسوية.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: MC.muted, height: 1.6)),
          ]);
        },
      ),
    );
  }
}
