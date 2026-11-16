import 'package:calm_ig/stats/day_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dayKey pads and uses the local date', () {
    expect(dayKey(DateTime(2026, 1, 5, 23, 59)), '2026-01-05');
    expect(dayKey(DateTime(2026, 11, 16)), '2026-11-16');
  });

  test('splitByDay keeps a same-day stretch whole', () {
    final parts = splitByDay(
      DateTime(2026, 11, 16, 20),
      DateTime(2026, 11, 16, 20, 30),
    );
    expect(parts, {'2026-11-16': const Duration(minutes: 30)});
  });

  test('splitByDay cuts at midnight', () {
    final parts = splitByDay(
      DateTime(2026, 11, 16, 23, 50),
      DateTime(2026, 11, 17, 0, 15),
    );
    expect(parts, {
      '2026-11-16': const Duration(minutes: 10),
      '2026-11-17': const Duration(minutes: 15),
    });
  });

  test('splitByDay across several days and month ends', () {
    final parts = splitByDay(
      DateTime(2026, 11, 30, 23),
      DateTime(2026, 12, 2, 1),
    );
    expect(parts, {
      '2026-11-30': const Duration(hours: 1),
      '2026-12-01': const Duration(hours: 24),
      '2026-12-02': const Duration(hours: 1),
    });
  });

  test('splitByDay of an empty or reversed range is empty', () {
    final t = DateTime(2026, 11, 16, 12);
    expect(splitByDay(t, t), isEmpty);
    expect(splitByDay(t, t.subtract(const Duration(minutes: 1))), isEmpty);
  });

  test('lastDays is oldest first and ends today', () {
    final days = lastDays(DateTime(2026, 11, 2, 15), 3);
    expect(days.map(dayKey), ['2026-10-31', '2026-11-01', '2026-11-02']);
  });
}
