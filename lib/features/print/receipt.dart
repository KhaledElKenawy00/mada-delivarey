import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'pdf_fonts.dart';

/// إيصال حراري (فاتورة / تحصيل / كشف يوم).
/// بنرسم الإيصال كصورة بالـ Canvas ونطبعها bitmap — كده العربي بيطلع متوصّل وصح
/// على أي طابعة Sunmi، من غير ما نعتمد على خطوط الطابعة.
class ReceiptLine {
  final String name;
  final double qty, price;
  const ReceiptLine(this.name, this.qty, this.price);
  double get total => qty * price;
}

class ReceiptTotal {
  final String label, value;
  final bool bold;
  const ReceiptTotal(this.label, this.value, {this.bold = false});
}

class ReceiptData {
  final String company, title;
  final String? number, warehouse, rep, customer, footer;
  final DateTime at;
  final List<ReceiptLine> lines;
  final List<ReceiptTotal> totals;
  final bool offline;
  const ReceiptData({
    required this.company,
    required this.title,
    required this.at,
    this.number,
    this.warehouse,
    this.rep,
    this.customer,
    this.lines = const [],
    this.totals = const [],
    this.footer,
    this.offline = false,
  });
}

/// 384 نقطة = ورق 58مم (V2 / V2s / L2 / P2 Lite) — 576 = ورق 80مم (T2 / V2 Pro 80)
class PaperWidth {
  static const mm58 = 384.0;
  static const mm80 = 576.0;
  static const _key = 'madar.paper_width';
  static Future<double> get() async => (await SharedPreferences.getInstance()).getDouble(_key) ?? mm58;
  static Future<void> set(double v) async => (await SharedPreferences.getInstance()).setDouble(_key, v);
}

Future<Uint8List> renderReceipt(ReceiptData r, {double width = PaperWidth.mm58}) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  const pad = 8.0;
  final inner = width - pad * 2;
  final scale = width / PaperWidth.mm58;
  c.drawRect(Rect.fromLTWH(0, 0, width, 6000), Paint()..color = Colors.white);
  var y = 10.0;

  TextPainter text(String s, double size, {FontWeight weight = FontWeight.w400, TextAlign align = TextAlign.right, double? max}) =>
      TextPainter(
        text: TextSpan(text: s, style: TextStyle(color: Colors.black, fontSize: size * scale, fontWeight: weight, height: 1.25)),
        textDirection: TextDirection.rtl,
        textAlign: align,
        maxLines: 3,
      )..layout(minWidth: max ?? inner, maxWidth: max ?? inner);

  void line(String s, double size, {FontWeight weight = FontWeight.w400, TextAlign align = TextAlign.right}) {
    final tp = text(s, size, weight: weight, align: align);
    tp.paint(c, Offset(pad, y));
    y += tp.height + 4;
  }

  void rule({bool dashed = true}) {
    final p = Paint()
      ..color = Colors.black
      ..strokeWidth = 1.5;
    if (!dashed) {
      c.drawLine(Offset(pad, y), Offset(width - pad, y), p);
    } else {
      for (var x = pad; x < width - pad; x += 10) {
        c.drawLine(Offset(x, y), Offset(x + 5, y), p);
      }
    }
    y += 10;
  }

  /// صف من 3 أعمدة: يمين / وسط / شمال
  void cols(String right, String mid, String left, double size, {FontWeight weight = FontWeight.w400}) {
    final wr = inner * 0.46, wm = inner * 0.28, wl = inner * 0.26;
    final a = text(right, size, weight: weight, max: wr);
    final b = text(mid, size, weight: weight, max: wm, align: TextAlign.center);
    final d = text(left, size, weight: weight, max: wl, align: TextAlign.left);
    a.paint(c, Offset(width - pad - wr, y));
    b.paint(c, Offset(pad + wl, y));
    d.paint(c, Offset(pad, y));
    y += [a.height, b.height, d.height].reduce((p, q) => p > q ? p : q) + 6;
  }

  void kv(String k, String v, double size, {FontWeight weight = FontWeight.w400}) {
    final a = text(k, size, weight: weight, max: inner * 0.6);
    final b = text(v, size, weight: weight, max: inner * 0.4, align: TextAlign.left);
    a.paint(c, Offset(width - pad - inner * 0.6, y));
    b.paint(c, Offset(pad, y));
    y += (a.height > b.height ? a.height : b.height) + 4;
  }

  line(r.company, 30, weight: FontWeight.w700, align: TextAlign.center);
  if (r.warehouse != null) line(r.warehouse!, 20, align: TextAlign.center);
  y += 4;
  line(r.title, 26, weight: FontWeight.w700, align: TextAlign.center);
  if (r.number != null) line(r.number!, 20, align: TextAlign.center);
  if (r.offline) line('(محفوظة أوفلاين — الرقم النهائي بعد الرفع)', 16, align: TextAlign.center);
  rule();
  kv('التاريخ', '${r.at.day}/${r.at.month}/${r.at.year}  ${hm(r.at)}', 20);
  if (r.rep != null) kv('المندوب', r.rep!, 20);
  if (r.customer != null) kv('العميل', r.customer!, 22, weight: FontWeight.w700);
  rule();
  if (r.lines.isNotEmpty) {
    cols('الصنف', 'كمية × سعر', 'الإجمالي', 19, weight: FontWeight.w700);
    rule(dashed: false);
    for (final l in r.lines) {
      cols(l.name, '${qty(l.qty)} × ${money(l.price)}', money(l.total), 21);
    }
    rule();
  }
  for (final t in r.totals) {
    kv(t.label, t.value, t.bold ? 26 : 21, weight: t.bold ? FontWeight.w700 : FontWeight.w400);
  }
  if (r.footer != null) {
    rule();
    line(r.footer!, 18, align: TextAlign.center);
  }
  y += 10;
  line('مدار — نظام التوزيع', 15, align: TextAlign.center);
  y += 16;

  final img = await rec.endRecording().toImage(width.round(), y.ceil());
  final png = await img.toByteData(format: ui.ImageByteFormat.png);
  return png!.buffer.asUint8List();
}

