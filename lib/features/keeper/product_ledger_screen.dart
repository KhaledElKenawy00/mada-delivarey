import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../print/report_pdf.dart';

/// كشف حركة صنف واحد من تاريخ البداية لحد النهارده (أو فترة محددة):
/// استلام من مورد، صرف للمناديب، مرتجع، وبيع فعلي للعملاء.
class ProductLedgerScreen extends ConsumerStatefulWidget {
  final String productId;
  const ProductLedgerScreen({super.key, required this.productId});
  @override
  ConsumerState<ProductLedgerScreen> createState() => _ProductLedgerScreenState();
}

class _ProductLedgerScreenState extends ConsumerState<ProductLedgerScreen> {
  DateTime _from = DateTime(2020, 1, 1);
  DateTime _to = DateTime.now();

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (picked != null) {
      setState(() {
        _from = picked.start;
        _to = picked.end;
      });
    }
  }

  IconData _icon(String kind) => switch (kind) {
        'receive' => Icons.move_to_inbox_rounded,
        'issue' => Icons.outbox_rounded,
        'return' => Icons.undo_rounded,
        'sale' => Icons.point_of_sale_rounded,
        _ => Icons.swap_horiz_rounded,
      };

  String _label(String kind) => switch (kind) {
        'receive' => 'استلام',
        'issue' => 'صرف لمندوب',
        'return' => 'مرتجع',
        'sale' => 'بيع',
        _ => kind,
      };

  Future<void> _printPdf(ProductLedger l) async {
    try {
      await Printing.layoutPdf(onLayout: (_) => buildProductLedgerPdf(l), name: 'كشف حركة ${l.productName}');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final args = (productId: widget.productId, from: _from, to: _to);
    final data = ref.watch(productLedgerProvider(args));
    return AsyncBody<ProductLedger>(
      value: data,
      onRetry: () => ref.invalidate(productLedgerProvider(args)),
      builder: (l) {
        return DesktopPage(children: [
          PageHeader(
            title: l.productName,
            kicker: '${dateLabel(_from)} → ${dateLabel(_to)}',
            actions: [
              OutlinedButton.icon(onPressed: _pickRange, icon: const Icon(Icons.date_range_rounded), label: const Text('الفترة')),
              OutlinedButton.icon(onPressed: () => _printPdf(l), icon: const Icon(Icons.print_outlined), label: const Text('طباعة PDF')),
            ],
          ),
          StatStrip(minWidth: 140, items: [
            StatItem('في المخزن', '${qty(l.inStock)} ${l.unit}', color: MC.teal),
            StatItem('استلام', qty(l.received), color: MC.plum),
            StatItem('صرف لمناديب', qty(l.issued), color: MC.orange),
            StatItem('مرتجع', qty(l.returned), color: MC.muted),
            StatItem('مبيع', qty(l.sold), color: MC.burnt),
          ]),
          const SectionTitle('الحركات'),
          if (l.movements.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('مفيش حركات في الفترة دي', style: TextStyle(color: MC.muted))),
          for (final m in l.movements)
            LinedRow(
              child: Row(children: [
                Icon(_icon(m.kind), size: 20, color: m.qty >= 0 ? MC.teal : MC.crimson),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_label(m.kind), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    Text([
                      if (m.at != null) dateLabel(m.at!),
                      if (m.title != null) m.title!,
                    ].join(' · '), style: const TextStyle(fontSize: 12, color: MC.muted)),
                  ]),
                ),
                if (m.kind == 'sale' && m.price != null && m.costPrice != null)
                  Text('ربح ${money((m.price! - m.costPrice!) * m.qty.abs())}', style: const TextStyle(fontSize: 12, color: MC.muted)),
                const SizedBox(width: 12),
                Text('${m.qty > 0 ? '+' : ''}${qty(m.qty)} ${l.unit}', style: display(16, color: m.qty >= 0 ? MC.teal : MC.crimson)),
              ]),
            ),
        ]);
      },
    );
  }
}
