import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../models/care_point_model.dart';
import 'ai_service.dart';
import 'routes_service.dart';

/// Finds places that can take over an emergency.
///
/// Two sources, in strict priority order:
///   1. **Registered Care Points** — operators who signed up and declared their
///      services. Trusted, and matched on real service data.
///   2. **Google Places** — everything else nearby. Fills the map from day one,
///      but carries only a name, category and phone, so it is always labelled
///      as unverified.
///
/// Registered points are never displaced by Places results: a responder should
/// see the facility that has said "we can take this" before an unknown one.
class CarePointService {
  CarePointService._();

  static const _collection = 'carePoints';
  static const _apiKey = 'AIzaSyCWZNqPl2Tvg7Zz8NXvuD0E86wPRJi2DQc';
  static const _placesEndpoint =
      'https://places.googleapis.com/v1/places:searchNearby';

  static final _db = FirebaseFirestore.instance;

  /// Everything nearby that could help, best first.
  ///
  /// [need] is what the responder is looking for, free text — "severe burns",
  /// "maternity", "trauma surgery". It drives the AI ranking.
  static Future<List<CarePoint>> findNearby({
    required LatLng origin,
    required String incidentType,
    String? need,
    double radiusMetres = 15000,
    int limit = 6,
  }) async {
    final registered = await _registeredNear(origin, radiusMetres);
    final discovered = await _placesNear(origin, incidentType, radiusMetres);

    // De-duplicate: a registered hospital will usually also appear in Places.
    // Registered wins, since it carries service data.
    final seen = <String>{
      for (final c in registered) _fingerprint(c),
    };
    final merged = [
      ...registered,
      ...discovered.where((c) => !seen.contains(_fingerprint(c))),
    ];

    final ranked = await _rank(merged, origin, incidentType, need, limit);
    return ranked;
  }

  /// Name + rough location, so the same place from two sources collapses.
  static String _fingerprint(CarePoint c) =>
      '${c.name.toLowerCase().trim()}@${c.lat.toStringAsFixed(3)},'
      '${c.lng.toStringAsFixed(3)}';

