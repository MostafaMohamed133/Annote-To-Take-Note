import 'package:flutter_test/flutter_test.dart';
import 'package:road_guard_annotator/services/csv_export_service.dart';

void main() {
  test('exports one row per button tap and preserves the legacy first columns', () {
    final csv = CsvExportService.build([
      {
        'annotation_id': 'A002',
        'annotation_name': 'POTHOLE',
        't_utc_epoch_ms': 1794127939721,
        't_mono_ns': 845101230000,
        'elapsed_ns': 170580000000,
        'elapsed_ms': 170580,
        'local_date': '2026-11-21',
        'local_time': '15:32:19.721',
        'timestamp_local': '2026-11-21 15:32:19.721 +02:00',
        'timestamp_utc_iso': '2026-11-21T13:32:19.721Z',
        'timezone_offset_minutes': 120,
        'timezone_offset': '+02:00',
        'session_id': 'S1',
        'trip_name': 'Test Trip',
        'recording_id': 'REC_001',
        'session_start_mono_ns': 674521230000,
        'session_start_utc_ms': 1794127769241,
      },
      {
        'annotation_id': 'A001',
        'annotation_name': 'BUMP',
        't_utc_epoch_ms': 1794127939621,
        't_mono_ns': 845001230000,
        'elapsed_ns': 170480000000,
        'elapsed_ms': 170480,
        'local_date': '2026-11-21',
        'local_time': '15:32:19.621',
        'timestamp_local': '2026-11-21 15:32:19.621 +02:00',
        'timestamp_utc_iso': '2026-11-21T13:32:19.621Z',
        'timezone_offset_minutes': 120,
        'timezone_offset': '+02:00',
        'session_id': 'S1',
        'trip_name': 'Test Trip',
        'recording_id': 'REC_001',
        'session_start_mono_ns': 674521230000,
        'session_start_utc_ms': 1794127769241,
      },
    ]);

    expect(csv, contains('"time","seconds_elapsed","text","millisecond_press_duration"'));
    expect(csv, contains('"1794127939621000000"'));
    expect(csv, contains('"170.480000000"'));
    expect(csv, contains('"BUMP"'));
    expect(csv, contains('"POTHOLE"'));
    expect(csv, contains('"MANUAL_BUTTON_TAP"'));
    expect(csv, contains('"2026-11-21 15:32:19.621 +02:00"'));
    expect(csv, contains('"2026-11-21"'));
    expect(csv, contains('"15:32:19.621"'));
    expect(csv, contains('"845001230000"'));

    final lines = csv.trim().split('\n');
    expect(lines.length, 3); // header + two taps
    expect(lines[1], contains('"BUMP"')); // ascending time order
    expect(lines[2], contains('"POTHOLE"'));
  });

  test('escapes commas, quotes and Arabic custom annotation names', () {
    final csv = CsvExportService.build([
      {
        'annotation_name': 'مطب، "مرتفع"',
        't_utc_epoch_ms': 1794127939621,
        't_mono_ns': 845001230000,
        'elapsed_ns': 170480000000,
      },
    ]);

    expect(csv, contains('"مطب، ""مرتفع"""'));
  });

  test('supports an empty trip export with a header only', () {
    final csv = CsvExportService.build([]);
    expect(csv.trim().split('\n').length, 1);
    expect(csv, contains('"annotation_name"'));
  });
}
