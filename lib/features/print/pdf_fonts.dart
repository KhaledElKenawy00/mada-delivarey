import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

/// خط عربي واحد لكل مستندات الـ PDF (إيصالات وتقارير) — بيتحمّل مرة واحدة بس.
pw.Font? _arabicFont;

Future<pw.Font> arabicFont() async {
  final cached = _arabicFont;
  if (cached != null) return cached;
  final bytes = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
  final f = pw.Font.ttf(bytes);
  _arabicFont = f;
  return f;
}
