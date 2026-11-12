import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// استيراد الأصناف والعملاء من Excel (.xlsx) أو CSV.
/// أول صف لازم يكون العناوين — الأعمدة بتتعرف بالعربي أو الإنجليزي وبأي ترتيب.
enum ImportKind { products, customers }

class _Col {
  final String key, label;
  final bool required;
  final List<String> aliases;
  const _Col(this.key, this.label, this.aliases, {this.required = false});
}

const _productCols = [
  _Col('code', 'code', ['code', 'كود', 'كود الصنف', 'الكود', 'sku', 'item code'], required: true),
  _Col('name', 'desc', ['desc', 'description', 'اسم', 'الاسم', 'اسم الصنف', 'الصنف', 'وصف', 'الوصف', 'name', 'item', 'product'], required: true),
];

const _customerCols = [
  _Col('code', 'code', ['code', 'كود', 'كود العميل', 'الكود', 'customer code']),
  _Col('name', 'desc', ['desc', 'description', 'اسم', 'الاسم', 'اسم العميل', 'العميل', 'وصف', 'الوصف', 'name', 'customer'], required: true),
];

String _norm(String v) => v
    .trim()
    .toLowerCase()
    .replaceAll(RegExp('[أإآ]'), 'ا')
    .replaceAll('ة', 'ه')
    .replaceAll('ى', 'ي')
    .replaceAll(RegExp(r'\s+'), ' ');

/// بيقرا الملف ويرجّع صفوف كـ Map<عمود, قيمة>
List<Map<String, String>> _readTable(Uint8ListLike bytes, String ext, List<_Col> cols) {
  List<List<String>> grid;
  if (ext == 'csv') {
    final text = utf8.decode(bytes, allowMalformed: true).replaceFirst('﻿', '');
    final sep = text.split('\n').first.contains(';') && !text.split('\n').first.contains(',') ? ';' : ',';
    grid = [
      for (final line in const LineSplitter().convert(text))
        if (line.trim().isNotEmpty) line.split(sep).map((c) => c.trim().replaceAll('"', '')).toList()
    ];
  } else {
    final ex = Excel.decodeBytes(bytes);
    if (ex.tables.isEmpty) return [];
    final sheet = ex.tables[ex.tables.keys.first]!;
    grid = [
      for (final row in sheet.rows) [for (final c in row) c?.value == null ? '' : '${c!.value}'.trim()]
    ];
  }
  if (grid.isEmpty) return [];

  // أول صف فيه عنوان معروف = صف العناوين
  var headerRow = 0;
  for (var k = 0; k < grid.length && k < 10; k++) {
    if (grid[k].any((h) => cols.any((c) => c.aliases.map(_norm).contains(_norm(h))))) {
      headerRow = k;
      break;
    }
  }
  final header = grid[headerRow];
  final index = <String, int>{};
  for (var k = 0; k < header.length; k++) {
    final h = _norm(header[k]);
    for (final c in cols) {
      if (!index.containsKey(c.key) && c.aliases.map(_norm).contains(h)) index[c.key] = k;
    }
  }
  final missing = cols.where((c) => c.required && !index.containsKey(c.key)).map((c) => c.label).toList();
  if (missing.isNotEmpty) throw FormatException('الأعمدة دي ناقصة في الملف: ${missing.join('، ')}');

  return [
    for (final row in grid.skip(headerRow + 1))
      if (row.any((v) => v.trim().isNotEmpty))
        {for (final e in index.entries) e.key: e.value < row.length ? row[e.value].trim() : ''}
  ];
}

typedef Uint8ListLike = List<int>;