/// نفس محتوى [renderReceipt] بس PDF مقاس A4 — للطباعة من أي شاشة (موبايل أو ديسكتوب)
/// على أي طابعة عادية، مش الحرارية بس.
Future<Uint8List> renderReceiptPdf(ReceiptData r) async {
  final font = await arabicFont();
  final doc = pw.Document();
  final bold = pw.TextStyle(font: font, fontSize: 14, fontWeight: pw.FontWeight.bold);
  final normal = pw.TextStyle(font: font, fontSize: 11);

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      theme: pw.ThemeData.withFont(base: font, bold: font),
      build: (ctx) => pw.Directionality(
        textDirection: pw.TextDirection.rtl,
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          pw.Text(r.company, style: pw.TextStyle(font: font, fontSize: 20, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
          if (r.warehouse != null) pw.Text(r.warehouse!, style: normal, textAlign: pw.TextAlign.center),
          pw.SizedBox(height: 10),
          pw.Text(r.title, style: pw.TextStyle(font: font, fontSize: 16, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
          if (r.number != null) pw.Text(r.number!, style: normal, textAlign: pw.TextAlign.center),
          if (r.offline) pw.Text('(محفوظة أوفلاين — الرقم النهائي بعد الرفع)', style: normal, textAlign: pw.TextAlign.center),
          pw.SizedBox(height: 8),
          pw.Divider(),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('${r.at.day}/${r.at.month}/${r.at.year}  ${hm(r.at)}', style: normal),
            if (r.rep != null) pw.Text('المندوب: ${r.rep}', style: normal),
          ]),
          if (r.customer != null) pw.Padding(padding: const pw.EdgeInsets.only(top: 6), child: pw.Text('العميل: ${r.customer}', style: bold)),
          pw.SizedBox(height: 8),
          if (r.lines.isNotEmpty)
            pw.TableHelper.fromTextArray(
              tableDirection: pw.TextDirection.rtl,
              headerDirection: pw.TextDirection.rtl,
              headerStyle: bold,
              cellStyle: normal,
              headers: const ['الصنف', 'كمية × سعر', 'الإجمالي'],
              data: [for (final l in r.lines) [l.name, '${qty(l.qty)} × ${money(l.price)}', money(l.total)]],
            ),
          pw.SizedBox(height: 10),
          for (final t in r.totals)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text(t.label, style: t.bold ? bold : normal),
                pw.Text(t.value, style: t.bold ? bold : normal),
              ]),
            ),
          if (r.footer != null) ...[
            pw.Divider(),
            pw.Text(r.footer!, style: normal, textAlign: pw.TextAlign.center),
          ],
        ]),
      ),
    ),
  );
  return doc.save();
}

