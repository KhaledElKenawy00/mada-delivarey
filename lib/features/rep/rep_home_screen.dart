import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../license/license_controller.dart';
import 'offline_queue.dart';
import 'rep_widgets.dart';
import 'tracking.dart';

class RepHomeScreen extends ConsumerStatefulWidget {
  const RepHomeScreen({super.key});
  @override
  ConsumerState<RepHomeScreen> createState() => _RepHomeScreenState();
}

class _RepHomeScreenState extends ConsumerState<RepHomeScreen> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 60), (_) => _refresh());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final sent = await ref.read(offlineQueueProvider).flush();
    if (sent > 0 && mounted) showDone(context, 'اترفع $sent عملية كانت محفوظة أوفلاين');
    ref.invalidate(myCustodyProvider);
  }

  Future<void> _syncTracking(SessionData? s) async {
    final tracking = ref.read(trackingProvider.notifier);
    if (s != null && s.isOpen) {
      final st = await tracking.start();
      if (!mounted) return;
      if (st == TrackingState.denied) showError(context, 'لازم تسمح بالموقع علشان تبدأ يوم العمل');
      if (st == TrackingState.gpsOff) showError(context, 'شغّل الـ GPS علشان تبدأ يوم العمل');
    } else {
      await tracking.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<SessionData?>>(myCustodyProvider, (_, next) {
      if (next.hasValue) _syncTracking(next.value);
    });
    final custody = ref.watch(myCustodyProvider);
    final queue = ref.watch(offlineQueueProvider);
    final tracking = ref.watch(trackingProvider);
    final me = ref.watch(profileProvider);

    return Scaffold(
      bottomNavigationBar: const RepBottomNav(index: 0),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: custody.when(
          skipLoadingOnRefresh: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            const SizedBox(height: 160),
            Center(child: Text('$e', textAlign: TextAlign.center)),
            Center(child: TextButton(onPressed: _refresh, child: const Text('حاول تاني'))),
          ]),
          data: (s) {
            final pendingQty = queue.pendingQty;
            final items = s?.items ?? const <CustodyItem>[];
            final issued = s?.totals.issued ?? 0;
            final remaining = items.fold<double>(0, (a, it) => a + (it.available - (pendingQty[it.productId] ?? 0)) * it.price);
            final sold = (s?.totals.sold ?? 0) + queue.pendingSales;
            final cash = (s?.totals.cashInHand ?? 0) + queue.pendingCash;
            return ListView(padding: EdgeInsets.zero, children: [
              _Band(
                name: me.fullName,
                started: s?.startedAt,
                tracking: tracking,
                open: s?.isOpen ?? false,
                fraction: issued == 0 ? 0.0 : remaining / issued,
                remaining: remaining,
                sold: sold,
                cash: cash,
              ),
              if (queue.length > 0)
                Container(
                  margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: MC.orangeTint, borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    const Icon(Icons.cloud_upload_outlined, color: MC.burntText),
                    const SizedBox(width: 10),
                    Expanded(child: Text('${queue.length} عملية محفوظة أوفلاين — هتترفع أول ما النت يرجع', style: const TextStyle(color: MC.burntText))),
                    TextButton(onPressed: _refresh, child: const Text('رفع')),
                  ]),
                ),
              if (s == null) const _Empty(icon: Icons.hourglass_empty_rounded, title: 'مفيش عهدة النهارده', body: 'استنى أمين المخزن يعمل لك إذن صرف. اسحب لتحت للتحديث.'),
              if (s != null && s.isPending)
                const _Empty(icon: Icons.task_alt_rounded, title: 'قفلت يومك', body: 'مستني أمين المخزن يراجع المرتجع ويستلم النقدية.'),
              if (s != null && s.isOpen) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                  child: Row(children: [
                    Expanded(
                      flex: 2,
                      child: _Action(
                        label: 'فاتورة بيع',
                        icon: Icons.note_add_rounded,
                        bg: MC.burnt,
                        fg: MC.ink,
                        big: true,
                        onTap: () => context.go('/rep/sale'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: _Action(label: 'تحصيل', icon: Icons.payments_outlined, fg: MC.teal, onTap: () => context.go('/rep/collect'))),
                    const SizedBox(width: 10),
                    Expanded(child: _Action(label: 'عميل جديد', icon: Icons.person_add_alt_rounded, fg: MC.plum, onTap: () => context.go('/rep/customers'))),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Text('عهدتي من ${me.warehouseName ?? 'المخزن'}', style: display(17)),
                      const Spacer(),
                      Text(s.issueNo ?? '', style: const TextStyle(fontSize: 12, color: MC.muted), textDirection: TextDirection.ltr),
                    ]),
                    const SizedBox(height: 8),
                    for (final it in items)
                      Builder(builder: (context) {
                        final left = it.available - (pendingQty[it.productId] ?? 0);
                        return LinedRow(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                              Text(it.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                              const SizedBox(width: 8),
                              Text('${money(it.price)} ج / ${it.unit}', style: const TextStyle(fontSize: 12, color: MC.muted)),
                              const Spacer(),
                              Text(qty(left), style: display(20, weight: FontWeight.w700)),
                              Text(' / ${qty(it.issued)}', style: const TextStyle(fontSize: 13, color: MC.muted)),
                            ]),
                            const SizedBox(height: 8),
                            SplitBar(segments: [(it.issued == 0 ? 0.0 : left / it.issued, MC.plum)], height: 8),
                          ]),
                        );
                      }),
                  ]),
                ),
              ],
            ]);
          },
        ),
      ),
    );
  }
}

