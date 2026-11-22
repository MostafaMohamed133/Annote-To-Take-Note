import 'package:flutter/services.dart';

import '../models/clock_snapshot.dart';

class ClockService {
  static const MethodChannel _channel = MethodChannel('road_guard/clock');

  /// Captures Android monotonic time and wall-clock time in one native call.
  /// The monotonic value is the authoritative timestamp for sensor alignment.
  static Future<ClockSnapshot> capture() async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'captureClockSnapshot',
    );
    if (result == null) {
      throw StateError('Android clock snapshot was empty.');
    }
    return ClockSnapshot.fromMap(result);
  }

  /// Keeps the phone screen awake only while a field annotation session is active.
  static Future<void> setKeepScreenOn(bool enabled) async {
    await _channel.invokeMethod<void>(
      'setKeepScreenOn',
      {'enabled': enabled},
    );
  }
}
