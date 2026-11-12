import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/models.dart';
import '../data/repository.dart';
import 'theme.dart';

// ───────────────────────────────────────────── Logo
class MadarLogo extends StatelessWidget {
  final double size;
  final Color ring, core, moon;
  const MadarLogo({super.key, this.size = 40, this.ring = MC.orange, this.core = MC.burnt, this.moon = Colors.white});
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _LogoPainter(ring, core, moon));
}

class _LogoPainter extends CustomPainter {
  final Color ring, core, moon;
  _LogoPainter(this.ring, this.core, this.moon);
  @override
  void paint(Canvas c, Size s) {
    final u = s.width / 40;
    final center = Offset(20 * u, 20 * u);
    c.drawCircle(center, 15 * u, Paint()
      ..color = ring
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5 * u);
    c.drawCircle(center, 6 * u, Paint()..color = core);
    c.drawCircle(Offset(33 * u, 12 * u), 4 * u, Paint()..color = moon);
  }

  @override
  bool shouldRepaint(covariant _LogoPainter old) => old.ring != ring || old.core != core || old.moon != moon;
}

/// حلقات "مدار" الزخرفية في الخلفية
class OrbitRings extends StatelessWidget {
  final double size;
  final Color color, accent;
  const OrbitRings({super.key, required this.size, this.color = Colors.white, this.accent = MC.orange});
  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: CustomPaint(size: Size.square(size), painter: _RingsPainter(color, accent)),
      );
}

class _RingsPainter extends CustomPainter {
  final Color color, accent;
  _RingsPainter(this.color, this.accent);
  @override
  void paint(Canvas c, Size s) {
    final o = Offset(s.width / 2, s.height / 2);
    final r = s.width / 2;
    c.drawCircle(o, r * 0.4, Paint()
      ..color = accent.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
    c.drawCircle(o, r * 0.67, Paint()
      ..color = color.withValues(alpha: 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
    c.drawCircle(o, r * 0.93, Paint()
      ..color = color.withValues(alpha: 0.09)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
    c.drawCircle(o, r * 0.16, Paint()..color = MC.burnt);
    c.drawCircle(o + Offset.fromDirection(-math.pi / 4, r * 0.4), r * 0.045, Paint()..color = accent);
    c.drawCircle(o + Offset.fromDirection(math.pi * 0.85, r * 0.67), r * 0.03, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ───────────────────────────────────────────── Stat strip (أرقام كبيرة بخط فاصل)
class StatItem {
  final String label, value;
  final String? sub;
  final Color? color;
  const StatItem(this.label, this.value, {this.sub, this.color});
}

class StatStrip extends StatelessWidget {
  final List<StatItem> items;
  final double minWidth, valueSize;
  final Color ink, muted, line;
  const StatStrip({
    super.key,
    required this.items,
    this.minWidth = 170,
    this.valueSize = 32,
    this.ink = MC.ink,
    this.muted = MC.muted,
    this.line = MC.line,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final cols = math.max(1, math.min(items.length, (c.maxWidth / minWidth).floor()));
        final w = c.maxWidth / cols;
        return Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: ink, width: 2), bottom: BorderSide(color: line)),
          ),
          child: Wrap(children: [
            for (final s in items)
              SizedBox(
                width: w,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(top: 18, bottom: 18, end: 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.label, style: TextStyle(fontSize: 13, color: muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(s.value, style: display(valueSize, color: s.color ?? ink)),
                    ),
                    if (s.sub != null) ...[
                      const SizedBox(height: 4),
                      Text(s.sub!, style: TextStyle(fontSize: 12, color: muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ]),
                ),
              ),
          ]),
        );
      });
}

// ───────────────────────────────────────────── Bars & chips
class SplitBar extends StatelessWidget {
  final List<(double, Color)> segments; // fraction 0..1
  final double height;
  final Color track;
  final double gap;
  const SplitBar({super.key, required this.segments, this.height = 10, this.track = MC.track, this.gap = 2});

  @override
  Widget build(BuildContext context) {
    final total = segments.fold<double>(0, (a, s) => a + s.$1.clamp(0.0, 1.0).toDouble());
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: Container(
        height: height,
        color: track,
        child: Row(children: [
          for (final (f, color) in segments)
            if (f > 0)
              Expanded(
                flex: math.max(1, (f.clamp(0.0, 1.0) * 1000).round()),
                child: Container(color: color, margin: EdgeInsetsDirectional.only(end: gap)),
              ),
          if (total < 1) Expanded(flex: math.max(1, ((1 - total) * 1000).round()), child: const SizedBox()),
        ]),
      ),
    );
  }
}

class Pill extends StatelessWidget {
  final String text;
  final Color fg, bg;
  final bool dot;
  final double fontSize;
  const Pill(this.text, {super.key, required this.fg, required this.bg, this.dot = true, this.fontSize = 13});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (dot) ...[
            Container(width: 7, height: 7, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
            const SizedBox(width: 6),
          ],
          Text(text, style: TextStyle(color: fg, fontSize: fontSize, fontWeight: FontWeight.w600)),
        ]),
      );
}

({String label, Color fg, Color bg}) repStatusStyle(RepStatus s) => switch (s) {
      RepStatus.moving => (label: 'يبيع الآن', fg: MC.burntText, bg: MC.orangeTint),
      RepStatus.stopped => (label: 'متوقف', fg: MC.mutedDeep, bg: MC.plumTint),
      RepStatus.lost => (label: 'GPS مقطوع', fg: MC.crimson, bg: MC.crimsonTint),
      RepStatus.pending => (label: 'في انتظار التسوية', fg: MC.teal, bg: MC.tealTint),
      RepStatus.done => (label: 'اليوم اتقفل', fg: MC.teal, bg: MC.tealTint),
      RepStatus.idle => (label: 'مستني صرف', fg: MC.mutedDeep, bg: MC.plumTint),
    };

class RepStatusPill extends StatelessWidget {
  final RepStatus status;
  const RepStatusPill(this.status, {super.key});
  @override
  Widget build(BuildContext context) {
    final st = repStatusStyle(status);
    return Pill(st.label, fg: st.fg, bg: st.bg);
  }
}

class Avatar extends StatelessWidget {
  final String text;
  final Color bg, fg;
  final double size;
  final double radius;
  const Avatar(this.text, {super.key, this.bg = MC.plumTint, this.fg = MC.plum, this.size = 44, this.radius = 99});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(radius)),
        child: Text(initialOf(text), style: display(size * 0.4, color: fg)),
      );
}