  static Future<List<CarePoint>> _registeredNear(
      LatLng origin, double radius) async {
    try {
      final snap = await _db
          .collection(_collection)
          .where('acceptingCases', isEqualTo: true)
          .limit(60)
          .get();

      return snap.docs
          .map((d) => CarePoint.fromMap(d.id, d.data()))
          .where((c) =>
              RoutesService.metresBetween(origin, LatLng(c.lat, c.lng)) <=
              radius)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<List<CarePoint>> _placesNear(
      LatLng origin, String incidentType, double radius) async {
    try {
      final res = await http
          .post(
            Uri.parse(_placesEndpoint),
            headers: {
              'Content-Type': 'application/json',
              'X-Goog-Api-Key': _apiKey,
              'X-Goog-FieldMask':
                  'places.id,places.displayName,places.formattedAddress,'
                      'places.location,places.nationalPhoneNumber,places.types',
            },
            body: jsonEncode({
              'includedTypes': _placesTypesFor(incidentType),
              'maxResultCount': 15,
              'locationRestriction': {
                'circle': {
                  'center': {
                    'latitude': origin.latitude,
                    'longitude': origin.longitude,
                  },
                  'radius': radius,
                }
              },
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (res.statusCode != 200) return const [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final places = data['places'] as List? ?? const [];

      return places
          .map((raw) {
            final p = raw as Map<String, dynamic>;
            final types = List<String>.from(p['types'] ?? const []);
            final type = CarePointType.fromPlacesType(types);
            if (type == null) return null;

            final loc = p['location'] as Map<String, dynamic>?;
            if (loc == null) return null;

            return CarePoint(
              id: p['id'] as String? ?? '',
              name: (p['displayName']
                      as Map<String, dynamic>?)?['text'] as String? ??
                  'Unnamed',
              type: type,
              lat: (loc['latitude'] as num).toDouble(),
              lng: (loc['longitude'] as num).toDouble(),
              phone: p['nationalPhoneNumber'] as String?,
              address: p['formattedAddress'] as String?,
              isRegistered: false,
            );
          })
          .whereType<CarePoint>()
          .toList();
    } catch (_) {
      // Places not enabled, or offline — registered points still stand.
      return const [];
    }
  }

  static List<String> _placesTypesFor(String incidentType) {
    switch (incidentType) {
      case 'fire':
        return ['fire_station', 'hospital'];
      case 'security':
        return ['police', 'hospital'];
      default:
        return ['hospital', 'doctor', 'pharmacy'];
    }
  }

  /// Sorts by distance, then asks the AI to reorder on clinical suitability.
  ///
  /// Distance is computed locally and always available; the AI pass is an
  /// enhancement. If it fails, the responder still gets a sane nearest-first
  /// list rather than nothing.
  static Future<List<CarePoint>> _rank(
    List<CarePoint> points,
    LatLng origin,
    String incidentType,
    String? need,
    int limit,
  ) async {
    if (points.isEmpty) return const [];

    final withDistance = points
        .map((c) => c.withRanking(
            distanceMeters:
                RoutesService.metresBetween(origin, LatLng(c.lat, c.lng))))
        .toList()
      ..sort((a, b) => a.distanceMeters!.compareTo(b.distanceMeters!));

    final shortlist = withDistance.take(limit * 2).toList();

    // Only registered points carry service data worth reasoning over.
    final hasServiceData =
        shortlist.any((c) => c.isRegistered && (c.services.isNotEmpty ||
            (c.description ?? '').isNotEmpty));
    if (!hasServiceData || (need ?? '').trim().isEmpty) {
      return shortlist.take(limit).toList();
    }

    try {
      final reasons = await AiService.rankCarePoints(
        need: need!,
        incidentType: incidentType,
        candidates: [
          for (final c in shortlist)
            {
              'id': c.id,
              'name': c.name,
              'type': CarePointType.label(c.type),
              'services': c.services,
              'description': c.description ?? '',
              'distance': c.distanceText,
            }
        ],
      );
      if (reasons.isEmpty) return shortlist.take(limit).toList();

      final byId = {for (final c in shortlist) c.id: c};
      final ordered = <CarePoint>[];
      for (final r in reasons) {
        final c = byId.remove(r['id']);
        if (c != null) {
          ordered.add(c.withRanking(matchReason: r['reason'] as String?));
        }
      }
      // Anything the model omitted still follows, nearest first.
      ordered.addAll(byId.values);
      return ordered.take(limit).toList();
    } catch (_) {
      return shortlist.take(limit).toList();
    }
  }

  /// Adds road travel time to the top results. Done separately because each is
  /// a billed Routes call, so it is only worth it for the handful shown.
  static Future<List<CarePoint>> withTravelTimes(
      List<CarePoint> points, LatLng origin,
      {int howMany = 3}) async {
    final out = <CarePoint>[];
    for (var i = 0; i < points.length; i++) {
      final c = points[i];
      if (i >= howMany) {
        out.add(c);
        continue;
      }
      final route = await RoutesService.compute(
        origin: origin,
        destination: LatLng(c.lat, c.lng),
      );
      out.add(c.withRanking(
        travelTime: route.isEstimate ? null : route.duration,
      ));
    }
    return out;
  }

  // ── Registry management ────────────────────────────────────────────────────

  static Stream<List<CarePoint>> streamAll() {
    return _db.collection(_collection).snapshots().map((s) =>
        s.docs.map((d) => CarePoint.fromMap(d.id, d.data())).toList());
  }

  static Future<void> save(CarePoint point) async {
    final ref = point.id.isEmpty
        ? _db.collection(_collection).doc()
        : _db.collection(_collection).doc(point.id);
    await ref.set(point.toMap(), SetOptions(merge: true));
  }
}
