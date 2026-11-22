import 'dart:async';

import 'package:geolocator/geolocator.dart';

class LocationSnapshot {
  const LocationSnapshot({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.locationUtcMs,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final int locationUtcMs;
}

/// GPS is supplementary. Marker timestamps are captured before this cached
/// location is read, so location lookup never delays the annotation timestamp.
class LocationService {
  StreamSubscription<Position>? _subscription;
  Position? _latestPosition;

  Position? get latestPosition => _latestPosition;

  Future<bool> start() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return false;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return false;
      }

      final last = await Geolocator.getLastKnownPosition();
      if (last != null) _latestPosition = last;

      await _subscription?.cancel();
      _subscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 1,
        ),
      ).listen(
        (position) => _latestPosition = position,
        onError: (_) {},
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  LocationSnapshot? getFreshSnapshot({int maxAgeSeconds = 15}) {
    final position = _latestPosition;
    if (position == null) return null;
    final age = DateTime.now().difference(position.timestamp).inSeconds;
    if (age < 0 || age > maxAgeSeconds) return null;
    return LocationSnapshot(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
      locationUtcMs: position.timestamp.toUtc().millisecondsSinceEpoch,
    );
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