const avatarTones = [
  (MC.orangeTint, MC.burntText),
  (Color(0xFFDCEBEF), MC.teal),
  (MC.plumTint, MC.plum),
  (MC.crimsonTint, MC.crimson),
];

(Color, Color) toneFor(int index) => avatarTones[index % avatarTones.length];

/// صف بخط فاصل فوقه (بديل الكروت)
class LinedRow extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color line;
  const LinedRow({super.key, required this.child, this.padding = const EdgeInsets.symmetric(vertical: 14), this.onTap, this.line = MC.line});
  @override
  Widget build(BuildContext context) {
    final body = Container(
      padding: padding,
      decoration: BoxDecoration(border: Border(top: BorderSide(color: line))),
      child: child,
    );
    return onTap == null ? body : InkWell(onTap: onTap, child: body);
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? hint;
  final Widget? trailing;
  final Color muted;
  const SectionTitle(this.title, {super.key, this.hint, this.trailing, this.muted = MC.muted});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Text(title, style: display(20)),
          if (hint != null) ...[
            const SizedBox(width: 12),
            Flexible(child: Text(hint!, style: TextStyle(fontSize: 13, color: muted), overflow: TextOverflow.ellipsis)),
          ],
          if (trailing != null) ...[const Spacer(), trailing!],
        ]),
      );
}

class QtyStepper extends StatelessWidget {
  final String value;
  final VoidCallback? onInc, onDec, onTapValue;
  final bool error;
  final double width;
  final Color color;
  const QtyStepper({
    super.key,
    required this.value,
    this.onInc,
    this.onDec,
    this.onTapValue,
    this.error = false,
    this.width = 150,
    this.color = MC.plum,
  });
  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: 46,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: error ? MC.crimson : MC.line, width: error ? 2 : 1),
        ),
        child: Row(children: [
          IconButton(onPressed: onInc, icon: const Icon(Icons.add), color: color, tooltip: 'زيادة'),
          Expanded(
            child: InkWell(
              onTap: onTapValue,
              child: Center(child: Text(value, style: display(18, weight: FontWeight.w700))),
            ),
          ),
          IconButton(onPressed: onDec, icon: const Icon(Icons.remove), color: color, tooltip: 'نقص'),
        ]),
      );
}

