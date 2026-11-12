import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

class StockIssueScreen extends ConsumerStatefulWidget {
  final String? initialRepId;
  const StockIssueScreen({super.key, this.initialRepId});
  @override
  ConsumerState<StockIssueScreen> createState() => _StockIssueScreenState();
}

class _Line {
  final StockLine product;
  double qty; // دايماً بوحدة الصنف الأساسية (unit)
  double price; // سعر الوحدة الأساسية دايماً، حتى لو العرض بالكرتونة
  bool byCarton;
  _Line(this.product, this.qty)
      : price = product.hasCarton && product.unitsPerCarton > 0
            ? product.effectiveCartonPrice / product.unitsPerCarton
            : product.price,
        byCarton = product.hasCarton;

  /// الكمية بالوحدة المختارة للعرض (كرتونة أو الوحدة الأساسية)
  double get displayQty => byCarton ? qty / product.unitsPerCarton : qty;
  String get displayUnit => byCarton ? (product.cartonUnit ?? '') : product.unit;
  /// السعر بالوحدة المختارة للعرض (سعر الكرتونة أو سعر الوحدة الأساسية)
  double get displayPrice => byCarton ? price * product.unitsPerCarton : price;
}

class _StockIssueScreenState extends ConsumerState<StockIssueScreen> {
  String? _repId;
  final _lines = <_Line>[];
  bool _busy = false;
  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _repId = widget.initialRepId;
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _add(StockLine p) {
    setState(() {
      final existing = _lines.where((l) => l.product.productId == p.productId).firstOrNull;
      final step = p.hasCarton ? p.unitsPerCarton : 1.0;
      if (existing == null) {
        _lines.add(_Line(p, step));
      } else {
        existing.qty += existing.byCarton ? existing.product.unitsPerCarton : 1;
      }
    });
    _search.clear();
  }

