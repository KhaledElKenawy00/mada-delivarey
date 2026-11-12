import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/format.dart';
import '../../data/models.dart';
import 'pdf_fonts.dart';

String _movementLabel(String kind) => switch (kind) {
      'receive' => 'استلام',
      'issue' => 'صرف لمندوب',
      'return' => 'مرتجع',
      'sale' => 'بيع',
      _ => kind,
    };

Future<pw.Document> _blankDoc() async {
  final font = await arabicFont();
  final doc = pw.Document(theme: pw.ThemeData.withFont(base: font, bold: font));
  return doc;
}

pw.Widget _header(pw.Font font, String title, String sub) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Text(title, style: pw.TextStyle(font: font, fontSize: 20, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
      pw.SizedBox(height: 4),
      pw.Text(sub, style: pw.TextStyle(font: font, fontSize: 12), textAlign: pw.TextAlign.center),
      pw.SizedBox(height: 14),
      pw.Divider(),
    ]);

pw.Widget _statBox(pw.Font font, List<(String, String)> items) => pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
      children: [
        for (final (label, value) in items)
          pw.Column(children: [
            pw.Text(value, style: pw.TextStyle(font: font, fontSize: 15, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 3),
            pw.Text(label, style: pw.TextStyle(font: font, fontSize: 10)),
          ]),
      ],
    );

pw.Widget _table(pw.Font font, List<String> headers, List<List<String>> rows) => pw.TableHelper.fromTextArray(
      tableDirection: pw.TextDirection.rtl,
      headerDirection: pw.TextDirection.rtl,
      headerStyle: pw.TextStyle(font: font, fontSize: 10, fontWeight: pw.FontWeight.bold),
      cellStyle: pw.TextStyle(font: font, fontSize: 9),
      headers: headers,
      data: rows,
    );

/// تقرير مندوب (يومي/شهري) — نفس بيانات تصدير الـ CSV الموجود في rep_report_screen.dart
Future<Uint8List> buildRepReportPdf(RepReport r, {required bool monthly, required String periodLabel}) async {
  final font = await arabicFont();
  final doc = await _blankDoc();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (ctx) => [
        pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
            _header(font, 'تقرير ${r.repName}', [periodLabel, r.warehouse, r.device].whereType<String>().join(' · ')),
            _statBox(font, [
              ('مبيعات', money(r.sales)),
              ('نقدي', money(r.cash)),
              ('آجل', money(r.credit)),
              ('تحصيلات قديمة', money(r.collections)),
              ('عجز', money(r.deficit.abs())),
            ]),
            pw.SizedBox(height: 16),
            pw.Text('حركة الأصناف', style: pw.TextStyle(font: font, fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            _table(font, const ['الصنف', 'استلم', 'باع', 'رجّع', 'القيمة'],
                [for (final i in r.items) [i.name, qty(i.issued), qty(i.sold), qty(i.returned), money(i.value)]]),
            pw.SizedBox(height: 16),
            if (monthly) ...[
              pw.Text('المبيعات يوم بيوم', style: pw.TextStyle(font: font, fontSize: 13, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              _table(font, const ['اليوم', 'المبيعات', 'العجز'],
                  [for (final d in r.days) [dateLabel(d.day), money(d.sales), d.deficit < 0 ? money(d.deficit.abs()) : '—']]),
            ] else ...[
              pw.Text('فواتير اليوم', style: pw.TextStyle(font: font, fontSize: 13, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              _table(font, const ['رقم الفاتورة', 'الوقت', 'العميل', 'الإجمالي', 'المدفوع', 'الآجل'],
                  [for (final v in r.invoiceList) [v.no, v.at == null ? '' : hm(v.at!), v.customer, money(v.total), money(v.paid), money(v.credit)]]),
            ],
          ]),
        ),
      ],
    ),
  );
  return doc.save();
}

/// تقرير الأرباح — نفس بيانات تصدير الـ CSV في profit_report_screen.dart
Future<Uint8List> buildProfitReportPdf(ProfitReport r, {required bool monthly, required String periodLabel}) async {
  final font = await arabicFont();
  final doc = await _blankDoc();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (ctx) => [
        pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
            _header(font, 'تقرير الأرباح', periodLabel),
            _statBox(font, [
              ('المبيعات', money(r.revenue)),
              ('التكلفة', money(r.cost)),
              ('الربح', money(r.profit)),
            ]),
            pw.SizedBox(height: 16),
            if (monthly) ...[
              pw.Text('يوم بيوم', style: pw.TextStyle(font: font, fontSize: 13, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              _table(font, const ['اليوم', 'المبيعات', 'التكلفة', 'الربح'],
                  [for (final d in r.days) [dateLabel(d.day), money(d.revenue), money(d.cost), money(d.profit)]]),
              pw.SizedBox(height: 16),
            ],
            pw.Text('الربح بالصنف', style: pw.TextStyle(font: font, fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            _table(font, const ['الصنف', 'الكمية', 'المبيعات', 'التكلفة', 'الربح'],
                [for (final i in r.items) [i.name, qty(i.qty), money(i.revenue), money(i.cost), money(i.profit)]]),
          ]),
        ),
      ],
    ),
  );
  return doc.save();
}

/// كشف حركة صنف — نفس بيانات product_ledger_screen.dart
Future<Uint8List> buildProductLedgerPdf(ProductLedger l) async {
  final font = await arabicFont();
  final doc = await _blankDoc();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (ctx) => [
        pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
            _header(font, 'كشف حركة — ${l.productName}', '${dateLabel(l.from)} → ${dateLabel(l.to)}'),
            _statBox(font, [
              ('في المخزن', '${qty(l.inStock)} ${l.unit}'),
              ('استلام', qty(l.received)),
              ('صرف لمناديب', qty(l.issued)),
              ('مرتجع', qty(l.returned)),
              ('مبيع', qty(l.sold)),
            ]),
            pw.SizedBox(height: 16),
            pw.Text('الحركات', style: pw.TextStyle(font: font, fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            _table(font, const ['التاريخ', 'النوع', 'التفاصيل', 'الكمية'], [
              for (final m in l.movements)
                [m.at == null ? '' : dateLabel(m.at!), _movementLabel(m.kind), m.title ?? '', '${m.qty > 0 ? '+' : ''}${qty(m.qty)} ${l.unit}'],
            ]),
          ]),
        ),
      ],
    ),
  );
  return doc.save();
}
