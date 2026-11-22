class FormattedTimestamp {
  const FormattedTimestamp({
    required this.localDate,
    required this.localTime,
    required this.localDateTime,
    required this.utcIso,
    required this.timezoneOffset,
  });

  final String localDate;
  final String localTime;
  final String localDateTime;
  final String utcIso;
  final String timezoneOffset;
}

class TimeFormatService {
  static String _two(int value) => value.toString().padLeft(2, '0');
  static String _three(int value) => value.toString().padLeft(3, '0');

  static String _offsetText(int offsetMinutes) {
    final sign = offsetMinutes >= 0 ? '+' : '-';
    final absolute = offsetMinutes.abs();
    return '$sign${_two(absolute ~/ 60)}:${_two(absolute % 60)}';
  }

  /// Formats the Android wall clock at millisecond precision.
  /// Exact monotonic event ordering is preserved separately in t_mono_ns.
  static FormattedTimestamp format({
    required int utcEpochMs,
    required int timezoneOffsetMinutes,
  }) {
    final utc = DateTime.fromMillisecondsSinceEpoch(utcEpochMs, isUtc: true);
    final localWallClock = utc.add(Duration(minutes: timezoneOffsetMinutes));

    final date = '${localWallClock.year.toString().padLeft(4, '0')}-'
        '${_two(localWallClock.month)}-${_two(localWallClock.day)}';
    final time = '${_two(localWallClock.hour)}:'
        '${_two(localWallClock.minute)}:'
        '${_two(localWallClock.second)}.'
        '${_three(localWallClock.millisecond)}';
    final offset = _offsetText(timezoneOffsetMinutes);
    final utcIso = '${utc.year.toString().padLeft(4, '0')}-'
        '${_two(utc.month)}-${_two(utc.day)}T'
        '${_two(utc.hour)}:${_two(utc.minute)}:${_two(utc.second)}.'
        '${_three(utc.millisecond)}Z';

    return FormattedTimestamp(
      localDate: date,
      localTime: time,
      localDateTime: '$date $time $offset',
      utcIso: utcIso,
      timezoneOffset: offset,
    );
  }

  /// Returns elapsed time in exact decimal seconds without converting the
  /// nanosecond value to a floating-point number.
  static String elapsedSecondsFromNs(int elapsedNs) {
    final safe = elapsedNs < 0 ? 0 : elapsedNs;
    final seconds = safe ~/ 1000000000;
    final nanoseconds = safe % 1000000000;
    return '$seconds.${nanoseconds.toString().padLeft(9, '0')}';
  }

  static String elapsedHmsMs(int elapsedMs) {
    final safe = elapsedMs < 0 ? 0 : elapsedMs;
    final hours = safe ~/ 3600000;
    final minutes = (safe % 3600000) ~/ 60000;
    final seconds = (safe % 60000) ~/ 1000;
    final milliseconds = safe % 1000;
    return '${hours.toString().padLeft(2, '0')}:'
        '${_two(minutes)}:${_two(seconds)}.${_three(milliseconds)}';
  }

  static String liveLocalTime(DateTime value) {
    final date = '${value.year.toString().padLeft(4, '0')}-'
        '${_two(value.month)}-${_two(value.day)}';
    final time = '${_two(value.hour)}:${_two(value.minute)}:'
        '${_two(value.second)}.${_three(value.millisecond)}';
    final offset = value.timeZoneOffset.inMinutes;
    return '$date $time ${_offsetText(offset)}';
  }
}
