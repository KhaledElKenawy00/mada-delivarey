import 'package:intl/intl.dart';

final _money = NumberFormat('#,##0', 'en_US');

/// 57000 → 57,000
String money(num v) => _money.format(v.round());

/// 12.0 → 12 ، 2.5 → 2.5
String qty(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

const arMonths = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
const arDays = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];

String hm(DateTime? t) {
  if (t == null) return '—';
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'ص' : 'م'}';
}

/// الخميس 5 نوفمبر
String dayLabel(DateTime t) => '${arDays[t.weekday - 1]} ${t.day} ${arMonths[t.month - 1]}';

/// 31 ديسمبر 2026
String dateLabel(DateTime t) => '${t.day} ${arMonths[t.month - 1]} ${t.year}';

String monthLabel(DateTime t) => '${arMonths[t.month - 1]} ${t.year}';

String timeAgo(DateTime? t) {
  if (t == null) return 'مفيش إشارة';
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return 'منذ ${d.inSeconds.clamp(1, 59)} ث';
  if (d.inMinutes < 60) return 'منذ ${d.inMinutes} د';
  if (d.inHours < 24) return 'منذ ${d.inHours} س';
  return 'منذ ${d.inDays} يوم';
}

double parseNum(String v) => double.tryParse(v.replaceAll(',', '').replaceAll('٫', '.').trim()) ?? 0;
