import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'new_company_screen.dart' show showKeysDialog;

/// حسابات ومفاتيح شركة: إيقاف/تشغيل، تمديد المدة، فك ربط جهاز، مفتاح جديد
class CompanyLicensesScreen extends ConsumerWidget {
  final String companyId;
  const CompanyLicensesScreen({super.key, required this.companyId});

  Future<void> _run(BuildContext context, WidgetRef ref, Future<void> Function() f, [String? done]) async {
    try {
      await f();
      ref.invalidate(companyLicensesProvider(companyId));
      ref.invalidate(companiesProvider);
      if (done != null && context.mounted) showDone(context, done);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<bool> _confirm(BuildContext context, String title, String body, {Color color = MC.crimson, String ok = 'تأكيد'}) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: color), onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
          ],
        ),
      ) ==
      true;

  Future<void> _deleteCompany(BuildContext context, WidgetRef ref, CompanyRow c) async {
    final typed = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('حذف ${c.name} نهائيًا؟'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text(
                'الإجراء ده مش قابل للرجوع: هيمسح الشركة وكل المخازن والحسابات والمفاتيح والأصناف والعملاء وكل الفواتير والتقارير الخاصة بيها.',
                style: TextStyle(height: 1.6),
              ),
              const SizedBox(height: 16),
              Text('اكتب اسم الشركة "${c.name}" للتأكيد:', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(controller: typed, autofocus: true, onChanged: (_) => set(() {})),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: MC.crimson),
              onPressed: typed.text.trim() == c.name ? () => Navigator.pop(ctx, true) : null,
              child: const Text('حذف نهائيًا'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(repositoryProvider).deleteCompany(c.id);
      ref.invalidate(companiesProvider);
      if (context.mounted) {
        showDone(context, 'اتمسحت ${c.name} نهائيًا');
        context.go('/admin');
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _renameAccount(BuildContext context, WidgetRef ref, LicenseRow l) async {
    final name = TextEditingController(text: l.name);
    final phone = TextEditingController(text: l.phone ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل اسم الحساب'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'الاسم')),
            const SizedBox(height: 14),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'موبايل (اختياري)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final repo = ref.read(repositoryProvider);
    await _run(
      context,
      ref,
      () => repo.renameAccount(l.profileId, name.text.trim(), phone: phone.text.trim().isEmpty ? null : phone.text.trim()),
      'اتعدّل اسم الحساب',
    );
  }

  Future<void> _addAccount(BuildContext context, WidgetRef ref, CompanyLicenses data) async {
    var role = Role.rep;
    String? wh = data.warehouses.isEmpty ? null : data.warehouses.first.id;
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('حساب جديد'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Segmented<Role>(
                options: const [(Role.rep, 'مندوب'), (Role.keeper, 'أمين مخزن')],
                value: role,
                onChanged: (r) => set(() => role = r),
              ),
              const SizedBox(height: 14),
              if (data.warehouses.isNotEmpty)
                DropdownButtonFormField<String>(
                  value: wh,
                  decoration: const InputDecoration(labelText: 'المخزن'),
                  items: [for (final w in data.warehouses) DropdownMenuItem(value: w.id, child: Text(w.name))],
                  onChanged: (v) => set(() => wh = v),
                ),
              const SizedBox(height: 14),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إنشاء ومفتاح')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    try {
      final acc = await ref.read(repositoryProvider).addAccount(companyId: companyId, warehouseId: wh, role: role, name: name.text.trim());
      ref.invalidate(companyLicensesProvider(companyId));
      if (context.mounted) await showKeysDialog(context, data.company.name, [acc]);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(companyLicensesProvider(companyId));
    final repo = ref.read(repositoryProvider);
    return AsyncBody<CompanyLicenses>(
      value: data,
      onRetry: () => ref.invalidate(companyLicensesProvider(companyId)),
      builder: (d) {
        final c = d.company;
        final live = c.active && !c.expired;
        final activated = d.licenses.where((l) => l.bound && l.active).length;
        const st = TextStyle(fontSize: 13, color: MC.adminMuted);

        Widget extend(String label, DurationUnit u, int n, {bool primary = false}) => primary
            ? FilledButton(
                style: FilledButton.styleFrom(backgroundColor: MC.orange, foregroundColor: MC.adminInk, minimumSize: const Size(44, 42)),
                onPressed: () => _run(context, ref, () => repo.extendCompany(c.id, u, n), 'اتمدّت المدة $label'),
                child: Text('+ $label'),
              )
            : OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFE4F1EE),
                  side: const BorderSide(color: Color(0xFF24505A)),
                  minimumSize: const Size(44, 42),
                ),
                onPressed: () => _run(context, ref, () => repo.extendCompany(c.id, u, n), 'اتمدّت المدة $label'),
                child: Text('+ $label'),
              );

        return DesktopPage(maxWidth: 1360, children: [
          Wrap(spacing: 24, runSpacing: 24, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 420, maxWidth: 700),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('كود الشركة ${c.code} · ${c.warehouses} مخازن · ${c.reps} مندوب', style: const TextStyle(fontSize: 14, color: MC.adminMuted)),
                Text(c.name, style: display(36, weight: FontWeight.w700)),
                const SizedBox(height: 10),
                Row(children: [
                  Switch(
                    value: c.active,
                    activeTrackColor: MC.teal,
                    inactiveTrackColor: MC.crimsonTint,
                    onChanged: (v) async {
                      if (!v && !await _confirm(context, 'إيقاف ${c.name}؟', 'كل أجهزة الشركة هتتقفل فوراً.', ok: 'إيقاف')) return;
                      if (context.mounted) await _run(context, ref, () => repo.setCompanyActive(c.id, v));
                    },
                  ),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(live ? 'الشركة شغالة' : (c.active ? 'مدة التفعيل انتهت' : 'الشركة موقوفة'),
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: live ? MC.teal : MC.crimson)),
                    Text(live ? 'إيقافها بيقفل كل أجهزتها فوراً' : 'كل الأجهزة مقفولة لحد ما تشغّلها أو تمد المدة',
                        style: const TextStyle(fontSize: 13, color: MC.adminMuted)),
                  ]),
                ]),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: MC.crimson, side: const BorderSide(color: MC.crimson)),
                  onPressed: () => _deleteCompany(context, ref, c),
                  icon: const Icon(Icons.delete_forever_rounded),
                  label: const Text('حذف الشركة نهائيًا'),
                ),
              ]),
            ),
            SizedBox(
              width: 420,
              child: DarkPanel(
                color: MC.adminRail,
                padding: const EdgeInsets.all(22),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('مدة التفعيل', style: TextStyle(fontSize: 13, color: MC.adminOnDark)),
                  const SizedBox(height: 6),
                  Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                    Text(dateLabel(c.expiresAt), style: display(26, weight: FontWeight.w700, color: Colors.white)),
                    const SizedBox(width: 10),
                    Text(c.expired ? 'منتهية' : 'باقي ${c.daysLeft} يوم', style: const TextStyle(fontSize: 14, color: MC.orange)),
                  ]),
                  const SizedBox(height: 14),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    extend('ساعة', DurationUnit.hour, 1),
                    extend('يوم', DurationUnit.day, 1),
                    extend('أسبوع', DurationUnit.week, 1),
                    extend('شهر', DurationUnit.month, 1, primary: true),
                    extend('سنة', DurationUnit.year, 1),
                  ]),
                ]),
              ),
            ),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionTitle(
              'الحسابات ومفاتيح التفعيل',
              hint: '$activated من ${d.licenses.length} مفعّل على جهاز',
              muted: MC.adminMuted,
              trailing: Wrap(spacing: 10, children: [
                OutlinedButton.icon(
                  onPressed: () => showKeysDialog(
                    context,
                    c.name,
                    [for (final l in d.licenses) CreatedAccount(role: l.role, name: l.name, key: l.key, warehouse: l.warehouse)],
                  ),
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('كل المفاتيح'),
                ),
                FilledButton.icon(
                  onPressed: () => _addAccount(context, ref, d),
                  icon: const Icon(Icons.person_add_alt_rounded),
                  label: const Text('حساب جديد'),
                ),
              ]),
            ),
            WideTable(
              minWidth: 1120,
              child: Column(children: [
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: MC.adminInk, width: 2), bottom: BorderSide(color: MC.adminLine))),
                  child: const Row(children: [
                    Expanded(flex: 16, child: Text('الحساب', style: st)),
                    Expanded(flex: 10, child: Text('المخزن', style: st)),
                    Expanded(flex: 15, child: Text('مفتاح التفعيل', style: st)),
                    Expanded(flex: 15, child: Text('الجهاز المربوط', style: st)),
                    SizedBox(width: 80, child: Text('شغال', style: st)),
                    SizedBox(width: 250),
                  ]),
                ),
                for (final l in d.licenses) _row(context, ref, l, live),
              ]),
            ),
            const SizedBox(height: 10),
            const Text('فك الربط بيحرر المفتاح علشان يتفعل على جهاز جديد · الجهاز القديم بيتقفل في أول تحقق.',
                style: TextStyle(fontSize: 13, color: MC.adminMuted)),
          ]),
        ]);
      },
    );
  }

  Widget _row(BuildContext context, WidgetRef ref, LicenseRow l, bool companyLive) {
    final repo = ref.read(repositoryProvider);
    final (icon, bg, fg) = switch (l.role) {
      Role.manager => (Icons.apartment_rounded, MC.orangeTint, MC.burntText),
      Role.keeper => (Icons.desktop_windows_outlined, MC.plumTint, MC.plum),
      _ => (Icons.smartphone_rounded, const Color(0xFFE4F1EE), MC.teal),
    };
    final on = l.active && companyLive;
    return Opacity(
      opacity: on ? 1 : 0.6,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: MC.adminLine))),
        child: Row(children: [
          Expanded(
            flex: 16,
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: fg, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15), overflow: TextOverflow.ellipsis),
                  Text(roleLabel(l.role), style: const TextStyle(fontSize: 12, color: MC.adminMuted)),
                ]),
              ),
            ]),
          ),
          Expanded(flex: 10, child: Text(l.warehouse ?? '—', style: const TextStyle(fontSize: 14))),
          Expanded(
            flex: 15,
            child: Row(children: [
              Flexible(child: SelectableText(l.key, style: display(14, letterSpacing: 0.5), textDirection: TextDirection.ltr)),
              IconButton(
                tooltip: 'نسخ المفتاح',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: l.key));
                  showDone(context, 'اتنسخ المفتاح');
                },
                icon: const Icon(Icons.copy_rounded, size: 16, color: MC.teal),
              ),
            ]),
          ),
          Expanded(
            flex: 15,
            child: l.bound
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l.deviceName ?? 'جهاز', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    Text([l.deviceSerial, if (l.activatedAt != null) dateLabel(l.activatedAt!)].whereType<String>().join(' · '),
                        style: const TextStyle(fontSize: 12, color: MC.adminMuted), overflow: TextOverflow.ellipsis),
                  ])
                : const Row(children: [
                    Icon(Icons.radio_button_unchecked, size: 14, color: MC.burntText),
                    SizedBox(width: 6),
                    Text('لسه ماتفعّلش', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: MC.burntText)),
                  ]),
          ),
          SizedBox(
            width: 80,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Switch(
                value: l.active,
                activeTrackColor: MC.teal,
                onChanged: (v) => _run(context, ref, () => repo.setLicenseActive(l.id, v), v ? 'اتشغل الحساب' : 'اتوقف الحساب'),
              ),
            ),
          ),
          SizedBox(
            width: 250,
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(40, 38), side: const BorderSide(color: MC.adminLine)),
                onPressed: () => _renameAccount(context, ref, l),
                child: const Text('تعديل الاسم'),
              ),
              if (l.bound)
                OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: MC.crimson, minimumSize: const Size(40, 38), side: const BorderSide(color: MC.adminLine)),
                  onPressed: () async {
                    if (await _confirm(context, 'فك ربط ${l.name}؟',
                        'الجهاز ${l.deviceName ?? ''} هيتقفل، ونفس المفتاح يقدر يتفعل على جهاز جديد.',
                        ok: 'فك الربط')) {
                      if (context.mounted) await _run(context, ref, () => repo.unbindLicense(l.id), 'اتفك ربط الجهاز');
                    }
                  },
                  child: const Text('فك ربط الجهاز'),
                ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(40, 38), side: const BorderSide(color: MC.adminLine)),
                onPressed: () async {
                  if (!await _confirm(context, 'مفتاح جديد لـ ${l.name}؟', 'المفتاح القديم هيبطل والجهاز الحالي هيتقفل.', color: MC.teal)) return;
                  try {
                    final k = await repo.regenerateKey(l.id);
                    ref.invalidate(companyLicensesProvider(companyId));
                    if (context.mounted) {
                      await showKeysDialog(context, l.name, [CreatedAccount(role: l.role, name: l.name, key: k, warehouse: l.warehouse)]);
                    }
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  }
                },
                child: const Text('مفتاح جديد'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
