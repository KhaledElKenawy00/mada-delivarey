import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../license/license_controller.dart';
import '../print/receipt.dart';
import 'offline_queue.dart';
import 'rep_widgets.dart';

/// تحصيل مديونية من عميل (بيقلل رصيده ويزوّد النقدية اللي مع المندوب)
class CollectionScreen extends ConsumerStatefulWidget {
  const CollectionScreen({super.key});
  @override
  ConsumerState<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends ConsumerState<CollectionScreen> {
  final _id = const Uuid().v4();
  final _amount = TextEditingController();
  Customer? _customer;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = parseNum(_amount.text);
    if (_customer == null || amount <= 0) {
      showError(context, 'اختار العميل واكتب المبلغ');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).createCollection(_id, _customer!.id, amount);
      ref.invalidate(myCustodyProvider);
      ref.invalidate(customersProvider);
      if (!mounted) return;
      showDone(context, 'اتسجل تحصيل ${money(amount)} ج من ${_customer!.name}');
      await _printAndClose(amount, offline: false);
    } on AppException catch (e) {
      if (e.code == 'NETWORK') {
        await ref.read(offlineQueueProvider).addCollection(_id, _customer!.id, amount);
        if (!mounted) return;
        showDone(context, 'مفيش نت — التحصيل اتحفظ وهيترفع لوحده');
        await _printAndClose(amount, offline: true);
      } else if (mounted) {
        showError(context, e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _printAndClose(double amount, {required bool offline}) async {
    final me = ref.read(profileProvider);
    final c = _customer!;
    await showReceiptDialog(
      context,
      ReceiptData(
        company: me.companyName ?? 'مدار',
        warehouse: me.warehouseName,
        title: 'إيصال تحصيل',
        number: 'COL ${_id.substring(0, 8).toUpperCase()}',
        offline: offline,
        at: DateTime.now(),
        rep: me.fullName,
        customer: c.name,
        totals: [
          ReceiptTotal('الرصيد قبل التحصيل', '${money(c.balance)} ج'),
          ReceiptTotal('المبلغ المحصّل', '${money(amount)} ج', bold: true),
          ReceiptTotal('الرصيد المتبقي', '${money(c.balance - amount)} ج', bold: true),
        ],
        footer: 'استلمنا المبلغ — شكراً لكم',
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(backgroundColor: MC.ground, title: Text('تحصيل', style: display(20))),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: MC.line)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: Avatar(_customer?.name ?? '+', size: 42, radius: 12),
              title: Text(_customer?.name ?? 'اختار العميل', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: _customer == null
                  ? null
                  : Text('عليه ${money(_customer!.balance)} ج', style: const TextStyle(color: MC.crimson)),
              trailing: const Icon(Icons.chevron_left_rounded),
              onTap: () async {
                final c = await pickCustomer(context, ref, owedFirst: true);
                if (c != null) {
                  setState(() {
                    _customer = c;
                    if (_amount.text.isEmpty && c.balance > 0) _amount.text = qty(c.balance);
                  });
                }
              },
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            style: display(28, color: MC.teal),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: const InputDecoration(labelText: 'المبلغ المحصّل', suffixText: 'ج'),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            style: FilledButton.styleFrom(backgroundColor: MC.teal, minimumSize: const Size.fromHeight(56)),
            icon: const Icon(Icons.payments_outlined),
            label: const Text('تسجيل التحصيل'),
          ),
        ]),
      );
}
