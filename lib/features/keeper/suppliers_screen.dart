import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

Future<void> _editSupplier(BuildContext context, WidgetRef ref, [Supplier? sup]) async {
  final name = TextEditingController(text: sup?.name ?? '');
  final phone = TextEditingController(text: sup?.phone ?? '');
  final address = TextEditingController(text: sup?.address ?? '');
  final opening = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(sup == null ? 'مورد جديد' : 'تعديل ${sup.name}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم المورد')),
            const SizedBox(height: 12),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف')),
            const SizedBox(height: 12),
            TextField(controller: address, decoration: const InputDecoration(labelText: 'العنوان')),
            if (sup == null) ...[
              const SizedBox(height: 12),
              TextField(
                controller: opening,
                decoration: const InputDecoration(labelText: 'عليك له فلوس من قبل (اختياري)'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
      ],
    ),
  );
  if (ok != true || name.text.trim().isEmpty) return;
  try {
    await ref.read(repositoryProvider).upsertSupplier(
          id: sup?.id,
          name: name.text.trim(),
          phone: phone.text.trim().isEmpty ? null : phone.text.trim(),
          address: address.text.trim().isEmpty ? null : address.text.trim(),
          openingBalance: parseNum(opening.text),
        );
    ref.invalidate(suppliersProvider);
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

Future<void> _paySupplier(BuildContext context, WidgetRef ref, Supplier sup) async {
  final amount = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('دفع لـ ${sup.name}'),
      content: SizedBox(
        width: 360,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (sup.balance > 0) Text('عليك له ${money(sup.balance)} ج.م', style: const TextStyle(color: MC.crimson, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          TextField(
            controller: amount,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'المبلغ المدفوع'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('دفع')),
      ],
    ),
  );
  if (ok != true) return;
  final v = parseNum(amount.text);
  if (v <= 0) return;
  try {
    await ref.read(repositoryProvider).createSupplierPayment(const Uuid().v4(), sup.id, v);
    ref.invalidate(suppliersProvider);
    ref.invalidate(supplierPaymentsProvider(sup.id));
    if (context.mounted) showDone(context, 'تم الدفع');
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

Future<void> _supplierPaymentsHistory(BuildContext context, WidgetRef ref, Supplier sup) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('سجل الدفعات — ${sup.name}'),
      content: SizedBox(
        width: 400,
        height: 360,
        child: Consumer(builder: (context, ref, _) {
          final data = ref.watch(supplierPaymentsProvider(sup.id));
          return AsyncBody<List<SupplierPayment>>(
            value: data,
            onRetry: () => ref.invalidate(supplierPaymentsProvider(sup.id)),
            builder: (rows) {
              if (rows.isEmpty) return const Center(child: Text('لسه مفيش دفعات', style: TextStyle(color: MC.muted)));
              return ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, k) => ListTile(
                  dense: true,
                  title: Text(money(rows[k].amount)),
                  subtitle: Text(rows[k].at == null ? '' : dateLabel(rows[k].at!)),
                  trailing: Text(rows[k].no, style: const TextStyle(fontSize: 12, color: MC.muted)),
                ),
              );
            },
          );
        }),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('قفل'))],
    ),
  );
}

class SuppliersScreen extends ConsumerWidget {
  const SuppliersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(suppliersProvider);
    return AsyncBody<List<Supplier>>(
      value: data,
      onRetry: () => ref.invalidate(suppliersProvider),
      builder: (suppliers) {
        final rows = [...suppliers]..sort((a, b) => a.name.compareTo(b.name));
        return DesktopPage(children: [
          PageHeader(title: 'الموردين', kicker: '${rows.length} مورد', actions: [
            FilledButton.icon(onPressed: () => _editSupplier(context, ref), icon: const Icon(Icons.add_rounded), label: const Text('مورد جديد')),
          ]),
          Column(children: [
            for (final sup in rows)
              LinedRow(
                onTap: () => _editSupplier(context, ref, sup),
                child: Row(children: [
                  Avatar(sup.name, size: 42, radius: 12),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(sup.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      Text([sup.phone, sup.address].whereType<String>().where((x) => x.isNotEmpty).join(' · '),
                          style: const TextStyle(fontSize: 12, color: MC.muted)),
                    ]),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(sup.balance > 0 ? 'عليك ${money(sup.balance)}' : 'مفيش دين', style: display(15, color: sup.balance > 0 ? MC.crimson : MC.teal)),
                  ]),
                  const SizedBox(width: 12),
                  IconButton(tooltip: 'سجل الدفعات', onPressed: () => _supplierPaymentsHistory(context, ref, sup), icon: const Icon(Icons.receipt_long_outlined)),
                  IconButton(tooltip: 'دفع', onPressed: () => _paySupplier(context, ref, sup), icon: const Icon(Icons.payments_outlined)),
                  IconButton(tooltip: 'تعديل', onPressed: () => _editSupplier(context, ref, sup), icon: const Icon(Icons.edit_outlined)),
                ]),
              ),
            if (rows.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('لسه مفيش موردين. ضيف أول مورد.', style: TextStyle(color: MC.muted))),
          ]),
        ]);
      },
    );
  }
}