class ReceiptPrinter {
  static bool? _sunmi;

  static Future<bool> isSunmi() async {
    if (_sunmi != null) return _sunmi!;
    if (!Platform.isAndroid) return _sunmi = false;
    final a = await DeviceInfoPlugin().androidInfo;
    return _sunmi = a.manufacturer.toUpperCase().contains('SUNMI') || a.brand.toUpperCase().contains('SUNMI');
  }

  /// كل التعامل مع مكتبة sunmi_printer_plus في الدالة دي بس
  static Future<void> printPng(Uint8List png) async {
    await SunmiPrinter.printImage(png);
    await SunmiPrinter.lineWrap(3);
    try {
      await SunmiPrinter.cutPaper(); // الأجهزة اللي مفيهاش قطّاع بتتجاهلها
    } catch (_) {}
  }
}

/// معاينة الإيصال + زرار طباعة (بيتفعل على أجهزة Sunmi)
Future<void> showReceiptDialog(BuildContext context, ReceiptData data, {bool autoPrint = false}) async {
  final width = await PaperWidth.get();
  final png = await renderReceipt(data, width: width);
  final sunmi = await ReceiptPrinter.isSunmi();
  if (!context.mounted) return;

  Future<void> doPrint(BuildContext ctx) async {
    try {
      await ReceiptPrinter.printPng(png);
    } catch (e) {
      if (ctx.mounted) showError(ctx, 'الطباعة فشلت: $e');
    }
  }

  if (autoPrint && sunmi) await doPrint(context);
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: MC.ground,
    builder: (ctx) => SizedBox(
      height: MediaQuery.of(ctx).size.height * 0.85,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            Text(data.title, style: display(20)),
            const Spacer(),
            PopupMenuButton<double>(
              tooltip: 'مقاس الورق',
              initialValue: width,
              onSelected: (w) async {
                await PaperWidth.set(w);
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) await showReceiptDialog(context, data);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: PaperWidth.mm58, child: Text('ورق 58 مم')),
                PopupMenuItem(value: PaperWidth.mm80, child: Text('ورق 80 مم')),
              ],
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(width == PaperWidth.mm58 ? '58 مم ▾' : '80 مم ▾', style: const TextStyle(color: MC.muted)),
              ),
            ),
          ]),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 340),
                decoration: BoxDecoration(boxShadow: const [BoxShadow(color: Color(0x2222101C), blurRadius: 12)], borderRadius: BorderRadius.circular(4)),
                child: Image.memory(png, fit: BoxFit.fitWidth, filterQuality: FilterQuality.medium),
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 16 + MediaQuery.of(ctx).padding.bottom),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: sunmi ? () => doPrint(ctx) : null,
                  style: FilledButton.styleFrom(backgroundColor: MC.plum, minimumSize: const Size.fromHeight(54)),
                  icon: const Icon(Icons.print_rounded),
                  label: Text(sunmi ? 'طباعة ريسيت' : 'الطباعة الحرارية على أجهزة Sunmi بس', overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      await Printing.layoutPdf(onLayout: (_) => renderReceiptPdf(data), name: '${data.title} ${data.number ?? ''}'.trim());
                    } catch (e) {
                      if (ctx.mounted) showError(ctx, 'الطباعة فشلت: $e');
                    }
                  },
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                  icon: const Icon(Icons.description_outlined),
                  label: const Text('طباعة A4'),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('تمام')),
          ]),
        ),
      ]),
    ),
  );
}
