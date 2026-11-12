import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

class CompaniesScreen extends ConsumerStatefulWidget {
  const CompaniesScreen({super.key});
  @override
  ConsumerState<CompaniesScreen> createState() => _CompaniesScreenState();
}

class _CompaniesScreenState extends ConsumerState<CompaniesScreen> {
  String _q = '';

  Future<void> _toggle(CompanyRow c) async {
    if (c.active) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('إيقاف ${c.name}؟'),
          content: const Text('كل أجهزة الشركة (المدير وأمناء المخازن والمناديب) هتتقفل فوراً لحد ما تشغّلها تاني.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: MC.crimson),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('إيقاف الشركة'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await ref.read(repositoryProvider).setCompanyActive(c.id, !c.active);
      ref.invalidate(companiesProvider);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(companiesProvider);
    return AsyncBody<List<CompanyRow>>(
      value: data,
      onRetry: () => ref.invalidate(companiesProvider),
      builder: (all) {
        final rows = all.where((c) => _q.isEmpty || c.name.contains(_q) || c.code.toLowerCase().contains(_q.toLowerCase())).toList();
        final active = all.where((c) => c.active && !c.expired).length;
        final devices = all.fold<int>(0, (a, c) => a + c.devicesActive);
        final soon = all.where((c) => c.active && !c.expired && c.daysLeft < 14).length;
        final stopped = all.where((c) => !c.active || c.expired).length;
        const st = TextStyle(fontSize: 13, color: MC.adminMuted);
        return DesktopPage(children: [
          PageHeader(title: 'الشركات', muted: MC.adminMuted, actions: [
            SizedBox(
              width: 280,
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'اسم الشركة أو الكود…'),
                onChanged: (v) => setState(() => _q = v.trim()),
              ),
            ),
            FilledButton.icon(onPressed: () => context.go('/admin/new'), icon: const Icon(Icons.add_rounded), label: const Text('شركة جديدة')),
          ]),
          StatStrip(ink: MC.adminInk, muted: MC.adminMuted, line: MC.adminLine, items: [
            StatItem('شركات شغالة', '$active', color: MC.teal),
            StatItem('أجهزة مفعّلة', '$devices', color: MC.adminInk),
            StatItem('تنتهي خلال 14 يوم', '$soon', color: MC.burntText),
            StatItem('موقوفة / منتهية', '$stopped', color: MC.crimson),
          ]),
          WideTable(
            minWidth: 1040,
            child: Column(children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: MC.adminLine))),
                child: const Row(children: [
                  Expanded(flex: 18, child: Text('الشركة', style: st)),
                  Expanded(flex: 9, child: Text('المخازن', style: st)),
                  Expanded(flex: 12, child: Text('المناديب / الأجهزة', style: st)),
                  Expanded(flex: 16, child: Text('مدة التفعيل', style: st)),
                  SizedBox(width: 100, child: Text('الحالة', style: st)),
                  SizedBox(width: 170),
                ]),
              ),
              for (var k = 0; k < rows.length; k++) _row(rows[k], k),
            ]),
          ),
        ]);
      },
    );
  }

  Widget _row(CompanyRow c, int k) {
    final live = c.active && !c.expired;
    final total = c.createdAt == null ? 365 : c.expiresAt.difference(c.createdAt!).inDays.clamp(1, 100000);
    final pct = live ? (c.daysLeft / total).clamp(0.02, 1.0).toDouble() : 0.0;
    final warn = live && c.daysLeft < 14;
    final (bg, fg) = toneFor(k);
    return Opacity(
      opacity: live ? 1 : 0.65,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: MC.adminLine))),
        child: Row(children: [
          Expanded(
            flex: 18,
            child: Row(children: [
              Avatar(c.name, size: 44, radius: 14, bg: bg, fg: fg),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                  Text('${c.code} · المدير: ${c.managerName ?? '—'}', style: const TextStyle(fontSize: 12, color: MC.adminMuted)),
                ]),
              ),
            ]),
          ),
          Expanded(flex: 9, child: Text('${c.warehouses} / ${c.maxWarehouses}', style: display(16))),
          Expanded(
            flex: 12,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${c.reps} / ${c.maxReps} مندوب', style: display(16)),
              Text('${c.devicesActive} من ${c.devicesTotal} جهاز مفعّل', style: const TextStyle(fontSize: 12, color: MC.adminMuted)),
            ]),
          ),
          Expanded(
            flex: 16,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SplitBar(segments: [(pct, !live ? MC.crimson : (warn ? MC.burnt : MC.teal))], height: 8, track: MC.adminTrack),
                const SizedBox(height: 6),
                Text(
                  !c.active
                      ? 'موقوفة يدوياً'
                      : c.expired
                          ? 'انتهت ${dateLabel(c.expiresAt)}'
                          : 'لحد ${dateLabel(c.expiresAt)} · باقي ${c.daysLeft} يوم',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: !live ? MC.crimson : (warn ? MC.burntText : MC.adminMuted)),
                ),
              ]),
            ),
          ),
          SizedBox(
            width: 100,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Switch(
                value: c.active,
                activeTrackColor: MC.teal,
                onChanged: (_) => _toggle(c),
              ),
            ),
          ),
          SizedBox(
            width: 170,
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: MC.teal),
              onPressed: () => context.go('/admin/company/${c.id}'),
              icon: const Icon(Icons.key_rounded, size: 18),
              label: const Text('الحسابات والمفاتيح'),
            ),
          ),
        ]),
      ),
    );
  }
}
