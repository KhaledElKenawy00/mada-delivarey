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
import '../license/license_controller.dart';
import '../print/report_pdf.dart';

enum _Period { day, month }

/// تقرير الأرباح (سعر البيع - سعر التكلفة الحقيقي): أمين المخزن يشوف مخزنه،
/// مدير الشركة يشوف كل المخازن.
class ProfitReportScreen extends ConsumerStatefulWidget {
  const ProfitReportScreen({super.key});
  @override
  ConsumerState<ProfitReportScreen> createState() => _ProfitReportScreenState();
}

class _ProfitReportScreenState extends ConsumerState<ProfitReportScreen> {
  _Period _period = _Period.day;
  DateTime _date = DateTime.now();

  ProfitArgs _args(String? whId) {
    final d = DateTime(_date.year, _date.month, _date.day);
    if (_period == _Period.day) return (from: d, to: d, warehouseId: whId);
    return (from: DateTime(d.year, d.month, 1), to: DateTime(d.year, d.month + 1, 0), warehouseId: whId);
  }

  void _shift(int dir) => setState(() {
        _date = _period == _Period.day
            ? _date.add(Duration(days: dir))
            : DateTime(_date.year, _date.month + dir, math.min(_date.day, 28));
      });

  Future<void> _export(ProfitReport r) async {
    final b = StringBuffer('﻿');
    final title = _period == _Period.day ? dayLabel(_date) : monthLabel(_date);
    b.writeln('تقرير الأرباح,$title');
    b.writeln('المبيعات,${r.revenue}\nالتكلفة,${r.cost}\nالربح,${r.profit}');
    b.writeln('\nالصنف,الكمية,المبيعات,التكلفة,الربح');
    for (final i in r.items) {
      b.writeln('${i.name},${i.qty},${i.revenue},${i.cost},${i.profit}');
    }
    b.writeln('\nاليوم,المبيعات,التكلفة,الربح');
    for (final d in r.days) {
      b.writeln('${d.day.year}-${d.day.month}-${d.day.day},${d.revenue},${d.cost},${d.profit}');
    }
    try {
      final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? Directory.systemTemp.path;
      final dir = Directory('$home${Platform.pathSeparator}Downloads');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final stamp = '${_date.year}-${_date.month.toString().padLeft(2, '0')}${_period == _Period.day ? '-${_date.day.toString().padLeft(2, '0')}' : ''}';
      final f = File('${dir.path}${Platform.pathSeparator}madar-profit-$stamp.csv');
      await f.writeAsString(b.toString());
      if (mounted) showDone(context, 'اتحفظ في ${f.path}');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _printPdf(ProfitReport r) async {
    final monthly = _period == _Period.month;
    final periodLabel = monthly ? 'ربح شهر ${monthLabel(_date)}' : 'ربح يوم ${dayLabel(_date)}';
    try {
      await Printing.layoutPdf(onLayout: (_) => buildProfitReportPdf(r, monthly: monthly, periodLabel: periodLabel), name: 'تقرير الأرباح');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(profileProvider);
    final whId = me.role == Role.keeper ? me.warehouseId : null;
    final args = _args(whId);
    final data = ref.watch(profitReportProvider(args));
    return AsyncBody<ProfitReport>(
      value: data,
      onRetry: () => ref.invalidate(profitReportProvider(args)),
      builder: (r) {
        final day = _period == _Period.day;
        return DesktopPage(children: [
          PageHeader(
            title: 'الأرباح',
            kicker: [day ? 'ربح يوم ${dayLabel(_date)}' : 'ربح شهر ${monthLabel(_date)}', me.warehouseName].whereType<String>().join(' · '),
            actions: [
              Segmented<_Period>(
                options: const [(_Period.day, 'يومي'), (_Period.month, 'شهري')],
                value: _period,
                onChanged: (v) => setState(() => _period = v),
              ),
              IconButton.outlined(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_right_rounded), tooltip: 'السابق'),
              IconButton.outlined(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_left_rounded), tooltip: 'التالي'),
              OutlinedButton.icon(onPressed: () => _export(r), icon: const Icon(Icons.download_rounded), label: const Text('Excel')),
              OutlinedButton.icon(onPressed: () => _printPdf(r), icon: const Icon(Icons.print_outlined), label: const Text('طباعة PDF')),
            ],
          ),
          StatStrip(minWidth: 150, valueSize: 28, items: [
            StatItem('المبيعات', money(r.revenue), color: MC.burnt),
            StatItem('التكلفة', money(r.cost), color: MC.muted),
            StatItem('الربح', money(r.profit), color: r.profit >= 0 ? MC.teal : MC.crimson),
          ]),
          if (day) _itemsTable(r) else _monthly(r),
        ]);
      },
    );
  }

  Widget _itemsTable(ProfitReport r) {
    const st = TextStyle(fontSize: 13, color: MC.muted);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('الربح بالصنف'),
      Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: MC.line))),
        child: const Row(children: [
          Expanded(flex: 13, child: Text('الصنف', style: st)),
          Expanded(flex: 9, child: Text('الكمية', style: st)),
          Expanded(flex: 10, child: Text('المبيعات', style: st)),
          Expanded(flex: 10, child: Text('التكلفة', style: st)),
          Expanded(flex: 10, child: Text('الربح', style: st)),
        ]),
      ),
      if (r.items.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('مفيش مبيعات في اليوم ده', style: TextStyle(color: MC.muted))),
      for (final i in r.items)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: MC.line))),
          child: Row(children: [
            Expanded(flex: 13, child: Text(i.name, style: const TextStyle(fontWeight: FontWeight.w600))),
            Expanded(flex: 9, child: Text(qty(i.qty), style: display(16))),
            Expanded(flex: 10, child: Text(money(i.revenue), style: display(16))),
            Expanded(flex: 10, child: Text(money(i.cost), style: display(16, color: MC.muted))),
            Expanded(flex: 10, child: Text(money(i.profit), style: display(16, color: i.profit >= 0 ? MC.teal : MC.crimson))),
          ]),
        ),
    ]);
  }

  Widget _monthly(ProfitReport r) {
    final max = r.days.isEmpty ? 1.0 : r.days.map((d) => d.revenue).reduce(math.max);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('المبيعات والربح يوم بيوم', hint: 'ألف جنيه'),
      SizedBox(
        height: 250,
        child: r.days.isEmpty
            ? const Center(child: Text('مفيش مبيعات في الشهر ده', style: TextStyle(color: MC.muted)))
            : Directionality(
                textDirection: TextDirection.ltr,
                child: Container(
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: MC.onDarkMuted))),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    for (final d in r.days)
                      Expanded(
                        child: Tooltip(
                          message: '${dayLabel(d.day)}\nمبيعات ${money(d.revenue)}\nربح ${money(d.profit)}',
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                              FittedBox(child: Text((d.revenue / 1000).toStringAsFixed(1), style: display(10, color: MC.muted))),
                              const SizedBox(height: 4),
                              Container(
                                height: math.max(4.0, d.revenue / max * 190),
                                decoration: BoxDecoration(
                                  color: d.profit >= 0 ? MC.teal : MC.crimson,
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
      _itemsTable(r),
    ]);
  }
}