/// جدول عريض: لو المساحة ضيقة بيعمل سكرول أفقي
class WideTable extends StatelessWidget {
  final double minWidth;
  final Widget child;
  const WideTable({super.key, required this.minWidth, required this.child});
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        if (c.maxWidth >= minWidth) return child;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: minWidth, child: child),
        );
      });
}

class MiniStat extends StatelessWidget {
  final String label, value;
  final Color? color;
  final double size;
  final Color muted;
  const MiniStat(this.label, this.value, {super.key, this.color, this.size = 18, this.muted = MC.muted});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: TextStyle(fontSize: 12, color: muted), maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(value, style: display(size, color: color))),
      ]);
}

class LegendDot extends StatelessWidget {
  final String label;
  final Color color;
  const LegendDot(this.label, this.color, {super.key});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: MC.mutedDeep)),
      ]);
}

// ───────────────────────────────────────────── Async + errors
class AsyncBody<T> extends StatelessWidget {
  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;
  const AsyncBody({super.key, required this.value, required this.builder, this.onRetry});

  @override
  Widget build(BuildContext context) => value.when(
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        data: builder,
        loading: () => const Center(child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator())),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.cloud_off_rounded, size: 40, color: MC.muted),
              const SizedBox(height: 12),
              Text(e is AppException ? e.message : '$e', textAlign: TextAlign.center),
              if (onRetry != null) ...[
                const SizedBox(height: 12),
                OutlinedButton(onPressed: onRetry, child: const Text('حاول تاني')),
              ],
            ]),
          ),
        ),
      );
}

void showError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    backgroundColor: MC.crimson,
    content: Text(e is AppException ? e.message : '$e'),
  ));
}

void showDone(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: MC.teal, content: Text(msg)));
}

// ───────────────────────────────────────────── Desktop shell (القائمة الجانبية)
class NavEntry {
  final String label, route;
  final IconData icon;
  final int? badge;
  const NavEntry(this.label, this.icon, this.route, {this.badge});
}

class ShellPalette {
  final Color rail, railFg, railMuted, railLine, activeBg, activeFg, ground;
  const ShellPalette({
    required this.rail,
    required this.railFg,
    required this.railMuted,
    required this.railLine,
    required this.activeBg,
    required this.activeFg,
    required this.ground,
  });

  static const keeper = ShellPalette(
    rail: MC.ink,
    railFg: Color(0xFFF6EDE6),
    railMuted: MC.onDarkMuted,
    railLine: Color(0xFF4A2A3E),
    activeBg: MC.orange,
    activeFg: MC.ink,
    ground: MC.ground,
  );
  static const manager = ShellPalette(
    rail: MC.plum,
    railFg: Color(0xFFFBEFE8),
    railMuted: Color(0xFFE5C8D5),
    railLine: Color(0xFF7A2B5C),
    activeBg: Color(0xFFFBEFE8),
    activeFg: MC.plum,
    ground: MC.ground,
  );
  static const admin = ShellPalette(
    rail: MC.adminRail,
    railFg: Color(0xFFE4F1EE),
    railMuted: MC.adminOnDark,
    railLine: Color(0xFF24505A),
    activeBg: MC.orange,
    activeFg: MC.adminInk,
    ground: MC.adminGround,
  );
}

class DesktopShell extends StatelessWidget {
  final ShellPalette palette;
  final String subtitle;
  final List<NavEntry> entries;
  final String location;
  final Widget? footer;
  final Widget child;
  const DesktopShell({
    super.key,
    required this.palette,
    required this.subtitle,
    required this.entries,
    required this.location,
    required this.child,
    this.footer,
  });

  bool _isActive(NavEntry e) {
    bool m(NavEntry x) => location == x.route || location.startsWith('${x.route}/');
    if (!m(e)) return false;
    return !entries.any((x) => x != e && m(x) && x.route.length > e.route.length);
  }

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Scaffold(
      backgroundColor: p.ground,
      body: LayoutBuilder(builder: (context, c) {
        final compact = c.maxWidth < 1100;
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            width: compact ? 84 : 248,
            color: p.rail,
            padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 20, vertical: 28),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(mainAxisAlignment: compact ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
                MadarLogo(size: 40, moon: p.railFg),
                if (!compact) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('مدار', style: display(22, weight: FontWeight.w700, color: p.railFg)),
                      Text(subtitle, style: TextStyle(fontSize: 12, color: p.railMuted), overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                ],
              ]),
              const SizedBox(height: 28),
              for (final e in entries) _NavTile(entry: e, active: _isActive(e), compact: compact, palette: p),
              const Spacer(),
              if (footer != null && !compact) footer!,
            ]),
          ),
          Expanded(child: child),
        ]);
      }),
    );
  }
}

