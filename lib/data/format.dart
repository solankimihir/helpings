import 'package:intl/intl.dart';

import 'models.dart';

String _pad(int n) => n.toString().padLeft(2, '0');

String dayKey(DateTime d) => '${d.year}-${_pad(d.month)}-${_pad(d.day)}';

String todayKey([DateTime? now]) => dayKey(now ?? DateTime.now());

String shiftKey(int days, [DateTime? now]) {
  final n = now ?? DateTime.now();
  return dayKey(DateTime(n.year, n.month, n.day + days));
}

/// Whole calendar days from [key] back to today: 0 today, 1 yesterday,
/// negative for future days. Uses UTC so DST changes don't skew it.
int daysAgo(String key, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final d = parseKey(key);
  return DateTime.utc(
    n.year,
    n.month,
    n.day,
  ).difference(DateTime.utc(d.year, d.month, d.day)).inDays;
}

DateTime parseKey(String key) {
  final p = key.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

String timeKey(int hour, int minute) => '${_pad(hour)}:${_pad(minute)}';

String nowTime([DateTime? now]) {
  final n = now ?? DateTime.now();
  return timeKey(n.hour, n.minute);
}

(int, int) parseTime(String t) {
  final p = t.split(':');
  return (int.parse(p[0]), p.length > 1 ? int.parse(p[1]) : 0);
}

/// `13:05` → `1:05 PM`.
String fmtTime(String t) {
  final (h, m) = parseTime(t);
  final ap = h >= 12 ? 'PM' : 'AM';
  return '${h % 12 == 0 ? 12 : h % 12}:${_pad(m)} $ap';
}

final _thousands = NumberFormat('#,##0', 'en_US');

/// Rounded with thousands separators; empty for null.
String fmtN(double? n) => n == null ? '' : _thousands.format(n.round());

/// Quantity without a trailing `.0`.
String fmtQty(double? q) {
  if (q == null) return '';
  if (q == q.roundToDouble()) return q.toInt().toString();
  return q.toString();
}

/// Lenient number parse used for form fields ("2", "1.5", "200 kcal").
double? parseNum(String v) {
  final cleaned = v.replaceAll(RegExp(r'[^0-9.]'), '');
  if (cleaned.isEmpty) return null;
  return double.tryParse(cleaned);
}

String _unitShort(FoodUnit? u, double? q) {
  switch (u) {
    case null:
    case FoodUnit.piece:
      return '';
    case FoodUnit.gram:
      return 'g';
    case FoodUnit.spoon:
    case FoodUnit.cup:
      final base = u.label.toLowerCase();
      return (q ?? 0) > 1 ? '${base}s' : base;
  }
}

/// "2 Idli", "1 cup Dal", "150 g Rice".
String lineText(String name, double? qty, FoodUnit? unit) {
  final bits = <String>[];
  if (qty != null) bits.add(fmtQty(qty));
  final us = _unitShort(unit, qty);
  if (us.isNotEmpty) bits.add(us);
  bits.add(name);
  return bits.join(' ');
}

/// "2 Pieces", "1 Cup", "— no unit".
String qtyLabel(double? qty, FoodUnit? unit) {
  final q = qty == null ? '—' : fmtQty(qty);
  final u = unit == null
      ? 'no unit'
      : (qty ?? 0) > 1
      ? '${unit.label}s'
      : unit.label;
  return '$q $u';
}

String plural(int n, String one, [String? many]) =>
    '$n ${n == 1 ? one : (many ?? '${one}s')}';

/// Card-level calorie label: "490 kcal", "210+ kcal", "No calories".
String calLabel(MealTotals t) {
  if (t.count == 0) return '—';
  if (t.complete) return '${fmtN(t.sum)} kcal';
  if (t.sum > 0) return '${fmtN(t.sum)}+ kcal';
  return 'No calories';
}

String longDate(DateTime d) => DateFormat('EEEE, MMMM d', 'en_US').format(d);

String dayGroupLabel(String key, [DateTime? now]) {
  if (key == todayKey(now)) return 'Today';
  if (key == shiftKey(-1, now)) return 'Yesterday';
  final d = parseKey(key);
  final n = now ?? DateTime.now();
  return d.year == n.year
      ? DateFormat('MMMM d', 'en_US').format(d)
      : DateFormat('MMMM d, y', 'en_US').format(d);
}
