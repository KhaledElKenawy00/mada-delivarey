import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../import/excel_import.dart';
import '../license/license_controller.dart';

Future<bool> showAddCustomerDialog(BuildContext context, WidgetRef ref) async {
  final name = TextEditingController();
  final phone = TextEditingController();
  final area = TextEditingController();
  final code = TextEditingController();
  final limit = TextEditingController();
  final opening = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('عميل جديد'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم العميل')),
            const SizedBox(height: 12),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف')),
            const SizedBox(height: 12),
            TextField(controller: area, decoration: const InputDecoration(labelText: 'المنطقة')),
            const SizedBox(height: 12),
            TextField(controller: code, decoration: const InputDecoration(labelText: 'كود العميل (اختياري)')),
            const SizedBox(height: 12),
            TextField(
              controller: limit,
              decoration: const InputDecoration(labelText: 'حد الآجل'),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: opening,
              decoration: const InputDecoration(labelText: 'عليه فلوس من قبل (اختياري)'),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
      ],
    ),
  );
  if (ok != true || name.text.trim().isEmpty) return false;
  try {
    await ref.read(repositoryProvider).addCustomer(
          name: name.text.trim(),
          phone: phone.text.trim().isEmpty ? null : phone.text.trim(),
          area: area.text.trim().isEmpty ? null : area.text.trim(),
          code: code.text.trim().isEmpty ? null : code.text.trim(),
          creditLimit: parseNum(limit.text),
          openingBalance: parseNum(opening.text),
        );
    ref.invalidate(customersProvider);
    return true;
  } catch (e) {
    if (context.mounted) showError(context, e);
    return false;
  }
}

class CustomersScreen extends ConsumerStatefulWidget {
  final bool mobile;
  const CustomersScreen({super.key, this.mobile = false});
  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(customersProvider);
    final list = AsyncBody<List<Customer>>(
      value: data,
      onRetry: () => ref.invalidate(customersProvider),
      builder: (all) {
        final rows = all
            .where((c) => _q.isEmpty || c.name.contains(_q) || (c.area ?? '').contains(_q) || (c.code ?? '').contains(_q))
            .toList()
          ..sort((a, b) => b.balance.compareTo(a.balance));
        final owed = all.fold<double>(0, (a, c) => a + (c.balance > 0 ? c.balance : 0));
        final children = <Widget>[
          if (!widget.mobile)
            PageHeader(title: 'العملاء', kicker: '${all.length} عميل · مديونيات ${money(owed)} ج', actions: [
              if (ref.watch(profileProvider).role == Role.keeper) const ImportMenuButton(kind: ImportKind.customers),
              FilledButton.icon(
                onPressed: () => showAddCustomerDialog(context, ref),
                icon: const Icon(Icons.person_add_alt_rounded),
                label: const Text('عميل جديد'),
              ),
            ]),
          TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'ابحث بالاسم أو المنطقة أو الكود'),
            onChanged: (v) => setState(() => _q = v.trim()),
          ),
          Column(children: [
            for (var k = 0; k < rows.length; k++)
              LinedRow(
                child: Row(children: [
                  Avatar(rows[k].name, size: 42, radius: 12, bg: toneFor(k).$1, fg: toneFor(k).$2),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(rows[k].name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      Text([rows[k].code, rows[k].area, rows[k].phone].whereType<String>().where((x) => x.isNotEmpty).join(' · '),
                          style: const TextStyle(fontSize: 12, color: MC.muted)),
                    ]),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(rows[k].balance > 0 ? 'عليه ${money(rows[k].balance)}' : 'مفيش مديونية',
                        style: display(15, color: rows[k].balance > 0 ? MC.crimson : MC.teal)),
                    if (rows[k].creditLimit > 0)
                      Text('حد الآجل ${money(rows[k].creditLimit)}',
                          style: TextStyle(fontSize: 12, color: rows[k].balance > rows[k].creditLimit ? MC.crimson : MC.muted)),
                  ]),
                ]),
              ),
          ]),
        ];
        if (widget.mobile) {
          return ListView(padding: const EdgeInsets.all(16), children: [
            for (final c in children) Padding(padding: const EdgeInsets.only(bottom: 12), child: c),
          ]);
        }
        return DesktopPage(gap: 20, children: children);
      },
    );
    if (!widget.mobile) return list;
    return Scaffold(
      appBar: AppBar(title: const Text('العملاء'), backgroundColor: MC.ground),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: MC.plum,
        foregroundColor: Colors.white,
        onPressed: () => showAddCustomerDialog(context, ref),
        icon: const Icon(Icons.person_add_alt_rounded),
        label: const Text('عميل جديد'),
      ),
      body: list,
    );
  }
}
