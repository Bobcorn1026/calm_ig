/// Local calendar days. Days start at local midnight, like Screen Time.
library;

String _two(int n) => n.toString().padLeft(2, '0');

/// `2026-11-16` for the local day containing [t]. The iOS App Intent uses
/// the same format for its bounce counter (InstagramPassIntent.swift).
String dayKey(DateTime t) {
  final l = t.toLocal();
  return '${l.year.toString().padLeft(4, '0')}-${_two(l.month)}-${_two(l.day)}';
}

DateTime startOfDay(DateTime t) {
  final l = t.toLocal();
  return DateTime(l.year, l.month, l.day);
}

DateTime nextMidnight(DateTime t) {
  final l = t.toLocal();
  return DateTime(l.year, l.month, l.day + 1);
}

/// Splits `[from, to)` at local midnights: how much of it fell on each day.
Map<String, Duration> splitByDay(DateTime from, DateTime to) {
  final parts = <String, Duration>{};
  var cursor = from;
  while (cursor.isBefore(to)) {
    final boundary = nextMidnight(cursor);
    final end = boundary.isBefore(to) ? boundary : to;
    final key = dayKey(cursor);
    parts[key] = (parts[key] ?? Duration.zero) + end.difference(cursor);
    cursor = end;
  }
  return parts;
}

/// The [count] days ending with the day of [today], oldest first.
List<DateTime> lastDays(DateTime today, int count) {
  final start = startOfDay(today);
  return [
    for (var i = count - 1; i >= 0; i--)
      DateTime(start.year, start.month, start.day - i),
  ];
}
