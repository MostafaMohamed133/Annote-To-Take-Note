class ClockSnapshot {
  const ClockSnapshot({
    required this.monotonicNs,
    required this.utcEpochMs,
    required this.timezoneOffsetMinutes,
  });

  final int monotonicNs;
  final int utcEpochMs;
  final int timezoneOffsetMinutes;

  factory ClockSnapshot.fromMap(Map<dynamic, dynamic> map) {
    return ClockSnapshot(
      monotonicNs: (map['monotonicNs'] as num).toInt(),
      utcEpochMs: (map['utcEpochMs'] as num).toInt(),
      timezoneOffsetMinutes:
          (map['timezoneOffsetMinutes'] as num).toInt(),
    );
  }
}
