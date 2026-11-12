import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

class _WhDraft {
  final TextEditingController name;
  int reps;
  _WhDraft(String n, this.reps) : name = TextEditingController(text: n);
}

class NewCompanyScreen extends ConsumerStatefulWidget {
  const NewCompanyScreen({super.key});
  @override
  ConsumerState<NewCompanyScreen> createState() => _NewCompanyScreenState();
}

class _NewCompanyScreenState extends ConsumerState<NewCompanyScreen> {
  final _name = TextEditingController();
  final _manager = TextEditingController();
  final _phone = TextEditingController();
  final _whs = [_WhDraft('مخزن 1', 3)];
  DurationUnit _unit = DurationUnit.month;
  int _count = 1;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _manager.dispose();
    _phone.dispose();
    for (final w in _whs) {
      w.name.dispose();
    }
    super.dispose();
  }

  int get _reps => _whs.fold(0, (a, w) => a + w.reps);
  int get _keys => 1 + _whs.length + _reps;

  Future<void> _create() async {
    if (_name.text.trim().isEmpty || _whs.isEmpty) {
      showError(context, 'اكتب اسم الشركة وضيف مخزن واحد على الأقل');
      return;
    }
    setState(() => _busy = true);
    try {
      final accounts = await ref.read(repositoryProvider).createCompany(NewCompanyInput(
            name: _name.text.trim(),
            managerName: _manager.text.trim().isEmpty ? 'مدير الشركة' : _manager.text.trim(),
            managerPhone: _phone.text.trim(),
            warehouses: [for (final w in _whs) (name: w.name.text.trim().isEmpty ? 'مخزن' : w.name.text.trim(), reps: w.reps)],
            unit: _unit,
            count: _count,
          ));
      ref.invalidate(companiesProvider);
      if (!mounted) return;
      await showKeysDialog(context, _name.text.trim(), accounts);
      if (mounted) context.go('/admin');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _step(int n, String title) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: MC.adminInk, shape: BoxShape.circle),
            child: Text('$n', style: const TextStyle(color: Colors.white, fontSize: 14)),
          ),
          const SizedBox(width: 10),
          Text(title, style: display(18)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final end = addDuration(DateTime.now(), _unit, _count);
    final form = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('إنشاء شركة جديدة', style: display(32, weight: FontWeight.w700)),
      const SizedBox(height: 32),
      _step(1, 'الشركة والمدير'),
      Wrap(spacing: 14, runSpacing: 14, children: [
        SizedBox(width: 260, child: TextField(controller: _name, decoration: const InputDecoration(labelText: 'اسم الشركة'))),
        SizedBox(width: 260, child: TextField(controller: _manager, decoration: const InputDecoration(labelText: 'اسم مدير الشركة'))),
        SizedBox(
          width: 220,
          child: TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'موبايل المدير')),
        ),
      ]),
      const SizedBox(height: 32),
      _step(2, 'المخازن وعدد المناديب في كل مخزن'),
      Container(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: MC.adminInk, width: 2))),
        child: Column(children: [
          for (var k = 0; k < _whs.length; k++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: MC.adminLine))),
              child: Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: const Color(0xFFE4F1EE), borderRadius: BorderRadius.circular(14)),
                  child: Text('${k + 1}', style: display(18, weight: FontWeight.w700, color: MC.teal)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 3,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    TextField(controller: _whs[k].name, decoration: const InputDecoration(hintText: 'اسم المخزن')),
                    const SizedBox(height: 4),
                    const Text('+ حساب أمين مخزن (ديسكتوب)', style: TextStyle(fontSize: 12, color: MC.adminMuted)),
                  ]),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: Wrap(spacing: 4, runSpacing: 4, children: [
                    for (var r = 0; r < _whs[k].reps; r++)
                      Container(width: 12, height: 22, decoration: BoxDecoration(color: MC.burnt, borderRadius: BorderRadius.circular(4))),
                  ]),
                ),
                QtyStepper(
                  value: '${_whs[k].reps} مندوب',
                  width: 190,
                  color: MC.teal,
                  onInc: () => setState(() => _whs[k].reps = (_whs[k].reps + 1).clamp(1, 50)),
                  onDec: () => setState(() => _whs[k].reps = (_whs[k].reps - 1).clamp(1, 50)),
                ),
                IconButton(
                  tooltip: 'حذف المخزن',
                  onPressed: _whs.length == 1 ? null : () => setState(() => _whs.removeAt(k).name.dispose()),
                  icon: const Icon(Icons.delete_outline_rounded, color: MC.crimson),
                ),
              ]),
            ),
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: MC.teal, side: const BorderSide(color: MC.teal)),
              onPressed: () => setState(() => _whs.add(_WhDraft('مخزن ${_whs.length + 1}', 2))),
              icon: const Icon(Icons.add_rounded),
              label: const Text('إضافة مخزن'),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 32),
      _step(3, 'مدة التفعيل'),
      Wrap(spacing: 14, runSpacing: 14, crossAxisAlignment: WrapCrossAlignment.center, children: [
        QtyStepper(
          value: '$_count',
          width: 170,
          color: MC.teal,
          onInc: () => setState(() => _count = (_count + 1).clamp(1, 99)),
          onDec: () => setState(() => _count = (_count - 1).clamp(1, 99)),
        ),
        Segmented<DurationUnit>(
          track: const Color(0xFFE2EBE9),
          ink: MC.adminInk,
          options: [for (final u in DurationUnit.values) (u, durationUnitLabel(u))],
          value: _unit,
          onChanged: (u) => setState(() => _unit = u),
        ),
        Text.rich(TextSpan(style: const TextStyle(fontSize: 15, color: MC.adminMuted), children: [
          const TextSpan(text: 'ينتهي في '),
          TextSpan(
            text: '${dateLabel(end)}${_unit == DurationUnit.hour ? ' · ${hm(end)}' : ''}',
            style: display(15, color: MC.adminInk),
          ),
        ])),
      ]),
    ]);

    final summary = Container(
      color: const Color(0xFFE2EBE9),
      padding: const EdgeInsets.all(32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DarkPanel(
          color: MC.adminRail,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('هيتعمل كام حساب ومفتاح', style: display(18, color: Colors.white)),
            const SizedBox(height: 16),
            _kv('مدير الشركة', '1'),
            _kv('أمناء مخازن (ديسكتوب)', '${_whs.length}'),
            _kv('مناديب (موبايل)', '$_reps'),
            const Divider(color: Color(0xFF24505A), height: 28),
            const Text('إجمالي مفاتيح التفعيل', style: TextStyle(fontSize: 13, color: MC.adminOnDark)),
            Text('$_keys', style: display(52, weight: FontWeight.w700, color: MC.orange)),
            const Text('كل مفتاح لجهاز واحد · يتربط بالسيريال أول مرة', style: TextStyle(fontSize: 13, color: MC.adminOnDark)),
          ]),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _busy ? null : _create,
          style: FilledButton.styleFrom(backgroundColor: MC.burnt, foregroundColor: MC.adminInk, minimumSize: const Size.fromHeight(58)),
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: MC.adminInk))
              : const Icon(Icons.key_rounded),
          label: const Text('إنشاء الشركة وتوليد المفاتيح'),
        ),
        const SizedBox(height: 12),
        const Text('بعد الإنشاء هتظهر لك كل المفاتيح تنسخها أو تطبعها وتسلمها لكل شخص.',
            style: TextStyle(fontSize: 13, height: 1.7, color: MC.adminMuted)),
      ]),
    );

    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 1100) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(36, 28, 36, 48),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [form, const SizedBox(height: 28), summary]),
        );
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(40, 32, 40, 48), child: form)),
        SizedBox(width: 400, child: SingleChildScrollView(child: summary)),
      ]);
    });
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Text(k, style: const TextStyle(color: MC.adminOnDark, fontSize: 15)),
          const Spacer(),
          Text(v, style: display(15, color: Colors.white)),
        ]),
      );
}

