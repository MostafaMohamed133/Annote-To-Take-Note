import 'dart:convert';

import 'time_format_service.dart';

class CsvExportService {
  /// The first four columns deliberately match the user's existing
  /// Sensor Logger annotation CSV layout.
  static const List<String> headers = [
    'time',
    'seconds_elapsed',
    'text',
    'millisecond_press_duration',
    'session_id',
    'trip_name',
    'recording_id',
    'annotation_id',
    'annotation_name',
    'annotation_type',
    't_mono_ns',
    't_utc_epoch_ms',
    'timestamp_local',
    'local_date',
    'local_time',
    'timestamp_utc_iso',
    'elapsed_ns',
    'elapsed_ms',
    'elapsed_hms_ms',
    'timezone_offset_minutes',
    'timezone_offset',
    'annotator_id',
    'device_id',
    'latitude',
    'longitude',
    'gps_accuracy_m',
    'notes',
    'session_start_mono_ns',
    'session_start_utc_ms',
    'elapsed_origin',
    'wall_clock_resolution_ms',
  ];

  static String _escape(Object? value) {
    if (value == null) return '""';
    final text = value.toString();
    return '"${text.replaceAll('"', '""')}"';
  }

  static Map<String, Object?> _compatibilityRow(Map<String, Object?> row) {
    final utcMs = (row['t_utc_epoch_ms'] as num).toInt();
    final elapsedNs = (row['elapsed_ns'] as num).toInt();
    final annotationName = row['annotation_name'] as String;
    return {
      ...row,
      // Wall-clock timestamps are millisecond resolution. The monotonic
      // nanosecond field is the synchronization source for the IMU streams.
      'time': utcMs * 1000000,
      'seconds_elapsed': TimeFormatService.elapsedSecondsFromNs(elapsedNs),
      'text': annotationName,
      'millisecond_press_duration': null,
      'annotation_type': 'MANUAL_BUTTON_TAP',
      'elapsed_origin': 'TRIP_SESSION_START',
      'wall_clock_resolution_ms': 1,
    };
  }

  static String build(List<Map<String, Object?>> rows) {
    final sorted = [...rows]
      ..sort(
        (a, b) => (a['t_mono_ns'] as num).compareTo(b['t_mono_ns'] as num),
      );
    final output = StringBuffer()..write('\uFEFF');
    output.writeln(headers.map(_escape).join(','));
    for (final rawRow in sorted) {
      final row = _compatibilityRow(rawRow);
      output.writeln(headers.map((key) => _escape(row[key])).join(','));
    }
    return output.toString();
  }

  static List<int> encode(List<Map<String, Object?>> rows) =>
      utf8.encode(build(rows));
}
