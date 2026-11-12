import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'reps_map.dart';

/// خريطة مباشرة: أمين المخزن (مناديب مخزنه) أو المدير (كل المناديب)
class LiveMapScreen extends ConsumerStatefulWidget {
  final bool allWarehouses;
  const LiveMapScreen({super.key, this.allWarehouses = false});
  @override
  ConsumerState<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends ConsumerState<LiveMapScreen> {
  Timer? _t;
  String? _selected;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 20), (_) {
      if (widget.allWarehouses) {
        ref.invalidate(companyOverviewProvider);
      } else {
        ref.invalidate(warehouseLiveProvider(null));
      }
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.allWarehouses) {
      final o = ref.watch(companyOverviewProvider);
      return AsyncBody(
        value: o,
        onRetry: () => ref.invalidate(companyOverviewProvider),
        builder: (c) => _body(
          title: 'كل المناديب · ${c.companyName}',
          reps: [for (final w in c.warehouses) ...w.reps.map((r) => (r, w.name))],
          warehouses: const [],
        ),
      );
    }
    final live = ref.watch(warehouseLiveProvider(null));
    return AsyncBody(
      value: live,
      onRetry: () => ref.invalidate(warehouseLiveProvider(null)),
      builder: (w) => _body(
        title: 'مناديب ${w.name}',
        reps: [for (final r in w.reps) (r, w.name)],
        warehouses: [if (w.lat != null && w.lng != null) MapWarehouse(w.name, w.lat!, w.lng!)],
      ),
    );
  }

  Widget _body({required String title, required List<(RepLive, String)> reps, required List<MapWarehouse> warehouses}) {
    final inField = reps.where((r) => r.$1.inField).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 28, 36, 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PageHeader(title: 'الخريطة المباشرة', kicker: '$title · ${inField.length} في الشارع'),
        const SizedBox(height: 20),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: RepsMap(
                reps: inField.map((e) => e.$1).toList(),
                warehouses: warehouses,
                onTapRep: (r) => setState(() => _selected = r.id),
              ),
            ),
            const SizedBox(width: 24),
            SizedBox(
              width: 360,
              child: ListView(children: [
                for (final (r, wh) in reps)
                  Container(
                    color: r.id == _selected ? MC.orangeTint : null,
                    child: LinedRow(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                      onTap: () => setState(() => _selected = r.id),
                      child: Row(children: [
                        Avatar(r.name, size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text('$wh · ${timeAgo(r.lastSeen)}', style: const TextStyle(fontSize: 12, color: MC.muted)),
                            const SizedBox(height: 6),
                            RepStatusPill(r.status),
                          ]),
                        ),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(money(r.totals.sold), style: display(15, color: MC.burntText)),
                          Text('تحصيل ${money(r.totals.cashInHand)}', style: const TextStyle(fontSize: 12, color: MC.teal)),
                        ]),
                      ]),
                    ),
                  ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}