  Future<void> _editNumber(String title, double current, ValueChanged<double> onSet) async {
    final c = TextEditingController(text: qty(current));
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          onSubmitted: (_) => Navigator.pop(ctx, parseNum(c.text)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, parseNum(c.text)), child: const Text('تمام')),
        ],
      ),
    );
    if (v != null && v >= 0) setState(() => onSet(v));
  }

  Future<void> _submit(List<RepLive> reps) async {
    if (_repId == null || _lines.isEmpty || _busy) return;
    final bad = _lines.where((l) => l.qty <= 0);
    if (bad.isNotEmpty) {
      showError(context, 'راجع الكميات: ${bad.map((l) => l.product.name).join('، ')}');
      return;
    }
    setState(() => _busy = true);
    try {
      final no = await ref.read(repositoryProvider).createStockIssue(
            _repId!,
            [for (final l in _lines) IssueLine(l.product.productId, l.qty, l.price)],
          );
      ref.invalidate(warehouseLiveProvider(null));
      if (!mounted) return;
      showDone(context, 'اتصرف الإذن $no — البضاعة ظهرت على موبايل المندوب');
      context.go('/keeper');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(warehouseLiveProvider(null));
    return AsyncBody(
      value: live,
      onRetry: () => ref.invalidate(warehouseLiveProvider(null)),
      builder: (w) {
        final rep = w.reps.where((r) => r.id == _repId).firstOrNull;
        final total = _lines.fold<double>(0, (a, l) => a + l.qty * l.price);
        final cartons = _lines.fold<double>(0, (a, l) => a + l.qty);
        final main = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          PageHeader(kicker: dayLabel(DateTime.now()), title: 'صرف بضاعة لمندوب'),
          const SizedBox(height: 28),
          const Text('المندوب', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (var k = 0; k < w.reps.length; k++) _RepChip(rep: w.reps[k], index: k, selected: w.reps[k].id == _repId, onTap: () => setState(() => _repId = w.reps[k].id)),
          ]),
          const SizedBox(height: 28),
          Row(children: [
            const Text('الأصناف المصروفة', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const Spacer(),
            SizedBox(
              width: 320,
              child: Autocomplete<StockLine>(
                optionsBuilder: (v) {
                  final q = v.text.trim();
                  return w.stock.where((p) => q.isEmpty || p.name.contains(q) || (p.code ?? '').toLowerCase().contains(q.toLowerCase()));
                },
                displayStringForOption: (p) => p.name,
                onSelected: _add,
                fieldViewBuilder: (context, controller, focus, onSubmit) => TextField(
                  controller: controller,
                  focusNode: focus,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'أضف صنف بالاسم أو الكود…'),
                  onSubmitted: (_) => onSubmit(),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in w.stock.where((p) => !_lines.any((l) => l.product.productId == p.productId)))
              ActionChip(avatar: const Icon(Icons.add_rounded, size: 16), label: Text(p.name), onPressed: () => _add(p)),
          ]),
          const SizedBox(height: 12),
          WideTable(
            minWidth: 820,
            child: Container(
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: MC.ink, width: 2))),
              child: Column(children: [
                const _HeadRow(),
                if (_lines.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(28),
                    child: Text('اختار الأصناف اللي هتنزل مع المندوب', style: TextStyle(color: MC.muted)),
                  ),
                for (final l in _lines) _lineRow(l),
              ]),
            ),
          ),
        ]);

        final ticket = Container(
          color: MC.groundDeep,
          padding: const EdgeInsets.all(32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Text('ملخص العهدة', style: display(18)),
                  const Spacer(),
                  const Pill('مسودة', fg: MC.burntText, bg: MC.orangeTint, dot: false, fontSize: 12),
                ]),
                const SizedBox(height: 18),
                _kv('المندوب', rep?.name ?? '—'),
                _kv('عدد الأصناف', '${_lines.length}'),
                _kv('إجمالي الكراتين', qty(cartons)),
                const SizedBox(height: 6),
                const Divider(color: MC.line, thickness: 2),
                const SizedBox(height: 12),
                const Text('قيمة العهدة بسعر البيع', style: TextStyle(fontSize: 13, color: MC.muted)),
                Text.rich(TextSpan(children: [
                  TextSpan(text: money(total), style: display(44, weight: FontWeight.w700, color: MC.plum)),
                  TextSpan(text: ' ج.م', style: display(18, weight: FontWeight.w500, color: MC.plum)),
                ])),
                const SizedBox(height: 16),
                const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: MC.teal),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'بعد الاعتماد البضاعة تنزل من رصيد المخزن وتظهر فوراً على موبايل المندوب كعهدة. المندوب مايقدرش يبيع غير الأصناف دي وبالكميات دي.',
                      style: TextStyle(fontSize: 13, height: 1.6, color: Color(0xFF4A2A3A)),
                    ),
                  ),
                ]),
              ]),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _repId != null && _lines.isNotEmpty && !_busy ? () => _submit(w.reps) : null,
              style: FilledButton.styleFrom(backgroundColor: MC.burnt, foregroundColor: MC.ink, minimumSize: const Size.fromHeight(58)),
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: MC.ink))
                  : const Icon(Icons.check_rounded),
              label: const Text('اعتماد وصرف للمندوب'),
            ),
          ]),
        );

        return LayoutBuilder(builder: (context, c) {
          if (c.maxWidth < 1100) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(36, 28, 36, 48),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [main, const SizedBox(height: 28), ticket]),
            );
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(40, 32, 40, 48), child: main),
            ),
            SizedBox(width: 380, child: SingleChildScrollView(child: ticket)),
          ]);
        });
      },
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Text(k, style: const TextStyle(color: MC.muted, fontSize: 15)),
          const Spacer(),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        ]),
      );

  Widget _lineRow(_Line l) {
    final p = l.product;
    final after = p.inStock - l.qty;
    final over = after < 0;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: MC.line))),
      child: Row(children: [
        SizedBox(width: 90, child: Text(p.code ?? '', style: display(14, color: MC.muted), textDirection: TextDirection.ltr)),
        Expanded(
          flex: 16,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            if (p.hasCarton)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Segmented<bool>(
                  options: [(false, p.unit), (true, p.cartonUnit!)],
                  value: l.byCarton,
                  onChanged: (v) => setState(() => l.byCarton = v),
                ),
              )
            else
              Text(p.unit, style: const TextStyle(fontSize: 12, color: MC.muted)),
          ]),
        ),
        Expanded(
          flex: 13,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SplitBar(segments: [(p.inStock == 0 ? 0.0 : (after / p.inStock).clamp(0, 1).toDouble(), MC.teal)], height: 6),
              const SizedBox(height: 6),
              Text(over ? 'الرصيد ${qty(p.inStock)} بس' : 'بعد الصرف: ${qty(after)} ${p.unit}',
                  style: TextStyle(fontSize: 12, color: over ? MC.crimson : MC.muted, fontWeight: over ? FontWeight.w600 : null)),
            ]),
          ),
        ),
        QtyStepper(
          value: qty(l.displayQty),
          error: over,
          width: 160,
          onInc: () => setState(() => l.qty += l.byCarton ? p.unitsPerCarton : 1),
          onDec: () => setState(() => l.qty = (l.qty - (l.byCarton ? p.unitsPerCarton : 1)).clamp(0, double.infinity).toDouble()),
          onTapValue: () => _editNumber(
            'الكمية — ${p.name} (بال${l.displayUnit})',
            l.displayQty,
            (v) => l.qty = l.byCarton ? v * p.unitsPerCarton : v,
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 110,
          child: InkWell(
            onTap: () => _editNumber(
              'سعر الـ${l.displayUnit} — ${p.name}',
              l.displayPrice,
              (v) => l.price = l.byCarton ? v / p.unitsPerCarton : v,
            ),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(money(l.displayPrice), style: display(16)),
                  if (p.hasCarton) Text('لكل ${l.displayUnit}', style: const TextStyle(fontSize: 11, color: MC.muted)),
                ]),
              ),
              const Icon(Icons.edit_outlined, size: 14, color: MC.muted),
            ]),
          ),
        ),
        SizedBox(width: 120, child: Text(money(l.qty * l.price), style: display(17))),
        IconButton(
          tooltip: 'حذف الصنف',
          onPressed: () => setState(() => _lines.remove(l)),
          icon: const Icon(Icons.delete_outline_rounded, color: MC.crimson),
        ),
      ]),
    );
  }
}

