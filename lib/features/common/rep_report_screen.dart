import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../print/report_pdf.dart';

enum ReportPeriod { day, month }

/// تقرير المندوب اليومي/الشهري — بيظهر لأمين المخزن (مناديب مخزنه بس) ولمدير الشركة
class RepReportScreen extends ConsumerStatefulWidget {
  final String repId;
  const RepReportScreen({super.key, required this.repId});
  @override
  ConsumerState<RepReportScreen> createState() => _RepReportScreenState();
}

class _RepReportScreenState extends ConsumerState<RepReportScreen> {
  ReportPeriod _period = ReportPeriod.day;
  DateTime _date = DateTime.now();

  ReportArgs get _args {
    final d = DateTime(_date.year, _date.month, _date.day);
    if (_period == ReportPeriod.day) return (repId: widget.repId, from: d, to: d);
    return (repId: widget.repId, from: DateTime(d.year, d.month, 1), to: DateTime(d.year, d.month + 1, 0));
  }

  void _shift(int dir) => setState(() {
        _date = _period == ReportPeriod.day
            ? _date.add(Duration(days: dir))
            : DateTime(_date.year, _date.month + dir, math.min(_date.day, 28));
      });

  Future<void> _export(RepReport r) async {
    final b = StringBuffer('﻿');
    final title = _period == ReportPeriod.day ? dayLabel(_date) : monthLabel(_date);
    b.writeln('تقرير ${r.repName},$title');
    b.writeln('مبيعات,${r.sales}\nتحصيل نقدي,${r.cash}\nآجل,${r.credit}\nتحصيلات قديمة,${r.collections}\nمرتجع,${r.returned}\nعجز,${r.deficit}\nفواتير,${r.invoices}');
    b.writeln('\nالصنف,استلم,باع,رجّع,القيمة');
    for (final i in r.items) {
      b.writeln('${i.name},${i.issued},${i.sold},${i.returned},${i.value}');
    }
    if (_period == ReportPeriod.month) {
      b.writeln('\nاليوم,المبيعات,العجز');
      for (final d in r.days) {
        b.writeln('${d.day.year}-${d.day.month}-${d.day.day},${d.sales},${d.deficit}');
      }
    } else {
      b.writeln('\nرقم الفاتورة,الوقت,العميل,الإجمالي,المدفوع,الآجل');
      for (final v in r.invoiceList) {
        b.writeln('${v.no},${hm(v.at)},${v.customer.replaceAll(',', ' ')},${v.total},${v.paid},${v.credit}');
      }
    }
    try {
      final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? Directory.systemTemp.path;
      final dir = Directory('$home${Platform.pathSeparator}Downloads');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final stamp = '${_date.year}-${_date.month.toString().padLeft(2, '0')}${_period == ReportPeriod.day ? '-${_date.day.toString().padLeft(2, '0')}' : ''}';
      final f = File('${dir.path}${Platform.pathSeparator}madar-${r.repName.replaceAll(' ', '_')}-$stamp.csv');
      await f.writeAsString(b.toString());
      if (mounted) showDone(context, 'اتحفظ في ${f.path}');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _printPdf(RepReport r) async {
    final monthly = _period == ReportPeriod.month;
    final periodLabel = monthly ? 'تقرير شهر ${monthLabel(_date)}' : 'تقرير يوم ${dayLabel(_date)}';
    try {
      await Printing.layoutPdf(
        onLayout: (_) => buildRepReportPdf(r, monthly: monthly, periodLabel: periodLabel),
        name: 'تقرير ${r.repName}',
      );
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(repReportProvider(_args));
    return AsyncBody<RepReport>(
      value: data,
      onRetry: () => ref.invalidate(repReportProvider(_args)),
      builder: (r) {
        final day = _period == ReportPeriod.day;
        return DesktopPage(children: [
          PageHeader(
            leading: Avatar(r.repName, size: 60, bg: MC.orange, fg: MC.ink),
            title: r.repName,
            kicker: [day ? 'تقرير يوم ${dayLabel(_date)}' : 'تقرير شهر ${monthLabel(_date)}', r.warehouse, r.device]
                .whereType<String>()
                .join(' · '),
            actions: [
              Segmented<ReportPeriod>(
                options: const [(ReportPeriod.day, 'يومي'), (ReportPeriod.month, 'شهري')],
                value: _period,
                onChanged: (v) => setState(() => _period = v),
              ),
              IconButton.outlined(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_right_rounded), tooltip: 'السابق'),
              IconButton.outlined(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_left_rounded), tooltip: 'التالي'),
              OutlinedButton.icon(onPressed: () => _export(r), icon: const Icon(Icons.download_rounded), label: const Text('Excel')),
              OutlinedButton.icon(onPressed: () => _printPdf(r), icon: const Icon(Icons.print_outlined), label: const Text('طباعة PDF')),
            ],
          ),
          const Text('التقرير ده بيظهر لأمين المخزن (لمناديب مخزنه بس) ولمدير الشركة', style: TextStyle(fontSize: 13, color: MC.muted)),
          StatStrip(minWidth: 150, valueSize: 28, items: [
            StatItem(day ? 'مبيعات' : 'مبيعات الشهر', money(r.sales), color: MC.burnt),
            StatItem('تحصيل نقدي', money(r.cash), color: MC.teal),
            StatItem('آجل', money(r.credit), color: MC.crimson),
            if (day) StatItem('مرتجع', money(r.returned), color: MC.muted) else StatItem('متوسط اليوم', money(r.daysWorked == 0 ? 0 : r.sales / r.daysWorked)),
            if (day) StatItem('فواتير', '${r.invoices}') else StatItem('أيام عمل', '${r.daysWorked}', color: MC.plum),
            StatItem('عجز', money(r.deficit.abs()), color: MC.crimson),
          ]),
          if (day) _daily(r) else _monthly(r),
        ]);
      },
    );
  }

  Widget _daily(RepReport r) => LayoutBuilder(builder: (context, c) {
        final items = _itemsTable(r);
        final inv = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionTitle('فواتير اليوم', hint: '(${r.invoiceList.length})'),
          if (r.invoiceList.isEmpty) const Text('مفيش فواتير في اليوم ده', style: TextStyle(color: MC.muted)),
          for (final v in r.invoiceList.take(40))
            LinedRow(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(children: [
                SizedBox(width: 70, child: Text(hm(v.at), style: display(14, color: MC.muted))),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(v.customer, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    Text(v.no, style: const TextStyle(fontSize: 12, color: MC.muted), textDirection: TextDirection.ltr),
                  ]),
                ),
                v.credit == 0
                    ? const Pill('نقدي', fg: MC.teal, bg: MC.tealTint, dot: false, fontSize: 12)
                    : (v.paid == 0
                        ? const Pill('آجل', fg: MC.crimson, bg: MC.crimsonTint, dot: false, fontSize: 12)
                        : const Pill('جزئي', fg: MC.burntText, bg: MC.orangeTint, dot: false, fontSize: 12)),
                SizedBox(width: 90, child: Text(money(v.total), textAlign: TextAlign.left, style: display(16))),
              ]),
            ),
        ]);
        if (c.maxWidth < 1000) return Column(children: [items, const SizedBox(height: 28), inv]);
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: items),
          const SizedBox(width: 32),
          Expanded(child: inv),
        ]);
      });

  Widget _itemsTable(RepReport r) {
    const st = TextStyle(fontSize: 13, color: MC.muted);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('حركة الأصناف'),
      Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: MC.line))),
        child: const Row(children: [
          Expanded(flex: 13, child: Text('الصنف', style: st)),
          Expanded(flex: 10, child: Text('استلم', style: st)),
          Expanded(flex: 10, child: Text('باع', style: st)),
          Expanded(flex: 10, child: Text('رجّع', style: st)),
          Expanded(flex: 12, child: Text('القيمة', style: st)),
        ]),
      ),
      if (r.items.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('مفيش حركة', style: TextStyle(color: MC.muted))),
      for (final i in r.items)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: MC.line))),
          child: Row(children: [
            Expanded(flex: 13, child: Text(i.name, style: const TextStyle(fontWeight: FontWeight.w600))),
            Expanded(flex: 10, child: Text(qty(i.issued), style: display(16))),
            Expanded(flex: 10, child: Text(qty(i.sold), style: display(16, color: MC.burntText))),
            Expanded(flex: 10, child: Text(qty(i.returned), style: display(16, color: MC.muted))),
            Expanded(flex: 12, child: Text(money(i.value), style: display(16))),
          ]),
        ),
    ]);
  }

  Widget _monthly(RepReport r) {
    final max = r.days.isEmpty ? 1.0 : r.days.map((d) => d.sales).reduce(math.max);
    final totalItems = r.items.isEmpty ? 1.0 : r.items.map((i) => i.value).reduce(math.max);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('المبيعات يوم بيوم', hint: 'ألف جنيه · الأيام اللي فيها عجز باللون الأحمر'),
      SizedBox(
        height: 250,
        child: r.days.isEmpty
            ? const Center(child: Text('مفيش أيام عمل في الشهر ده', style: TextStyle(color: MC.muted)))
            : Directionality(
                textDirection: TextDirection.ltr,
                child: Container(
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: MC.onDarkMuted))),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    for (final d in r.days)
                      Expanded(
                        child: Tooltip(
                          message: '${dayLabel(d.day)}\n${money(d.sales)} ج${d.deficit < 0 ? '\nعجز ${money(d.deficit.abs())}' : ''}',
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                              FittedBox(child: Text((d.sales / 1000).toStringAsFixed(1), style: display(10, color: MC.muted))),
                              const SizedBox(height: 4),
                              Container(
                                height: math.max(4.0, d.sales / max * 190),
                                decoration: BoxDecoration(
                                  color: d.deficit < 0 ? MC.crimson : MC.burnt,
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(6), bottom: Radius.circular(2)),
                                ),
                              ),
                            ]),
                          ),
                        ),
                      ),
                  ]),
                ),
              ),
      ),
      Directionality(
        textDirection: TextDirection.ltr,
        child: Row(children: [
          for (final d in r.days)
            Expanded(child: Padding(padding: const EdgeInsets.only(top: 6), child: Text('${d.day.day}', textAlign: TextAlign.center, style: display(11, color: MC.muted)))),
        ]),
      ),
      const SizedBox(height: 32),
      LayoutBuilder(builder: (context, c) {
        final top = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionTitle('أعلى العملاء في الشهر'),
          for (final cu in r.topCustomers)
            LinedRow(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(children: [
                Expanded(child: Text(cu.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                if (cu.balance > 0) Text('عليه ${money(cu.balance)}', style: const TextStyle(fontSize: 13, color: MC.crimson)),
                const SizedBox(width: 16),
                SizedBox(width: 90, child: Text(money(cu.total), textAlign: TextAlign.left, style: display(16))),
              ]),
            ),
        ]);
        final items = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionTitle('الأصناف المباعة'),
          for (final i in r.items)
            LinedRow(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Text(i.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text('${qty(i.sold)} كرتونة · ${money(i.value)} ج', style: display(15)),
                ]),
                const SizedBox(height: 6),
                SplitBar(segments: [(i.value / totalItems, MC.plum)], height: 8),
              ]),
            ),
        ]);
        if (c.maxWidth < 1000) return Column(children: [top, const SizedBox(height: 28), items]);
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: top),
          const SizedBox(width: 32),
          Expanded(child: items),
        ]);
      }),
    ]);
  }
}
