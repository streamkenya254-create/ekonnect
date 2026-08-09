import 'dart:convert';
import 'dart:math';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

/// Google Routes API (`routes.googleapis.com`).
///
/// This replaces the legacy Directions API (`maps/api/directions/json`), which
/// Google no longer permits new Cloud projects to enable — calls to it come
/// back `REQUEST_DENIED / LegacyApiNotActivatedMapError`.
///
/// Requires **Routes API** to be enabled for the project. If it is not, every
/// call degrades to [RouteResult.isEstimate] — a straight-line distance and a
/// speed-based ETA — so the UI still shows something truthful rather than
/// silently rendering nothing.
class RoutesService {
  RoutesService._();

  static const _apiKey = 'AIzaSyCWZNqPl2Tvg7Zz8NXvuD0E86wPRJi2DQc';
  static const _endpoint =
      'https://routes.googleapis.com/directions/v2:computeRoutes';

  /// Average emergency-response speed used for fallback ETAs.
  static const _avgSpeedKmh = 40.0;

  /// Computes a driving route from [origin] to [destination].
  ///
  /// Never throws and never returns null — on any failure it returns a
  /// straight-line [RouteResult] flagged with `isEstimate: true`.
  /// Pass [includeSteps] to also fetch turn-by-turn instructions (needed for
  /// in-app navigation; skip it for simple tracking to keep responses small).
  static Future<RouteResult> compute({
    required LatLng origin,
    required LatLng destination,
    bool includeSteps = false,
  }) async {
    try {
      final fields = <String>[
        'routes.distanceMeters',
        'routes.duration',
        'routes.polyline.encodedPolyline',
        if (includeSteps) ...[
          'routes.legs.steps.navigationInstruction',
          'routes.legs.steps.distanceMeters',
          'routes.legs.steps.endLocation',
        ],
      ].join(',');

      final res = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Content-Type': 'application/json',
              'X-Goog-Api-Key': _apiKey,
              'X-Goog-FieldMask': fields,
            },
            body: jsonEncode({
              'origin': _waypoint(origin),
              'destination': _waypoint(destination),
              'travelMode': 'DRIVE',
              'routingPreference': 'TRAFFIC_AWARE',
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          return _parse(routes.first as Map<String, dynamic>);
        }
      }
    } catch (_) {
      // Network error, timeout, or malformed payload — fall through.
    }
    return _estimate(origin, destination);
  }

  static Map<String, dynamic> _waypoint(LatLng p) => {
        'location': {
          'latLng': {'latitude': p.latitude, 'longitude': p.longitude}
        }
      };

  static RouteResult _parse(Map<String, dynamic> route) {
    final encoded =
        (route['polyline'] as Map<String, dynamic>?)?['encodedPolyline']
            as String?;

    final steps = <NavStep>[];
    for (final leg in (route['legs'] as List? ?? const [])) {
      for (final raw in ((leg as Map)['steps'] as List? ?? const [])) {
        final step = raw as Map;
        final instruction = (step['navigationInstruction']
            as Map<String, dynamic>?)?['instructions'] as String?;
        final end =
            (step['endLocation'] as Map<String, dynamic>?)?['latLng'] as Map?;
        if (instruction == null || end == null) continue;
        steps.add(NavStep(
          instruction: instruction,
          distanceMeters: (step['distanceMeters'] as num?)?.toInt() ?? 0,
          endLocation: LatLng(
            (end['latitude'] as num).toDouble(),
            (end['longitude'] as num).toDouble(),
          ),
        ));
      }
    }

    return RouteResult(
      points: encoded != null ? decodePolyline(encoded) : const [],
      distanceMeters: (route['distanceMeters'] as num?)?.toInt() ?? 0,
      duration: _parseDuration(route['duration'] as String?),
      steps: steps,
      isEstimate: false,
    );
  }

  /// Routes API returns durations as protobuf strings, e.g. `"352s"`.
  static Duration _parseDuration(String? raw) {
    if (raw == null) return Duration.zero;
    return Duration(seconds: int.tryParse(raw.replaceAll('s', '')) ?? 0);
  }

  static RouteResult _estimate(LatLng origin, LatLng destination) {
    final metres = metresBetween(origin, destination).round();
    final seconds = (metres / (_avgSpeedKmh * 1000 / 3600)).round();
    return RouteResult(
      // Two points still draw a line, so the user sees direction of approach.
      // Callers render estimates differently to avoid implying a real road path.
      points: [origin, destination],
      distanceMeters: metres,
      duration: Duration(seconds: seconds.clamp(60, 24 * 3600)),
      steps: const [],
      isEstimate: true,
    );
  }

  /// Decodes Google's encoded-polyline format into coordinates.
  static List<LatLng> decodePolyline(String encoded) {
    final points = <LatLng>[];
    int index = 0, lat = 0, lng = 0;

    while (index < encoded.length) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : result >> 1;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : result >> 1;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  /// Great-circle distance in metres.
  static double metresBetween(LatLng a, LatLng b) {
    const earthRadius = 6371000.0;
    final phi1 = a.latitude * pi / 180;
    final phi2 = b.latitude * pi / 180;
    final dPhi = (b.latitude - a.latitude) * pi / 180;
    final dLambda = (b.longitude - a.longitude) * pi / 180;
    final h = sin(dPhi / 2) * sin(dPhi / 2) +
        cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2);
    return earthRadius * 2 * atan2(sqrt(h), sqrt(1 - h));
  }

  /// Initial bearing from [a] to [b], in degrees clockwise from north.
  static double bearingBetween(LatLng a, LatLng b) {
    final phi1 = a.latitude * pi / 180;
    final phi2 = b.latitude * pi / 180;
    final dLambda = (b.longitude - a.longitude) * pi / 180;
    final y = sin(dLambda) * cos(phi2);
    final x = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(dLambda);
    return (atan2(y, x) * 180 / pi + 360) % 360;
  }
}