class _HeadRow extends StatelessWidget {
  const _HeadRow();
  @override
  Widget build(BuildContext context) {
    const st = TextStyle(fontSize: 13, color: MC.muted);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: MC.line))),
      child: const Row(children: [
        SizedBox(width: 90, child: Text('الكود', style: st)),
        Expanded(flex: 16, child: Text('الصنف', style: st)),
        Expanded(flex: 13, child: Text('رصيد المخزن', style: st)),
        SizedBox(width: 160, child: Text('الكمية', style: st)),
        SizedBox(width: 16),
        SizedBox(width: 110, child: Text('سعر البيع', style: st)),
        SizedBox(width: 120, child: Text('الإجمالي', style: st)),
        SizedBox(width: 48),
      ]),
    );
  }
}

class _RepChip extends StatelessWidget {
  final RepLive rep;
  final int index;
  final bool selected;
  final VoidCallback onTap;
  const _RepChip({required this.rep, required this.index, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final busy = rep.sessionId != null && rep.status != RepStatus.done;
    final (bg, fg) = toneFor(index);
    return Opacity(
      opacity: busy ? 0.6 : 1,
      child: Material(
        color: selected ? MC.plum : (busy ? Colors.transparent : Colors.white),
        shape: StadiumBorder(side: BorderSide(color: selected ? MC.plum : MC.line)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: busy ? null : onTap,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 18, 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Avatar(rep.name, size: 32, bg: selected ? MC.orange : bg, fg: selected ? MC.ink : fg),
              const SizedBox(width: 10),
              Text(busy ? '${rep.name} · عنده عهدة مفتوحة' : rep.name,
                  style: TextStyle(fontSize: 15, fontWeight: selected ? FontWeight.w600 : FontWeight.w400, color: selected ? Colors.white : MC.ink)),
            ]),
          ),
        ),
      ),
    );
  }
}
