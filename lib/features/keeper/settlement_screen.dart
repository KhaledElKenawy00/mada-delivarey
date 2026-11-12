import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../license/license_controller.dart';
import '../print/receipt.dart';

/// قايمة المناديب اللي محتاجين تسوية
class SettlementsScreen extends ConsumerWidget {
  const SettlementsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(warehouseLiveProvider(null));
    return AsyncBody(
      value: live,
      onRetry: () => ref.invalidate(warehouseLiveProvider(null)),
      builder: (w) {
        final pending = w.reps.where((r) => r.status == RepStatus.pending).toList();
        final open = w.reps.where((r) => r.sessionId != null && r.inField).toList();
        final done = w.reps.where((r) => r.status == RepStatus.done).toList();
        Widget group(String title, List<RepLive> reps, String empty) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SectionTitle(title, hint: '${reps.length}'),
              if (reps.isEmpty) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(empty, style: const TextStyle(color: MC.muted))),
              for (var k = 0; k < reps.length; k++)
                LinedRow(
                  onTap: () => context.go('/keeper/settlement/${reps[k].sessionId}'),
                  child: Row(children: [
                    Avatar(reps[k].name, bg: toneFor(k).$1, fg: toneFor(k).$2),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(reps[k].name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                        Text('خرج ${hm(reps[k].startedAt)} · ${reps[k].totals.invoices} فاتورة', style: const TextStyle(fontSize: 12, color: MC.muted)),
                      ]),
                    ),
                    MiniStat('مبيعات', money(reps[k].totals.sold), color: MC.burntText),
                    const SizedBox(width: 28),
                    MiniStat('نقدية معاه', money(reps[k].totals.cashInHand), color: MC.teal),
                    const SizedBox(width: 28),
                    RepStatusPill(reps[k].status),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_left_rounded, color: MC.muted),
                  ]),
                ),
              const SizedBox(height: 24),
            ]);
        return DesktopPage(children: [
          const PageHeader(kicker: 'نهاية اليوم', title: 'تسوية العهد'),
          group('في انتظار اعتمادك', pending, 'مفيش مندوب قفل يومه لسه'),
          group('لسه في الشارع', open, 'مفيش مناديب في الشارع'),
          group('اتقفل النهارده', done, '—'),
        ]);
      },
    );
  }
}

class SettlementScreen extends ConsumerStatefulWidget {
  final String sessionId;
  const SettlementScreen({super.key, required this.sessionId});
  @override
  ConsumerState<SettlementScreen> createState() => _SettlementScreenState();
}

class _SettlementScreenState extends ConsumerState<SettlementScreen> {
  final _returns = <String, TextEditingController>{};
  final _received = TextEditingController();
  bool _init = false, _busy = false;

  @override
  void dispose() {
    for (final c in _returns.values) {
      c.dispose();
    }
    _received.dispose();
    super.dispose();
  }

  void _setup(SessionData s) {
    if (_init) return;
    _init = true;
    for (final it in s.items) {
      _returns[it.productId] = TextEditingController(text: qty(it.expectedReturn));
    }
    _received.text = money(s.expectedCash);
  }

  Future<void> _printSettlement(SessionData s, double expected, double received, double diff, double missing) async {
    final me = ref.read(profileProvider);
    final t = s.totals;
    await showReceiptDialog(
      context,
      ReceiptData(
        company: me.companyName ?? 'مدار',
        warehouse: me.warehouseName,
        title: 'محضر تسوية عهدة',
        number: s.issueNo,
        at: DateTime.now(),
        rep: s.repName,
        lines: [for (final it in s.items) if (it.returned > 0) ReceiptLine(it.name, it.returned, it.price)],
        totals: [
          ReceiptTotal('نقدي من الفواتير', money(t.cash)),
          ReceiptTotal('تحصيلات مديونيات', money(t.collections)),
          if (missing > 0) ReceiptTotal('قيمة بضاعة ناقصة', money(missing)),
          ReceiptTotal('المطلوب تسليمه', money(expected), bold: true),
          ReceiptTotal('المبلغ المستلم فعليًا', money(received), bold: true),
          ReceiptTotal(diff < 0 ? 'عجز على المندوب' : (diff > 0 ? 'زيادة' : 'مطابق'), money(diff.abs()), bold: true),
        ],
        footer: 'توقيع أمين المخزن: ...............',
      ),
    );
  }

