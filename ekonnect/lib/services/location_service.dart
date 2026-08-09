import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'firestore_service.dart';

/// Why a location fix could not be obtained.
///
/// Previously every one of these collapsed into a single null return, so the UI
/// told users to "enable location permissions" even when permissions were
/// granted and GPS was on — which is the most common case and the least
/// actionable message.
enum LocationFailure {
  /// Device location (GPS) is switched off entirely.
  serviceDisabled,

  /// The user declined, but can be asked again.
  permissionDenied,

  /// Declined permanently — only Settings can fix it.
  permissionDeniedForever,

  /// Permissions fine, GPS on, but no fix arrived in time. Typically indoors,
  /// underground, or under heavy cover. This is the usual real-world failure.
  noFix,
}

/// A location attempt: either a [position], or a [failure] explaining why not.
class LocationResult {
  final Position? position;
  final LocationFailure? failure;

  /// True when the fix came from the OS cache rather than a live reading, so
  /// callers can warn that the pin may be slightly stale.
  final bool isApproximate;

  const LocationResult.success(this.position, {this.isApproximate = false})
      : failure = null;

  const LocationResult.failed(this.failure)
      : position = null,
        isApproximate = false;

  bool get isSuccess => position != null;

  /// A message that describes what actually went wrong and what to do about it.
  String get message {
    switch (failure) {
      case LocationFailure.serviceDisabled:
        return 'Location is turned off. Switch on GPS and try again.';
      case LocationFailure.permissionDenied:
        return 'eKonnect needs location access to send responders to you.';
      case LocationFailure.permissionDeniedForever:
        return 'Location access is blocked. Enable it in Settings → Apps → '
            'eKonnect → Permissions.';
      case LocationFailure.noFix:
        return 'Could not get a GPS fix. Move near a window or outdoors, then '
            'retry.';
      case null:
        return '';
    }
  }
}

class LocationService {
  static final _rtdb = FirebaseDatabase.instance;
  static Timer? _locationTimer;

  // ── Test-mode drive simulation ───────────────────────────────────────────
  // Lets navigation, voice guidance and live tracking be exercised without
  // physically driving. Deliberately lives here rather than in a screen so it
  // is transparent to *every* consumer — the nav camera, the turn prompts and
  // the RTDB publisher all see the synthetic position as if it were real GPS.

  static StreamController<Position>? _simController;
  static Timer? _simTimer;
  static Position? _simPosition;

  static bool get isSimulating => _simTimer != null;

