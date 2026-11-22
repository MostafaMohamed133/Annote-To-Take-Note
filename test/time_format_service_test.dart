import 'package:flutter_test/flutter_test.dart';
import 'package:road_guard_annotator/services/time_format_service.dart';

void main() {
  group('TimeFormatService', () {
    test('formats local date and time with milliseconds and timezone', () {
      final utc = DateTime.utc(2026, 11, 21, 13, 9, 5, 123);
      final formatted = TimeFormatService.format(
        utcEpochMs: utc.millisecondsSinceEpoch,
        timezoneOffsetMinutes: 120,
      );

      expect(formatted.localDate, '2026-11-21');
      expect(formatted.localTime, '15:09:05.123');
      expect(formatted.localDateTime, '2026-11-21 15:09:05.123 +02:00');
      expect(formatted.utcIso, '2026-11-21T13:09:05.123Z');
    });

    test('formats elapsed nanoseconds without floating point conversion', () {
      expect(
        TimeFormatService.elapsedSecondsFromNs(170480123456),
        '170.480123456',
      );
    });
  });
}
