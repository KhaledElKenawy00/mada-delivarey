import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../common/customers_screen.dart' show showAddCustomerDialog;

/// حلقة "مدار" للعهدة المتبقية
class CustodyRing extends StatelessWidget {
  final double fraction; // المتبقي
  final double size;
  const CustodyRing({super.key, required this.fraction, this.size = 132});
  @override
  Widget build(BuildContext context) => Semantics(
        label: 'متبقي ${(fraction * 100).round()}% من العهدة',
        child: SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _RingPainter(fraction),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${(fraction * 100).round()}%', style: display(size * 0.2, weight: FontWeight.w700, color: Colors.white)),
                const Text('متبقي', style: TextStyle(fontSize: 13, color: MC.onDarkMuted)),
              ]),
            ),
          ),
        ),
      );
}

class _RingPainter extends CustomPainter {
  final double f;
  _RingPainter(this.f);
  @override
  void paint(Canvas c, Size s) {
    final stroke = s.width * 0.09;
    final rect = Offset.zero & s;
    final r = rect.deflate(stroke / 2);
    c.drawArc(r, 0, math.pi * 2, false, Paint()
      ..color = MC.inkSoft
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke);
    c.drawArc(r, -math.pi / 2, math.pi * 2 * f.clamp(0.0, 1.0).toDouble(), false, Paint()
      ..color = MC.orange
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.f != f;
}

class RepBottomNav extends StatelessWidget {
  final int index;
  const RepBottomNav({super.key, required this.index});
  @override
  Widget build(BuildContext context) => NavigationBar(
        selectedIndex: index,
        backgroundColor: Colors.white,
        indicatorColor: MC.plumTint,
        onDestinationSelected: (k) {
          switch (k) {
            case 0:
              context.go('/rep');
            case 1:
              context.go('/rep/customers');
            case 2:
              context.go('/rep/day');
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2_rounded, color: MC.plum), label: 'العهدة'),
          NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront_rounded, color: MC.plum), label: 'العملاء'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long_rounded, color: MC.plum), label: 'كشف اليوم'),
        ],
      );
}

/// اختيار عميل (بحث + إضافة عميل جديد)
Future<Customer?> pickCustomer(BuildContext context, WidgetRef ref, {bool owedFirst = false}) => showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: MC.ground,
      builder: (ctx) => _CustomerPicker(owedFirst: owedFirst),
    );

class _CustomerPicker extends ConsumerStatefulWidget {
  final bool owedFirst;
  const _CustomerPicker({required this.owedFirst});
  @override
  ConsumerState<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends ConsumerState<_CustomerPicker> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final data = ref.watch(customersProvider);
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text('اختار العميل', style: display(20)),
            const Spacer(),
            TextButton.icon(
              onPressed: () => showAddCustomerDialog(context, ref),
              icon: const Icon(Icons.person_add_alt_rounded),
              label: const Text('عميل جديد'),
            ),
          ]),
          const SizedBox(height: 8),
          TextField(
            autofocus: false,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'ابحث بالاسم أو المنطقة'),
            onChanged: (v) => setState(() => _q = v.trim()),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: data.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (all) {
                final rows = all.where((c) => _q.isEmpty || c.name.contains(_q) || (c.area ?? '').contains(_q)).toList();
                if (widget.owedFirst) rows.sort((a, b) => b.balance.compareTo(a.balance));
                return ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: MC.line),
                  itemBuilder: (_, k) {
                    final c = rows[k];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      onTap: () => Navigator.pop(context, c),
                      title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(c.area ?? '', style: const TextStyle(color: MC.muted)),
                      trailing: c.balance > 0
                          ? Text('عليه ${money(c.balance)}', style: display(14, color: MC.crimson))
                          : const Text('مفيش مديونية', style: TextStyle(color: MC.teal, fontSize: 12)),
                    );
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