  Future<void> _approve(SessionData s) async {
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).approveSettlement(
            s.sessionId,
            {for (final it in s.items) it.productId: parseNum(_returns[it.productId]!.text)},
            parseNum(_received.text),
          );
      ref.invalidate(warehouseLiveProvider(null));
      ref.invalidate(sessionDataProvider(s.sessionId));
      if (mounted) showDone(context, 'اتقفل يوم ${s.repName} والمرتجع رجع المخزن');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(sessionDataProvider(widget.sessionId));
    return AsyncBody(
      value: data,
      onRetry: () => ref.invalidate(sessionDataProvider(widget.sessionId)),
      builder: (s) {
        _setup(s);
        final closed = s.isClosed && s.settlement != null;
        final t = s.totals;

        // معاينة لحظية قبل الاعتماد
        var returnedValue = 0.0, missing = 0.0;
        for (final it in s.items) {
          final r = closed ? it.returned : parseNum(_returns[it.productId]?.text ?? '0');
          returnedValue += r * it.price;
          missing += (it.expectedReturn - r).clamp(0.0, double.infinity).toDouble() * it.price;
        }
        final expected = closed ? s.settlement!.expectedCash : t.cash + t.collections + missing;
        final received = closed ? s.settlement!.receivedCash : parseNum(_received.text);
        final diff = received - expected;

        return DesktopPage(maxWidth: 1360, children: [
          PageHeader(
            leading: Avatar(s.repName, size: 60, bg: MC.orange, fg: MC.ink),
            title: 'تسوية يوم ${s.repName}',
            kicker: [
              if (s.issueNo != null) 'إذن ${s.issueNo}',
              'خرج ${hm(s.startedAt)}',
              if (s.submittedAt != null) 'رجع ${hm(s.submittedAt)}',
              '${t.invoices} فاتورة',
            ].join(' · '),
            actions: [
              if (closed)
                const Pill('اليوم اتقفل', fg: MC.teal, bg: MC.tealTint)
              else if (s.isPending)
                const Pill('في انتظار اعتمادك', fg: MC.burntText, bg: MC.orangeTint)
              else
                const Pill('المندوب لسه ماقفلش يومه', fg: MC.crimson, bg: MC.crimsonTint),
            ],
          ),
          _Equation(items: [
            ('', 'بضاعة مصروفة', t.issued, MC.ink),
            ('−', 'مرتجع', returnedValue, MC.muted),
            ('=', 'مبيعات اليوم', t.sold + missing, MC.burnt),
            ('−', 'آجل على العملاء', t.credit, MC.crimson),
            ('+', 'تحصيلات قديمة', t.collections, MC.teal),
            ('=', 'نقدية مطلوبة', expected, MC.plum),
          ]),
          LayoutBuilder(builder: (context, c) {
            final items = _items(s, closed);
            final cash = _cashPanel(s, closed, expected, received, diff, missing);
            if (c.maxWidth < 1000) return Column(children: [items, const SizedBox(height: 28), cash]);
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 3, child: items),
              const SizedBox(width: 32),
              Expanded(flex: 2, child: cash),
            ]);
          }),
        ]);
      },
    );
  }

  Widget _items(SessionData s, bool closed) {
    const st = TextStyle(fontSize: 13, color: MC.muted);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('حركة الأصناف — المرتجع الفعلي'),
      WideTable(
        minWidth: 640,
        child: Column(children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: MC.ink, width: 2), bottom: BorderSide(color: MC.line))),
            child: const Row(children: [
              Expanded(flex: 14, child: Text('الصنف', style: st)),
              Expanded(flex: 10, child: Text('مستلم', style: st)),
              Expanded(flex: 10, child: Text('مباع', style: st)),
              Expanded(flex: 10, child: Text('مرتجع متوقع', style: st)),
              Expanded(flex: 12, child: Text('مرتجع فعلي', style: st)),
              SizedBox(width: 100, child: Text('الحالة', style: st)),
            ]),
          ),
          for (final it in s.items)
            Builder(builder: (context) {
              final actual = closed ? it.returned : parseNum(_returns[it.productId]!.text);
              final ok = actual == it.expectedReturn;
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: MC.line))),
                child: Row(children: [
                  Expanded(flex: 14, child: Text(it.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16))),
                  Expanded(flex: 10, child: Text(qty(it.issued), style: display(17))),
                  Expanded(flex: 10, child: Text(qty(it.sold), style: display(17, color: MC.burnt))),
                  Expanded(flex: 10, child: Text(qty(it.expectedReturn), style: display(17, color: MC.muted))),
                  Expanded(
                    flex: 12,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: SizedBox(
                        width: 90,
                        child: closed
                            ? Text(qty(it.returned), style: display(17))
                            : TextField(
                                controller: _returns[it.productId],
                                textAlign: TextAlign.center,
                                style: display(17),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                                onChanged: (_) => setState(() {}),
                              ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 100,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: ok
                          ? const Pill('مطابق', fg: MC.teal, bg: MC.tealTint, dot: false, fontSize: 12)
                          : Pill('ناقص ${qty(it.expectedReturn - actual)}', fg: MC.crimson, bg: MC.crimsonTint, dot: false, fontSize: 12),
                    ),
                  ),
                ]),
              );
            }),
        ]),
      ),
      const SizedBox(height: 10),
      const Text('المرتجعات بترجع لرصيد المخزن بعد الاعتماد فقط. أي نقص في البضاعة بيتحسب على المندوب بسعر البيع.',
          style: TextStyle(fontSize: 13, color: MC.muted)),
    ]);
  }

  Widget _cashPanel(SessionData s, bool closed, double expected, double received, double diff, double missing) {
    final t = s.totals;
    Widget line(String k, String v, {bool strong = false}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Text(k, style: TextStyle(color: strong ? Colors.white : MC.onDarkMuted, fontSize: 15)),
            const Spacer(),
            Text(v, style: display(strong ? 18 : 15, color: Colors.white)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DarkPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('جرد النقدية', style: display(18, color: Colors.white)),
          const SizedBox(height: 18),
          line('نقدي من الفواتير', money(t.cash)),
          line('تحصيلات مديونيات', money(t.collections)),
          if (missing > 0) line('قيمة بضاعة ناقصة', money(missing)),
          const Divider(color: MC.inkSoft),
          line('المطلوب تسليمه', money(expected), strong: true),
          const SizedBox(height: 10),
          const Text('المبلغ المستلم فعلياً', style: TextStyle(fontSize: 14, color: MC.onDarkMuted)),
          const SizedBox(height: 8),
          closed
              ? Text(money(received), style: display(28, color: Colors.white))
              : TextField(
                  controller: _received,
                  style: display(28, color: Colors.white),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    fillColor: const Color(0xFF2E1527),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: MC.orange, width: 2)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: MC.orange, width: 2)),
                  ),
                ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: diff < 0 ? const Color(0xFF4A0A1B) : (diff > 0 ? const Color(0xFF163E46) : MC.inkSoft),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              Text(diff < 0 ? 'عجز على المندوب' : (diff > 0 ? 'زيادة' : 'مطابق'),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFFFFD9DE))),
              const Spacer(),
              Text(diff == 0 ? '0' : '${diff < 0 ? '−' : '+'} ${money(diff.abs())}', style: display(24, weight: FontWeight.w700, color: Colors.white)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      Row(children: [
        const Text('آجل جديد على العملاء اليوم', style: TextStyle(color: MC.muted, fontSize: 14)),
        const Spacer(),
        Text(money(t.credit), style: display(16, color: MC.plum)),
      ]),
      const SizedBox(height: 16),
      if (!closed)
        FilledButton.icon(
          onPressed: _busy ? null : () => _approve(s),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(58)),
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.lock_outline_rounded),
          label: const Text('اعتماد وإغلاق يوم المندوب'),
        ),
      if (closed) ...[
        OutlinedButton.icon(
          onPressed: () => _printSettlement(s, expected, received, diff, missing),
          icon: const Icon(Icons.print_outlined),
          label: const Text('طباعة محضر التسوية'),
        ),
        const SizedBox(height: 10),
      ],
      OutlinedButton(onPressed: () => context.go('/keeper/report/${s.repId}'), child: const Text('تقرير المندوب')),
    ]);
  }
}

class _Equation extends StatelessWidget {
  final List<(String, String, double, Color)> items;
  const _Equation({required this.items});
  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: MC.ink, width: 2), bottom: BorderSide(color: MC.line))),
        child: Wrap(children: [
          for (final (op, label, v, color) in items)
            SizedBox(
              width: 210,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Row(children: [
                  SizedBox(width: 28, child: Text(op, textAlign: TextAlign.center, style: display(30, color: MC.onDarkMuted))),
                  const SizedBox(width: 10),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label, style: const TextStyle(fontSize: 13, color: MC.muted)),
                    Text(money(v), style: display(28, color: color)),
                  ]),
                ]),
              ),
            ),
        ]),
      );
}