  /// Walks a synthetic position along [route] at [speedKmh].
  ///
  /// Emits roughly once a second so heading changes look smooth and the voice
  /// guidance distance bands are crossed at a realistic rate.
  static void startSimulation(List<LatLng> route, {double speedKmh = 40}) {
    stopSimulation();
    if (route.length < 2) return;

    final controller = StreamController<Position>.broadcast();
    _simController = controller;

    var index = 0;
    var travelled = 0.0; // metres into the current segment
    final metresPerTick = speedKmh * 1000 / 3600; // one tick == one second

    _simTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      travelled += metresPerTick;

      // Consume whole segments until the remaining distance fits inside one.
      while (index < route.length - 1) {
        final a = route[index];
        final b = route[index + 1];
        final segment = Geolocator.distanceBetween(
            a.latitude, a.longitude, b.latitude, b.longitude);
        if (travelled < segment || segment == 0) break;
        travelled -= segment;
        index++;
      }

      if (index >= route.length - 1) {
        _emitSim(route.last, route[route.length - 2], route.last, controller);
        stopSimulation();
        return;
      }

      final a = route[index];
      final b = route[index + 1];
      final segment = Geolocator.distanceBetween(
          a.latitude, a.longitude, b.latitude, b.longitude);
      final t = segment == 0 ? 0.0 : (travelled / segment).clamp(0.0, 1.0);
      final here = LatLng(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      );
      _emitSim(here, a, b, controller);
    });
  }

  static void _emitSim(
      LatLng here, LatLng from, LatLng to, StreamController<Position> sink) {
    final bearing = Geolocator.bearingBetween(
        from.latitude, from.longitude, to.latitude, to.longitude);
    final pos = Position(
      latitude: here.latitude,
      longitude: here.longitude,
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: (bearing + 360) % 360,
      headingAccuracy: 0,
      // Above the stationary threshold so nav uses this heading, not a fallback.
      speed: 11,
      speedAccuracy: 0,
    );
    _simPosition = pos;
    if (!sink.isClosed) sink.add(pos);
  }

  static void stopSimulation() {
    _simTimer?.cancel();
    _simTimer = null;
    _simController?.close();
    _simController = null;
    _simPosition = null;
  }

  /// Attempts a fix, degrading gracefully rather than failing outright.
  ///
  /// A high-accuracy fix can take 30s+ indoors and may never arrive, so this
  /// walks down a ladder: precise → coarse → last known. For dispatch, an
  /// approximate position now beats a perfect one that never comes.
  static Future<LocationResult> resolvePosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const LocationResult.failed(LocationFailure.serviceDisabled);
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      return const LocationResult.failed(LocationFailure.permissionDenied);
    }
    if (permission == LocationPermission.deniedForever) {
      return const LocationResult.failed(
          LocationFailure.permissionDeniedForever);
    }

    // 1. Precise fix, short leash.
    final precise = await _tryFix(LocationAccuracy.high, 8);
    if (precise != null) return LocationResult.success(precise);

    // 2. Coarse fix — cell/wifi derived, far more likely to succeed indoors.
    final coarse = await _tryFix(LocationAccuracy.medium, 6);
    if (coarse != null) return LocationResult.success(coarse);

    // 3. Whatever the OS last saw. Better than refusing to send an SOS.
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        return LocationResult.success(last, isApproximate: true);
      }
    } catch (_) {
      // fall through
    }

    return const LocationResult.failed(LocationFailure.noFix);
  }

  static Future<Position?> _tryFix(LocationAccuracy accuracy, int seconds) async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: accuracy,
          // Geolocator's own limit throws cleanly; the outer timeout is a
          // belt-and-braces guard in case the platform channel stalls.
          timeLimit: Duration(seconds: seconds),
        ),
      ).timeout(Duration(seconds: seconds + 2));
    } catch (_) {
      return null; // TimeoutException, LocationServiceDisabled, platform error
    }
  }

  /// Convenience wrapper for callers that only need "a position or nothing".
  static Future<Position?> getCurrentPosition() async {
    // While simulating, the synthetic point *is* the truth — otherwise the
    // RTDB publisher would broadcast the device's real, stationary location
    // and the patient would watch a responder that never moves.
    if (_simPosition != null) return _simPosition;
    final result = await resolvePosition();
    return result.position;
  }

  static Stream<Position> positionStream() {
    final sim = _simController;
    if (sim != null) return sim.stream;
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    );
  }

  /// Publishes the responder's position every few seconds while on a job.
  ///
  /// Writes to two places on purpose. Realtime Database is the cheaper channel
  /// for high-frequency updates, but it is optional — if no RTDB instance
  /// exists the write simply fails and tracking still works, because the
  /// authoritative copy goes onto the incident document in Firestore, which the
  /// patient is already streaming.
  static void startLiveTracking(String uid, {String? incidentId}) {
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final pos = await getCurrentPosition();
      if (pos == null) return;

      if (incidentId != null) {
        try {
          await FirestoreService.updateResponderLocation(
            incidentId: incidentId,
            lat: pos.latitude,
            lng: pos.longitude,
            heading: pos.heading,
          );
        } catch (_) {
          // Never let a failed publish kill the timer.
        }
      }

      try {
        await _rtdb.ref('locations/$uid').set({
          'lat': pos.latitude,
          'lng': pos.longitude,
          'heading': pos.heading,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
      } catch (_) {
        // No RTDB instance configured — Firestore above already covers us.
      }
    });
  }

  static void stopLiveTracking(String uid) {
    _locationTimer?.cancel();
    _locationTimer = null;
    try {
      _rtdb.ref('locations/$uid').remove();
    } catch (_) {
      // No RTDB instance — nothing to clean up.
    }
  }

  // Stream responder location for the user watching their job
  static Stream<Map<String, double>?> streamResponderLocation(
      String responderId) {
    return _rtdb.ref('locations/$responderId').onValue.map((event) {
      final data = event.snapshot.value as Map?;
      if (data == null) return null;
      return {
        'lat': (data['lat'] as num).toDouble(),
        'lng': (data['lng'] as num).toDouble(),
      };
    });
  }

  // Includes heading so map markers can be rotated to face direction of travel
  static Stream<Map<String, double>?> streamResponderLocationWithHeading(
      String responderId) {
    return _rtdb.ref('locations/$responderId').onValue.map((event) {
      final data = event.snapshot.value as Map?;
      if (data == null) return null;
      return {
        'lat': (data['lat'] as num).toDouble(),
        'lng': (data['lng'] as num).toDouble(),
        'heading': (data['heading'] as num?)?.toDouble() ?? 0.0,
      };
    });
  }

  static double distanceInKm(
      double lat1, double lng1, double lat2, double lng2) {
    return Geolocator.distanceBetween(lat1, lng1, lat2, lng2) / 1000;
  }
}
