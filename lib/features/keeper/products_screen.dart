import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../import/excel_import.dart';

// "كرتونة" مش ضمن اختيارات الوحدة الأساسية عمدًا — هي مفهوم منفصل
// (التعبئة الأكبر اللي بتتباع منها الوحدة الأساسية دي)، علشان ما تتلخبطش معاها.
const _unitChoices = ['عبوة', 'قطعة', 'كيلو', 'جرام', 'لتر', 'كيس', 'شيكارة', 'درزن'];
const _otherUnit = 'أخرى';

/// بيرجّع الاختيار المطابق للنص في قايمة الوحدات، أو "أخرى" لو نص حر مش في القايمة.
String? _matchUnitChoice(String text) => text.isEmpty ? null : (_unitChoices.contains(text) ? text : _otherUnit);

class ProductsScreen extends ConsumerWidget {
  const ProductsScreen({super.key});

  Future<void> _editProduct(BuildContext context, WidgetRef ref, [StockLine? p]) async {
    final code = TextEditingController(text: p?.code ?? '');
    final name = TextEditingController(text: p?.name ?? '');
    final unit = TextEditingController(text: p?.unit ?? 'عبوة');
    final price = TextEditingController(text: p == null ? '' : qty(p.price));
    final cost = TextEditingController(text: p?.cost == null ? '' : qty(p!.cost!));
    final openingQty = TextEditingController();
    final cartonUnit = TextEditingController(text: (p?.cartonUnit ?? '').isEmpty ? 'كرتونة' : p!.cartonUnit!);
    final perCarton = TextEditingController(text: (p?.unitsPerCarton ?? 1) > 1 ? qty(p!.unitsPerCarton) : '');
    final cartonPriceCtrl = TextEditingController(text: p?.cartonPrice == null ? '' : qty(p!.cartonPrice!));
    String? unitChoice = _matchUnitChoice(unit.text) ?? 'عبوة';
    bool hasCarton = (p?.cartonUnit ?? '').isNotEmpty;
    bool openingByCarton = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final n = parseNum(perCarton.text);
          final defaultCartonPrice = n > 0 ? parseNum(price.text) * n : 0;
          final cartonPriceSet = hasCarton && cartonPriceCtrl.text.trim().isNotEmpty;
          // لو حدد سعر الكرتونة بنفسه، سعر الوحدة بقى محسوب منه (كرتونة ÷ عدد) مش العكس.
          final derivedUnitPrice = cartonPriceSet && n > 0 ? parseNum(cartonPriceCtrl.text) / n : null;
          return AlertDialog(
            title: Text(p == null ? 'صنف جديد' : 'تعديل ${p.name}'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(controller: code, decoration: const InputDecoration(labelText: 'كود الصنف')),
                  const SizedBox(height: 12),
                  TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم الصنف')),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: unitChoice,
                    decoration: const InputDecoration(labelText: 'أصغر وحدة بتتباع بيها للزبون؟'),
                    items: [
                      for (final u in _unitChoices) DropdownMenuItem(value: u, child: Text(u)),
                      const DropdownMenuItem(value: _otherUnit, child: Text(_otherUnit)),
                    ],
                    onChanged: (v) => set(() {
                      unitChoice = v;
                      if (v != _otherUnit) unit.text = v ?? '';
                    }),
                  ),
                  if (unitChoice == _otherUnit) ...[
                    const SizedBox(height: 12),
                    TextField(controller: unit, decoration: const InputDecoration(labelText: 'اسم الوحدة')),
                  ],
                  const SizedBox(height: 12),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: derivedUnitPrice != null
                          ? TextField(
                              key: ValueKey(derivedUnitPrice),
                              controller: TextEditingController(text: qty(derivedUnitPrice)),
                              enabled: false,
                              decoration: InputDecoration(
                                labelText: 'سعر بيع الـ${unit.text.isEmpty ? 'وحدة' : unit.text}',
                                helperText: 'بيتحسب من سعر الكرتونة ÷ العدد',
                                helperMaxLines: 2,
                              ),
                            )
                          : TextField(
                              controller: price,
                              onChanged: (_) => set(() {}),
                              decoration: InputDecoration(labelText: 'سعر بيع الـ${unit.text.isEmpty ? 'وحدة' : unit.text}'),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: cost,
                        decoration: const InputDecoration(labelText: 'سعر التكلفة (اختياري)'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                      ),
                    ),
                  ]),
                  if (p == null) ...[
                    const SizedBox(height: 12),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: TextField(
                          controller: openingQty,
                          decoration: const InputDecoration(labelText: 'الرصيد الافتتاحي (اللي متاح عندك دلوقتي، اختياري)'),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                        ),
                      ),
                      if (hasCarton && n > 0) ...[
                        const SizedBox(width: 12),
                        Segmented<bool>(
                          options: [(false, unit.text), (true, cartonUnit.text)],
                          value: openingByCarton,
                          onChanged: (v) => set(() => openingByCarton = v),
                        ),
                      ],
                    ]),
                  ],
                  const Divider(height: 28),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('بتيجي كمان بتعبئة أكبر (كرتونة)؟', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    value: hasCarton,
                    onChanged: (v) => set(() {
                      hasCarton = v;
                      if (v && cartonUnit.text.trim().isEmpty) cartonUnit.text = 'كرتونة';
                    }),
                  ),
                  if (hasCarton) ...[
                    const SizedBox(height: 12),
                    TextField(controller: cartonUnit, onChanged: (_) => set(() {}), decoration: const InputDecoration(labelText: 'اسمها إيه (افتراضيًا كرتونة)')),
                    const SizedBox(height: 12),
                    TextField(
                      controller: perCarton,
                      onChanged: (_) => set(() {}),
                      decoration: InputDecoration(labelText: 'الـ${cartonUnit.text.isEmpty ? 'كرتونة' : cartonUnit.text} فيها كام ${unit.text.isEmpty ? 'وحدة' : unit.text}؟'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    ),
                    if (n > 0) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: cartonPriceCtrl,
                        onChanged: (_) => set(() {}),
                        decoration: InputDecoration(
                          labelText: 'سعر بيع الـ${cartonUnit.text.isEmpty ? 'كرتونة' : cartonUnit.text}',
                          hintText: 'سيبه فاضي = ${money(defaultCartonPrice.toDouble())} (سعر الـ${unit.text} × العدد)',
                          helperText: 'لو حددته، سعر الـ${unit.text} هيتحسب منه تلقائي (الكرتونة ÷ العدد)',
                          helperMaxLines: 2,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                      ),
                    ],
                  ],
                ]),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
            ],
          );
        },
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final finalPerCarton = hasCarton ? parseNum(perCarton.text) : 0.0;
    final finalCartonPrice = hasCarton && cartonPriceCtrl.text.trim().isNotEmpty ? parseNum(cartonPriceCtrl.text) : null;
    final finalUnitPrice = finalCartonPrice != null && finalPerCarton > 0 ? finalCartonPrice / finalPerCarton : parseNum(price.text);
    final rawOpening = parseNum(openingQty.text);
    final finalOpeningQty = openingByCarton && finalPerCarton > 0 ? rawOpening * finalPerCarton : rawOpening;
    try {
      await ref.read(repositoryProvider).upsertProduct(
            id: p?.productId,
            code: code.text.trim(),
            name: name.text.trim(),
            unit: unit.text.trim().isEmpty ? 'عبوة' : unit.text.trim(),
            price: finalUnitPrice,
            cartonUnit: hasCarton ? cartonUnit.text.trim() : '',
            unitsPerCarton: finalPerCarton,
            cost: cost.text.trim().isEmpty ? null : parseNum(cost.text),
            cartonPrice: finalCartonPrice,
            openingQty: p == null && finalOpeningQty > 0 ? finalOpeningQty : null,
          );
      ref.invalidate(warehouseLiveProvider(null));
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<Supplier?> _quickAddSupplier(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مورد جديد'),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'اسم المورد')),
            const SizedBox(height: 12),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف (اختياري)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return null;
    try {
      await ref.read(repositoryProvider).upsertSupplier(name: name.text.trim(), phone: phone.text.trim().isEmpty ? null : phone.text.trim());
      ref.invalidate(suppliersProvider);
      final all = await ref.read(repositoryProvider).suppliers();
      return all.where((s) => s.name == name.text.trim()).lastOrNull;
    } catch (e) {
      if (context.mounted) showError(context, e);
      return null;
    }
  }

  Future<void> _receive(BuildContext context, WidgetRef ref, List<StockLine> stock) async {
    final ctrls = {for (final p in stock) p.productId: TextEditingController()};
    final costCtrls = {for (final p in stock) p.productId: TextEditingController(text: p.cost == null ? '' : qty(p.cost!))};
    final paidCtrl = TextEditingController();
    final production = <String, DateTime?>{};
    final expiry = <String, DateTime?>{};
    List<Supplier> suppliers;
    try {
      suppliers = await ref.read(repositoryProvider).suppliers();
    } catch (e) {
      if (context.mounted) showError(context, e);
      return;
    }
    if (!context.mounted) return;
    String? supplierId;

    Future<void> pickDate(void Function(void Function()) set, Map<String, DateTime?> target, String productId) async {
      final picked = await showDatePicker(
        context: context,
        initialDate: target[productId] ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );
      if (picked != null) set(() => target[productId] = picked);
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('استلام بضاعة للمخزن'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      initialValue: supplierId,
                      decoration: const InputDecoration(labelText: 'المورد (اختياري)'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('بدون مورد')),
                        for (final sup in suppliers) DropdownMenuItem(value: sup.id, child: Text(sup.name)),
                      ],
                      onChanged: (v) => set(() => supplierId = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'مورد جديد',
                    onPressed: () async {
                      final added = await _quickAddSupplier(context, ref);
                      if (added != null) {
                        set(() {
                          suppliers = [...suppliers, added];
                          supplierId = added.id;
                        });
                      }
                    },
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ]),
                const Divider(height: 24),
                for (final p in stock)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text('${p.name} (${p.unit})', style: const TextStyle(fontWeight: FontWeight.w600))),
                        SizedBox(
                          width: 90,
                          child: TextField(
                            controller: ctrls[p.productId],
                            onChanged: (_) => set(() {}),
                            textAlign: TextAlign.center,
                            decoration: const InputDecoration(hintText: 'الكمية'),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 100,
                          child: TextField(
                            controller: costCtrls[p.productId],
                            onChanged: (_) => set(() {}),
                            textAlign: TextAlign.center,
                            decoration: const InputDecoration(hintText: 'سعر الشراء'),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                          ),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      Row(children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => pickDate(set, production, p.productId),
                            icon: const Icon(Icons.calendar_today_outlined, size: 16),
                            label: Text(production[p.productId] == null ? 'تاريخ الإنتاج' : dateLabel(production[p.productId]!)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => pickDate(set, expiry, p.productId),
                            icon: const Icon(Icons.event_busy_outlined, size: 16),
                            label: Text(expiry[p.productId] == null ? 'تاريخ الصلاحية' : dateLabel(expiry[p.productId]!)),
                          ),
                        ),
                      ]),
                    ]),
                  ),
                if (supplierId != null) ...[
                  const Divider(height: 24),
                  Builder(builder: (_) {
                    final total = stock.fold<double>(0, (a, p) => a + parseNum(ctrls[p.productId]!.text) * parseNum(costCtrls[p.productId]!.text));
                    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('الإجمالي: ${money(total)} ج.م', style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 10),
                      TextField(
                        controller: paidCtrl,
                        decoration: const InputDecoration(labelText: 'المدفوع نقدًا الآن (سيبه فاضي = مدفوع بالكامل)'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                      ),
                    ]);
                  }),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إضافة للرصيد')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final lines = [
      for (final e in ctrls.entries)
        if (parseNum(e.value.text) > 0)
          ReceiveLine(
            productId: e.key,
            qty: parseNum(e.value.text),
            costPrice: costCtrls[e.key]!.text.trim().isEmpty ? null : parseNum(costCtrls[e.key]!.text),
            productionDate: production[e.key],
            expiryDate: expiry[e.key],
          )
    ];
    if (lines.isEmpty) return;
    try {
      final r = await ref
          .read(repositoryProvider)
          .receiveStock(lines, supplierId: supplierId, paid: paidCtrl.text.trim().isEmpty ? null : parseNum(paidCtrl.text));
      ref.invalidate(warehouseLiveProvider(null));
      if (supplierId != null) ref.invalidate(suppliersProvider);
      if (context.mounted) {
        showDone(context, r.credit > 0 ? 'اتضاف للرصيد — فاضل آجل للمورد ${money(r.credit)} ج' : 'اتضاف للرصيد');
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _resetData(BuildContext context, WidgetRef ref) async {
    final typed = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('مسح بيانات الشركة؟'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text(
                'الإجراء ده مش قابل للرجوع: هيمسح كل الأصناف والعملاء وكل الفواتير (صرف، بيع، تحصيل، تسوية) الخاصة بالشركة كلها. الحسابات والمخازن بتفضل كما هي.',
                style: TextStyle(height: 1.6),
              ),
              const SizedBox(height: 16),
              const Text('اكتب "مسح" للتأكيد:', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(controller: typed, autofocus: true, onChanged: (_) => set(() {})),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: MC.crimson),
              onPressed: typed.text.trim() == 'مسح' ? () => Navigator.pop(ctx, true) : null,
              child: const Text('مسح نهائيًا'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(repositoryProvider).resetCompanyData();
      ref.invalidate(warehouseLiveProvider(null));
      ref.invalidate(customersProvider);
      if (context.mounted) showDone(context, 'اتمسحت بيانات الشركة');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(warehouseLiveProvider(null));
    return AsyncBody(
      value: live,
      onRetry: () => ref.invalidate(warehouseLiveProvider(null)),
      builder: (w) {
        const st = TextStyle(fontSize: 13, color: MC.muted);
        return DesktopPage(children: [
          PageHeader(title: 'الأصناف والمخزون', kicker: w.name, actions: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: MC.crimson, side: const BorderSide(color: MC.crimson)),
              onPressed: () => _resetData(context, ref),
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('مسح بيانات الشركة'),
            ),
            const ImportMenuButton(kind: ImportKind.products),
            OutlinedButton.icon(onPressed: () => _receive(context, ref, w.stock), icon: const Icon(Icons.move_to_inbox_rounded), label: const Text('استلام بضاعة')),
            FilledButton.icon(onPressed: () => _editProduct(context, ref), icon: const Icon(Icons.add_rounded), label: const Text('صنف جديد')),
          ]),
          if (w.expiringBatches.isNotEmpty) _ExpiryBanner(batches: w.expiringBatches),
          WideTable(
            minWidth: 820,
            child: Column(children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: MC.ink, width: 2), bottom: BorderSide(color: MC.line))),
                child: const Row(children: [
                  SizedBox(width: 100, child: Text('الكود', style: st)),
                  Expanded(flex: 3, child: Text('الصنف', style: st)),
                  Expanded(flex: 2, child: Text('سعر البيع', style: st)),
                  Expanded(flex: 4, child: Text('في المخزن / مع المناديب', style: st)),
                  SizedBox(width: 48),
                ]),
              ),
              for (final p in w.stock)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: MC.line))),
                  child: Row(children: [
                    SizedBox(width: 100, child: Text(p.code ?? '', style: display(14, color: MC.muted), textDirection: TextDirection.ltr)),
                    Expanded(
                      flex: 3,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                        Text(p.unit, style: const TextStyle(fontSize: 12, color: MC.muted)),
                      ]),
                    ),
                    Expanded(flex: 2, child: Text(money(p.price), style: display(16))),
                    Expanded(
                      flex: 4,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        SplitBar(segments: [
                          (p.inStock + p.withReps == 0 ? 0.0 : p.inStock / (p.inStock + p.withReps), MC.teal),
                          (p.inStock + p.withReps == 0 ? 0.0 : p.withReps / (p.inStock + p.withReps), MC.orange),
                        ], height: 8),
                        const SizedBox(height: 6),
                        Text('في المخزن ${qty(p.inStock)} · مع المناديب ${qty(p.withReps)}', style: const TextStyle(fontSize: 12, color: MC.muted)),
                      ]),
                    ),
                    IconButton(
                      tooltip: 'حركة الصنف',
                      onPressed: () => context.go('/keeper/products/${p.productId}/movements'),
                      icon: const Icon(Icons.receipt_long_outlined),
                    ),
                    IconButton(tooltip: 'تعديل', onPressed: () => _editProduct(context, ref, p), icon: const Icon(Icons.edit_outlined)),
                  ]),
                ),
            ]),
          ),
          const Row(children: [
            LegendDot('في المخزن', MC.teal),
            SizedBox(width: 16),
            LegendDot('مع المناديب', MC.orange),
          ]),
        ]);
      },
    );
  }
}

class _ExpiryBanner extends StatelessWidget {
  final List<ExpiringBatch> batches;
  const _ExpiryBanner({required this.batches});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: MC.orange.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: MC.orange.withValues(alpha: 0.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final b in batches)
            LinedRow(
              line: MC.orange.withValues(alpha: 0.2),
              child: Row(children: [
                Icon(Icons.warning_amber_rounded, size: 18, color: b.daysLeft <= 7 ? MC.crimson : MC.orange),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${b.productName} (${qty(b.qty)} ${b.unit}) ${b.daysLeft < 0 ? 'منتهي الصلاحية' : 'هتخلص صلاحيته بعد ${b.daysLeft} يوم'}'
                    '${b.supplierName == null ? '' : ' · ${b.supplierName}'}',
                    style: TextStyle(fontSize: 13, color: b.daysLeft <= 7 ? MC.crimson : MC.ink, fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
            ),
        ]),
      );
}
