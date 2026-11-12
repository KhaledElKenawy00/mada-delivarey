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

enum PayMode { cash, partial, credit }

class SaleScreen extends ConsumerStatefulWidget {
  const SaleScreen({super.key});
  @override
  ConsumerState<SaleScreen> createState() => _SaleScreenState();
}

class _SaleScreenState extends ConsumerState<SaleScreen> {
  final _clientUuid = const Uuid().v4(); // ثابت للفاتورة دي — يمنع التكرار
  Customer? _customer;
  final _qty = <String, double>{}; // دايماً بوحدة الصنف الأساسية (unit)
  final _byCarton = <String, bool>{};
  PayMode _mode = PayMode.cash;
  final _paid = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _paid.dispose();
    super.dispose();
  }

  bool _isCarton(CustodyItem it) => _byCarton[it.productId] ?? it.hasCarton;
  double _toDisplay(CustodyItem it, double baseQty) => _isCarton(it) ? baseQty / it.unitsPerCarton : baseQty;
  String _unitOf(CustodyItem it) => _isCarton(it) ? (it.cartonUnit ?? '') : it.unit;

  Future<void> _editQty(CustodyItem it) async {
    final c = TextEditingController(text: qty(_toDisplay(it, _qty[it.productId] ?? 0)));
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('الكمية — ${it.name} (بال${_unitOf(it)})'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _isCarton(it) ? parseNum(c.text) * it.unitsPerCarton : parseNum(c.text)),
            child: const Text('تمام'),
          ),
        ],
      ),
    );
    if (v != null) setState(() => _qty[it.productId] = v);
  }

  Future<void> _save(List<CustodyItem> items, Map<String, double> available, double total) async {
    if (_customer == null) {
      showError(context, 'اختار العميل الأول');
      return;
    }
    final lines = [
      for (final it in items)
        if ((_qty[it.productId] ?? 0) > 0) SaleLine(it.productId, _qty[it.productId]!)
    ];
    if (lines.isEmpty) {
      showError(context, 'ضيف صنف واحد على الأقل');
      return;
    }
    for (final l in lines) {
      if (l.qty > (available[l.productId] ?? 0)) {
        showError(context, const AppException('EXCEEDS_CUSTODY'));
        return;
      }
    }
    final paid = switch (_mode) {
      PayMode.cash => total,
      PayMode.credit => 0.0,
      PayMode.partial => parseNum(_paid.text).clamp(0.0, total).toDouble(),
    };
    setState(() => _busy = true);
    try {
      final r = await ref.read(repositoryProvider).createSale(_clientUuid, _customer!.id, lines, paid);
      ref.invalidate(myCustodyProvider);
      ref.invalidate(customersProvider);
      if (!mounted) return;
      showDone(context, 'اتحفظت الفاتورة ${r.no} — ${money(r.total)} ج');
      await _printAndClose(r.no, r.total, r.paid, items, offline: false);
    } on AppException catch (e) {
      if (e.code == 'NETWORK') {
        await ref.read(offlineQueueProvider).addSale(_clientUuid, _customer!.id, lines, paid, total);
        if (!mounted) return;
        showDone(context, 'مفيش نت — الفاتورة اتحفظت على الموبايل وهتترفع لوحدها');
        await _printAndClose(null, total, paid, items, offline: true);
      } else if (mounted) {
        showError(context, e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// معاينة/طباعة الإيصال وبعدين الرجوع للعهدة
  Future<void> _printAndClose(String? no, double total, double paid, List<CustodyItem> items, {required bool offline}) async {
    final me = ref.read(profileProvider);
    final before = _customer!.balance;
    final data = ReceiptData(
      company: me.companyName ?? 'مدار',
      warehouse: me.warehouseName,
      title: 'فاتورة بيع',
      number: no ?? 'مؤقت ${_clientUuid.substring(0, 8).toUpperCase()}',
      offline: offline,
      at: DateTime.now(),
      rep: me.fullName,
      customer: _customer!.name,
      lines: [
        for (final it in items)
          if ((_qty[it.productId] ?? 0) > 0) ReceiptLine(it.name, _qty[it.productId]!, it.price)
      ],
      totals: [
        ReceiptTotal('إجمالي الفاتورة', '${money(total)} ج', bold: true),
        ReceiptTotal('المدفوع', '${money(paid)} ج'),
        if (total - paid > 0) ReceiptTotal('آجل', '${money(total - paid)} ج'),
        if (before != 0) ReceiptTotal('رصيد سابق', '${money(before)} ج'),
        if (before != 0 || total - paid > 0) ReceiptTotal('الرصيد الحالي على العميل', '${money(before + total - paid)} ج', bold: true),
      ],
      footer: 'شكراً لتعاملكم معنا',
    );
    await showReceiptDialog(context, data);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final custody = ref.watch(myCustodyProvider);
    final queue = ref.watch(offlineQueueProvider);
    final allowCredit = ref.watch(profileProvider).allowCredit;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: MC.ground,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('فاتورة بيع', style: display(20)),
          Text(_clientUuid.substring(0, 8).toUpperCase(), style: const TextStyle(fontSize: 12, color: MC.muted)),
        ]),
      ),
      body: AsyncBody<SessionData?>(
        value: custody,
        builder: (s) {
          if (s == null || !s.isOpen) {
            return const Center(child: Text('مفيش يوم عمل مفتوح'));
          }
          final pending = queue.pendingQty;
          final available = {for (final it in s.items) it.productId: it.available - (pending[it.productId] ?? 0)};
          final items = s.items.where((it) => (available[it.productId] ?? 0) > 0 || (_qty[it.productId] ?? 0) > 0).toList();
          var total = 0.0;
          var hasError = false;
          for (final it in items) {
            final q = _qty[it.productId] ?? 0;
            if (q > (available[it.productId] ?? 0)) {
              hasError = true;
            } else {
              total += q * it.price;
            }
          }
          final paid = switch (_mode) {
            PayMode.cash => total,
            PayMode.credit => 0.0,
            PayMode.partial => parseNum(_paid.text).clamp(0.0, total).toDouble(),
          };

          return Column(children: [
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
                Material(
                  color: MC.ink,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () async {
                      final c = await pickCustomer(context, ref);
                      if (c != null) setState(() => _customer = c);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(children: [
                        Avatar(_customer?.name ?? '+', size: 42, radius: 12, bg: MC.orange, fg: MC.ink),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(_customer?.name ?? 'اختار العميل', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: Colors.white)),
                            if (_customer != null)
                              Text(
                                _customer!.balance > 0 ? 'رصيد سابق عليه: ${money(_customer!.balance)} ج' : 'مفيش مديونية سابقة',
                                style: TextStyle(fontSize: 12, color: _customer!.balance > 0 ? const Color(0xFFFFB4BF) : MC.onDarkMuted),
                              ),
                          ]),
                        ),
                        Text(_customer == null ? 'اختيار' : 'تغيير', style: const TextStyle(color: MC.orange, fontSize: 13)),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                for (final it in items)
                  Builder(builder: (context) {
                    final q = _qty[it.productId] ?? 0;
                    final avail = available[it.productId] ?? 0;
                    final over = q > avail;
                    final carton = _isCarton(it);
                    final unit = _unitOf(it);
                    final unitPrice = carton ? it.price * it.unitsPerCarton : it.price;
                    final availDisplay = _toDisplay(it, avail);
                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: MC.line))),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(it.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                              Text('${money(unitPrice)} ج/$unit · متاح ${qty(availDisplay)} $unit', style: const TextStyle(fontSize: 12, color: MC.muted)),
                              if (it.hasCarton)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Segmented<bool>(
                                    options: [(false, it.unit), (true, it.cartonUnit!)],
                                    value: carton,
                                    onChanged: (v) => setState(() => _byCarton[it.productId] = v),
                                  ),
                                ),
                            ]),
                          ),
                          QtyStepper(
                            value: qty(_toDisplay(it, q)),
                            width: 128,
                            error: over,
                            onInc: () => setState(() => _qty[it.productId] = q + (carton ? it.unitsPerCarton : 1)),
                            onDec: () => setState(() => _qty[it.productId] = (q - (carton ? it.unitsPerCarton : 1)).clamp(0.0, double.infinity).toDouble()),
                            onTapValue: () => _editQty(it),
                          ),
                          SizedBox(
                            width: 66,
                            child: Text(over || q == 0 ? '—' : money(q * it.price), textAlign: TextAlign.left, style: display(16)),
                          ),
                        ]),
                        if (over) ...[
                          const SizedBox(height: 6),
                          Row(children: [
                            const Icon(Icons.error_outline_rounded, size: 15, color: MC.crimson),
                            const SizedBox(width: 6),
                            Text('الكمية أكبر من عهدتك — المتاح ${qty(availDisplay)} $unit فقط',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: MC.crimson)),
                          ]),
                        ],
                      ]),
                    );
                  }),
                const SizedBox(height: 16),
                const Text('طريقة الدفع', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Segmented<PayMode>(
                  options: [
                    (PayMode.cash, 'نقدي'),
                    if (allowCredit) (PayMode.partial, 'جزئي'),
                    if (allowCredit) (PayMode.credit, 'آجل'),
                  ],
                  value: _mode,
                  onChanged: (m) => setState(() => _mode = m),
                ),
                if (_mode != PayMode.cash) ...[
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: _mode == PayMode.partial
                          ? TextField(
                              controller: _paid,
                              onChanged: (_) => setState(() {}),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                              style: display(20, color: MC.teal),
                              decoration: const InputDecoration(labelText: 'المحصّل نقداً'),
                            )
                          : MiniStat('المحصّل نقداً', '0', color: MC.teal, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        height: 56,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        alignment: AlignmentDirectional.centerStart,
                        decoration: BoxDecoration(color: MC.crimsonTint, borderRadius: BorderRadius.circular(12)),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('يتسجّل آجل', style: TextStyle(fontSize: 12, color: MC.crimson)),
                          Text(money(total - paid), style: display(20, color: MC.crimson)),
                        ]),
                      ),
                    ),
                  ]),
                ],
              ]),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
              decoration: const BoxDecoration(
                color: MC.ink,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  const Text('إجمالي الفاتورة', style: TextStyle(fontSize: 12, color: MC.onDarkMuted)),
                  Text('${money(total)} ج', style: display(26, weight: FontWeight.w700, color: Colors.white)),
                ]),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _busy || hasError || total == 0 ? null : () => _save(s.items, available, total),
                  style: FilledButton.styleFrom(backgroundColor: MC.orange, foregroundColor: MC.ink, minimumSize: const Size(150, 54)),
                  icon: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: MC.ink))
                      : const Icon(Icons.save_rounded),
                  label: const Text('حفظ الفاتورة'),
                ),
              ]),
            ),
          ]);
        },
      ),
    );
  }
}