/// قايمة المفاتيح اللي اتولدت (نسخ واحد واحد أو الكل)
Future<void> showKeysDialog(BuildContext context, String company, List<CreatedAccount> accounts) {
  final all = accounts.map((a) => '${roleLabel(a.role)}\t${a.name}\t${a.warehouse ?? ''}\t${a.key}').join('\n');
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text('مفاتيح تفعيل $company'),
      content: SizedBox(
        width: 640,
        height: 460,
        child: ListView(children: [
          const Text('سلّم كل شخص المفتاح بتاعه. المفتاح بيتفعل مرة واحدة على جهاز واحد.', style: TextStyle(color: MC.adminMuted)),
          const SizedBox(height: 12),
          for (final a in accounts)
            LinedRow(
              line: MC.adminLine,
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(children: [
                Icon(
                  switch (a.role) { Role.manager => Icons.apartment_rounded, Role.keeper => Icons.desktop_windows_outlined, _ => Icons.smartphone_rounded },
                  color: MC.teal,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('${roleLabel(a.role)}${a.warehouse == null ? '' : ' · ${a.warehouse}'}', style: const TextStyle(fontSize: 12, color: MC.adminMuted)),
                  ]),
                ),
                SelectableText(a.key, style: display(15, letterSpacing: 1), textDirection: TextDirection.ltr),
                IconButton(
                  tooltip: 'نسخ',
                  onPressed: () => Clipboard.setData(ClipboardData(text: a.key)),
                  icon: const Icon(Icons.copy_rounded, size: 18),
                ),
              ]),
            ),
        ]),
      ),
      actions: [
        TextButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: all));
            showDone(ctx, 'اتنسخت كل المفاتيح');
          },
          icon: const Icon(Icons.copy_all_rounded),
          label: const Text('نسخ الكل'),
        ),
        FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('تمام')),
      ],
    ),
  );
}
