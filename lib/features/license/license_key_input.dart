import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';

/// MDR-XXXX-XXXX-XXXX — 3 خانات بتتنقل لوحدها، واللصق بيتوزع عليهم
class LicenseKeyInput extends StatefulWidget {
  final ValueChanged<String> onChanged;
  final bool dark;
  final double boxHeight;
  const LicenseKeyInput({super.key, required this.onChanged, this.dark = false, this.boxHeight = 60});

  @override
  State<LicenseKeyInput> createState() => LicenseKeyInputState();
}

class LicenseKeyInputState extends State<LicenseKeyInput> {
  final _c = List.generate(3, (_) => TextEditingController());
  final _f = List.generate(3, (_) => FocusNode());

  String get value => 'MDR-${_c.map((c) => c.text).join('-')}';

  /// بيملى المفتاح كله (من الحافظة أو من زرار تجربة)
  void fill(String raw) {
    var clean = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (clean.startsWith('MDR')) clean = clean.substring(3);
    for (var k = 0; k < 3; k++) {
      final start = k * 4;
      _c[k].text = start >= clean.length ? '' : clean.substring(start, (start + 4).clamp(0, clean.length));
    }
    widget.onChanged(value);
    final firstEmpty = _c.indexWhere((c) => c.text.length < 4);
    if (firstEmpty >= 0) _f[firstEmpty].requestFocus();
  }

  Future<void> pasteFromClipboard() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (d?.text != null) fill(d!.text!);
  }

  void _changed(int k, String v) {
    if (v.length > 4) {
      fill(v);
      return;
    }
    final up = v.toUpperCase();
    if (up != v) {
      _c[k].value = TextEditingValue(text: up, selection: TextSelection.collapsed(offset: up.length));
    }
    if (up.length == 4 && k < 2) _f[k + 1].requestFocus();
    if (up.isEmpty && k > 0) _f[k - 1].requestFocus();
    widget.onChanged(value);
  }

  @override
  void dispose() {
    for (final c in _c) {
      c.dispose();
    }
    for (final f in _f) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fillColor = widget.dark ? const Color(0xFFFBEFE8) : Colors.white;
    final border = widget.dark ? Colors.transparent : MC.ink;
    Widget box(Widget child, {double width = 100}) => SizedBox(
          width: width,
          height: widget.boxHeight,
          child: child,
        );
    final style = display(22, weight: FontWeight.w600, color: MC.ink, letterSpacing: 2);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        box(
          width: 84,
          Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.dark ? const Color(0xFFE5C8D5) : MC.plumTint,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text('MDR', style: style),
          ),
        ),
        for (var k = 0; k < 3; k++)
          box(
            TextField(
              controller: _c[k],
              focusNode: _f[k],
              textAlign: TextAlign.center,
              style: style,
              maxLength: 14, // يسمح باللصق، وبيتوزع
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-]'))],
              decoration: InputDecoration(
                counterText: '',
                filled: true,
                fillColor: fillColor,
                contentPadding: EdgeInsets.zero,
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: border, width: 2)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: MC.burnt, width: 2)),
              ),
              onChanged: (v) => _changed(k, v),
              onSubmitted: (_) {},
            ),
          ),
      ]),
    );
  }
}