class _NavTile extends StatelessWidget {
  final NavEntry entry;
  final bool active, compact;
  final ShellPalette palette;
  const _NavTile({required this.entry, required this.active, required this.compact, required this.palette});
  @override
  Widget build(BuildContext context) {
    final fg = active ? palette.activeFg : palette.railFg;
    final tile = Material(
      color: active ? palette.activeBg : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.go(entry.route),
        child: Container(
          height: 46,
          padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 14),
          child: Row(mainAxisAlignment: compact ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
            Badge(
              isLabelVisible: compact && (entry.badge ?? 0) > 0,
              label: Text('${entry.badge ?? ''}'),
              backgroundColor: MC.crimson,
              child: Icon(entry.icon, color: fg, size: 21),
            ),
            if (!compact) ...[
              const SizedBox(width: 12),
              Expanded(
                child: Text(entry.label,
                    style: TextStyle(color: fg, fontSize: 15, fontWeight: active ? FontWeight.w600 : FontWeight.w400),
                    overflow: TextOverflow.ellipsis),
              ),
              if ((entry.badge ?? 0) > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: MC.crimson, borderRadius: BorderRadius.circular(99)),
                  child: Text('${entry.badge}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                ),
            ],
          ]),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: compact ? Tooltip(message: entry.label, child: tile) : tile,
    );
  }
}

/// محتوى صفحة ديسكتوب: سكرول + padding + عرض أقصى
class DesktopPage extends StatelessWidget {
  final List<Widget> children;
  final double maxWidth;
  final double gap;
  const DesktopPage({super.key, required this.children, this.maxWidth = 1400, this.gap = 28});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(36, 28, 36, 48),
        child: Align(
          alignment: AlignmentDirectional.topStart,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var k = 0; k < children.length; k++) ...[
                if (k > 0) SizedBox(height: gap),
                children[k],
              ],
            ]),
          ),
        ),
      );
}

class PageHeader extends StatelessWidget {
  final String? kicker;
  final String title;
  final List<Widget> actions;
  final Widget? leading;
  final Color muted;
  const PageHeader({super.key, this.kicker, required this.title, this.actions = const [], this.leading, this.muted = MC.muted});
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final compact = c.maxWidth < 560;
        return Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: c.maxWidth),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (leading != null) ...[leading!, const SizedBox(width: 14)],
                Flexible(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    if (kicker != null) Text(kicker!, style: TextStyle(fontSize: 14, color: muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(title, style: display(compact ? 22 : 30, weight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ]),
                ),
              ]),
            ),
            Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: actions),
          ],
        );
      });
}

/// اختيار من مجموعة (segmented) بنفس شكل التصميم
class Segmented<T> extends StatelessWidget {
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  final Color track, ink;
  const Segmented({super.key, required this.options, required this.value, required this.onChanged, this.track = const Color(0xFFEFE6DC), this.ink = MC.ink});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: track, borderRadius: BorderRadius.circular(14)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final (v, label) in options)
            Material(
              color: v == value ? Colors.white : Colors.transparent,
              elevation: v == value ? 1 : 0,
              borderRadius: BorderRadius.circular(11),
              child: InkWell(
                borderRadius: BorderRadius.circular(11),
                onTap: () => onChanged(v),
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  alignment: Alignment.center,
                  child: Text(label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: v == value ? FontWeight.w700 : FontWeight.w400,
                        color: v == value ? ink : MC.mutedDeep,
                      )),
                ),
              ),
            ),
        ]),
      );
}

class DarkPanel extends StatelessWidget {
  final Widget child;
  final Color color;
  final EdgeInsetsGeometry padding;
  const DarkPanel({super.key, required this.child, this.color = MC.ink, this.padding = const EdgeInsets.all(24)});
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(22)),
        child: DefaultTextStyle.merge(style: const TextStyle(color: Color(0xFFF6EDE6)), child: child),
      );
}