class _Band extends StatelessWidget {
  final String name;
  final DateTime? started;
  final TrackingState tracking;
  final bool open;
  final double fraction, remaining, sold, cash;
  const _Band({
    required this.name,
    required this.started,
    required this.tracking,
    required this.open,
    required this.fraction,
    required this.remaining,
    required this.sold,
    required this.cash,
  });
  @override
  Widget build(BuildContext context) {
    final (label, fg, bg) = switch (tracking) {
      TrackingState.on => ('التتبع شغال', const Color(0xFF9FE0CB), const Color(0xFF163E46)),
      TrackingState.denied => ('الموقع مقفول', const Color(0xFFFFB4BF), const Color(0xFF4A0A1B)),
      TrackingState.gpsOff => ('GPS مقفول', const Color(0xFFFFB4BF), const Color(0xFF4A0A1B)),
      TrackingState.off => ('التتبع واقف', MC.onDarkMuted, MC.inkSoft),
    };
    return Container(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 18, 20, 22),
      decoration: const BoxDecoration(
        color: MC.ink,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(started == null ? 'مدار · المندوب' : 'يوم عمل · بدأ ${hm(started)}', style: const TextStyle(fontSize: 13, color: MC.onDarkMuted)),
              Text('أهلاً ${name.split(' ').first}', style: display(20, color: Colors.white)),
            ]),
          ),
          if (open) Pill(label, fg: fg, bg: bg, fontSize: 12),
        ]),
        const SizedBox(height: 18),
        Row(children: [
          CustodyRing(fraction: fraction),
          const SizedBox(width: 18),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('العهدة المتبقية', style: TextStyle(fontSize: 12, color: MC.onDarkMuted)),
              FittedBox(child: Text(money(remaining), style: display(26, weight: FontWeight.w700, color: Colors.white))),
              const SizedBox(height: 10),
              Row(children: [
                MiniStat('مبيعات', money(sold), color: MC.orange, size: 16, muted: MC.onDarkMuted),
                const SizedBox(width: 18),
                MiniStat('معايا كاش', money(cash), color: const Color(0xFF9FE0CB), size: 16, muted: MC.onDarkMuted),
              ]),
            ]),
          ),
        ]),
      ]),
    );
  }
}

class _Action extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color bg, fg;
  final bool big;
  final VoidCallback onTap;
  const _Action({required this.label, required this.icon, this.bg = Colors.white, required this.fg, this.big = false, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: bg == Colors.white ? const BorderSide(color: MC.line) : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: SizedBox(
            height: 76,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: big ? 16 : 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: big ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                children: [
                  Icon(icon, color: fg),
                  const SizedBox(height: 4),
                  Text(label, style: TextStyle(fontWeight: big ? FontWeight.w700 : FontWeight.w600, fontSize: big ? 16 : 13, color: big ? fg : MC.ink)),
                ],
              ),
            ),
          ),
        ),
      );
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String title, body;
  const _Empty({required this.icon, required this.title, required this.body});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
        child: Column(children: [
          Icon(icon, size: 48, color: MC.plum),
          const SizedBox(height: 12),
          Text(title, style: display(20)),
          const SizedBox(height: 6),
          Text(body, textAlign: TextAlign.center, style: const TextStyle(color: MC.muted, height: 1.6)),
        ]),
      );
}