/// زرار الاستيراد: اختيار ملف → معاينة → تأكيد → رفع
Future<void> startExcelImport(BuildContext context, WidgetRef ref, ImportKind kind) async {
  PlatformFile? file;
  Uint8ListLike? bytes;
  try {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'csv'],
      withData: true,
    );
    file = picked?.files.singleOrNull;
    if (file == null) return;
    bytes = file.bytes ?? (file.path == null ? null : await File(file.path!).readAsBytes());
  } catch (e) {
    if (context.mounted) showError(context, 'مافتحش الملف: $e');
    return;
  }
  if (bytes == null) {
    if (context.mounted) showError(context, 'الملف فاضي أو مقدرش يتقرا');
    return;
  }
  final ext = (file.extension ?? '').toLowerCase();

  final List<Map<String, String>> rows;
  try {
    rows = _readTable(bytes, ext, kind == ImportKind.products ? _productCols : _customerCols);
  } on FormatException catch (e) {
    if (context.mounted) showError(context, e.message);
    return;
  } catch (e) {
    if (context.mounted) showError(context, 'الملف مش مقروء: $e');
    return;
  }

  final errors = <String>[];
  final products = <ProductImport>[];
  final customers = <CustomerImport>[];
  for (var k = 0; k < rows.length; k++) {
    final r = rows[k];
    final line = k + 2;
    if (kind == ImportKind.products) {
      if ((r['code'] ?? '').isEmpty || (r['name'] ?? '').isEmpty) {
        errors.add('صف $line: الكود أو الاسم فاضي');
        continue;
      }
      products.add(ProductImport(
        code: r['code']!,
        name: r['name']!,
        unit: 'كرتونة',
        price: 0,
      ));
    } else {
      if ((r['name'] ?? '').isEmpty) {
        errors.add('صف $line: اسم العميل فاضي');
        continue;
      }
      String? opt(String k) => (r[k] ?? '').isEmpty ? null : r[k];
      customers.add(CustomerImport(
        name: r['name']!,
        code: opt('code'),
        phone: opt('phone'),
        area: opt('area'),
        address: opt('address'),
        creditLimit: parseNum(r['limit'] ?? ''),
        openingBalance: parseNum(r['balance'] ?? ''),
      ));
    }
  }
  if (!context.mounted) return;

  final count = kind == ImportKind.products ? products.length : customers.length;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(kind == ImportKind.products ? 'استيراد ${products.length} صنف' : 'استيراد ${customers.length} عميل'),
      content: SizedBox(
        width: 640,
        height: 420,
        child: ListView(children: [
          Text('من الملف: ${file!.name}', style: const TextStyle(color: MC.muted)),
          const SizedBox(height: 6),
          Text(
            kind == ImportKind.products
                ? 'الكود الموجود بيتحدث اسمه، والجديد بيتضاف على مخزنك.'
                : 'الكود الموجود بيتحدث (من غير ما يتغير رصيده الحالي)، والجديد بيتضاف على مخزنك.',
            style: const TextStyle(fontSize: 13, height: 1.6),
          ),
          if (errors.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: MC.orangeTint, borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${errors.length} ملاحظة', style: const TextStyle(fontWeight: FontWeight.w700, color: MC.burntText)),
                for (final e in errors.take(8)) Text(e, style: const TextStyle(fontSize: 12, color: MC.burntText)),
                if (errors.length > 8) Text('و ${errors.length - 8} كمان…', style: const TextStyle(fontSize: 12, color: MC.burntText)),
              ]),
            ),
          ],
          const SizedBox(height: 12),
          if (kind == ImportKind.products)
            for (final p in products.take(60))
              LinedRow(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  SizedBox(width: 90, child: Text(p.code, style: display(13, color: MC.muted))),
                  Expanded(child: Text(p.name)),
                ]),
              )
          else
            for (final c in customers.take(60))
              LinedRow(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  SizedBox(width: 90, child: Text(c.code ?? '—', style: display(13, color: MC.muted))),
                  Expanded(child: Text([c.name, c.area, c.phone].whereType<String>().join(' · '))),
                  if (c.openingBalance > 0) Text('عليه ${money(c.openingBalance)}', style: display(13, color: MC.crimson)),
                ]),
              ),
          if (count > 60) Padding(padding: const EdgeInsets.only(top: 8), child: Text('و ${count - 60} صف كمان', style: const TextStyle(color: MC.muted))),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(onPressed: count == 0 ? null : () => Navigator.pop(ctx, true), child: const Text('استيراد')),
      ],
    ),
  );
  if (ok != true) return;

  try {
    final repo = ref.read(repositoryProvider);
    final res = kind == ImportKind.products ? await repo.importProducts(products) : await repo.importCustomers(customers);
    ref.invalidate(warehouseLiveProvider(null));
    ref.invalidate(customersProvider);
    if (context.mounted) {
      showDone(context, 'اتضاف ${res.inserted} · اتحدث ${res.updated}${res.skipped > 0 ? ' · اتساب ${res.skipped}' : ''}');
    }
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

/// نموذج Excel فاضي بالعناوين الصح (بيتحفظ في Downloads)
Future<void> saveExcelTemplate(BuildContext context, ImportKind kind) async {
  final ex = Excel.createExcel();
  final sheetName = ex.getDefaultSheet() ?? 'Sheet1';
  final sheet = ex[sheetName];
  final cols = kind == ImportKind.products ? _productCols : _customerCols;
  sheet.appendRow([for (final c in cols) TextCellValue(c.label)]);
  if (kind == ImportKind.products) {
    sheet.appendRow([TextCellValue('P-101'), TextCellValue('لحمة')]);
  } else {
    sheet.appendRow([TextCellValue('C-001'), TextCellValue('سوبر ماركت الأمل')]);
  }
  final bytes = ex.save();
  if (bytes == null) return;
  try {
    final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? Directory.systemTemp.path;
    final dir = Directory('$home${Platform.pathSeparator}Downloads');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final f = File('${dir.path}${Platform.pathSeparator}madar-${kind == ImportKind.products ? 'products' : 'customers'}-template.xlsx');
    await f.writeAsBytes(bytes);
    if (context.mounted) showDone(context, 'النموذج اتحفظ في ${f.path}');
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

/// زرار قايمة: استيراد + تحميل نموذج
class ImportMenuButton extends ConsumerWidget {
  final ImportKind kind;
  const ImportMenuButton({super.key, required this.kind});
  @override
  Widget build(BuildContext context, WidgetRef ref) => MenuAnchor(
        builder: (context, controller, _) => OutlinedButton.icon(
          onPressed: () => controller.isOpen ? controller.close() : controller.open(),
          icon: const Icon(Icons.upload_file_rounded),
          label: const Text('استيراد من Excel'),
        ),
        menuChildren: [
          MenuItemButton(
            leadingIcon: const Icon(Icons.file_open_outlined),
            onPressed: () => startExcelImport(context, ref, kind),
            child: const Text('اختيار ملف (.xlsx / .csv)'),
          ),
          MenuItemButton(
            leadingIcon: const Icon(Icons.download_rounded),
            onPressed: () => saveExcelTemplate(context, kind),
            child: const Text('تحميل نموذج فاضي'),
          ),
        ],
      );
}