/// A single turn instruction along a route.
class NavStep {
  final String instruction;
  final int distanceMeters;
  final LatLng endLocation;

  const NavStep({
    required this.instruction,
    required this.distanceMeters,
    required this.endLocation,
  });
}

/// A computed driving route, plus display helpers.
class RouteResult {
  final List<LatLng> points;
  final int distanceMeters;
  final Duration duration;
  final List<NavStep> steps;

  /// True when this is a straight-line approximation rather than a real road
  /// route — i.e. the Routes API was unreachable or not enabled.
  final bool isEstimate;

  const RouteResult({
    required this.points,
    required this.distanceMeters,
    required this.duration,
    required this.steps,
    required this.isEstimate,
  });

  bool get isEmpty => points.isEmpty;

  /// "850 m", "2.4 km", "17 km"
  String get distanceText {
    if (distanceMeters < 1000) return '$distanceMeters m';
    final km = distanceMeters / 1000;
    return '${km.toStringAsFixed(km >= 10 ? 0 : 1)} km';
  }

  /// "< 1 min", "12 min", "1h 05m"
  String get durationText {
    final mins = duration.inMinutes;
    if (mins < 1) return '< 1 min';
    if (mins < 60) return '$mins min';
    return '${mins ~/ 60}h ${(mins % 60).toString().padLeft(2, '0')}m';
  }

  /// Whole minutes, floored at 1 — for compact ETA badges.
  int get etaMinutes => duration.inMinutes < 1 ? 1 : duration.inMinutes;

  /// Clock time the responder is expected to arrive.
  DateTime arrivalAt([DateTime? from]) =>
      (from ?? DateTime.now()).add(duration);

  /// "10:42" in 24-hour form.
  String arrivalText([DateTime? from]) {
    final t = arrivalAt(from);
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }

  /// The step the driver is currently on, given their position: the first step
  /// whose end point is still ahead of them.
  NavStep? currentStep(LatLng position) {
    if (steps.isEmpty) return null;
    for (final step in steps) {
      if (RoutesService.metresBetween(position, step.endLocation) > 25) {
        return step;
      }
    }
    return steps.last;
  }
}
