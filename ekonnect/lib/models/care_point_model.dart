import 'package:cloud_firestore/cloud_firestore.dart';

/// Kinds of place that can help during an incident.
class CarePointType {
  static const hospital = 'hospital';
  static const clinic = 'clinic';
  static const pharmacy = 'pharmacy';
  static const fireStation = 'fire_station';
  static const police = 'police';
  static const rescue = 'rescue';

  /// Places a patient is physically taken to. A fire station or police post
  /// dispatches *to* the scene instead, so referring someone there means
  /// requesting their attendance, not transporting the patient.
  static bool isVisitable(String type) =>
      type == hospital || type == clinic || type == pharmacy;

  static String label(String type) {
    switch (type) {
      case hospital:
        return 'Hospital';
      case clinic:
        return 'Clinic';
      case pharmacy:
        return 'Pharmacy';
      case fireStation:
        return 'Fire station';
      case police:
        return 'Police post';
      case rescue:
        return 'Rescue service';
      default:
        return 'Care point';
    }
  }

  /// Maps a Google Places type onto ours. Returns null for places we would
  /// never refer an emergency to.
  static String? fromPlacesType(List<String> types) {
    if (types.contains('hospital')) return hospital;
    if (types.contains('doctor') || types.contains('medical_clinic')) {
      return clinic;
    }
    if (types.contains('pharmacy') || types.contains('drugstore')) {
      return pharmacy;
    }
    if (types.contains('fire_station')) return fireStation;
    if (types.contains('police')) return police;
    return null;
  }
}

/// A place that can take over or assist with an emergency — a hospital, clinic,
/// fire station, police post.
///
/// Comes from one of two sources, and the distinction matters: a registered
/// Care Point has service data its operator vouched for, while one discovered
/// through Google Places has only a name, a category and a phone number. The UI
/// must never present the second as if it were the first.
class CarePoint {
  final String id;
  final String name;
  final String type;
  final double lat;
  final double lng;

  final String? phone;
  final String? address;

  /// Free text the operator wrote at sign-up, used for AI matching.
  final String? description;

  /// Specific services offered, e.g. "Trauma surgery", "Maternity", "ICU".
  final List<String> services;

  /// True when this came from eKonnect's own registry rather than Google.
  final bool isRegistered;

  /// True while the operator says they can accept new cases.
  final bool acceptingCases;

  final bool open24Hours;

  // ── Populated at query time, not stored ──────────────────────────────────
  /// Straight-line distance from the incident, in metres.
  final double? distanceMeters;

  /// Road travel time, when a route could be computed.
  final Duration? travelTime;

  /// Why the AI put this forward, shown to the responder so they can judge it.
  final String? matchReason;

  const CarePoint({
    required this.id,
    required this.name,
    required this.type,
    required this.lat,
    required this.lng,
    this.phone,
    this.address,
    this.description,
    this.services = const [],
    this.isRegistered = false,
    this.acceptingCases = true,
    this.open24Hours = false,
    this.distanceMeters,
    this.travelTime,
    this.matchReason,
  });

  bool get isVisitable => CarePointType.isVisitable(type);

  String get distanceText {
    final m = distanceMeters;
    if (m == null) return '';
    if (m < 1000) return '${m.round()} m';
    return '${(m / 1000).toStringAsFixed(m >= 10000 ? 0 : 1)} km';
  }

  String get travelTimeText {
    final t = travelTime;
    if (t == null) return '';
    final mins = t.inMinutes;
    if (mins < 1) return '< 1 min';
    if (mins < 60) return '$mins min';
    return '${mins ~/ 60}h ${(mins % 60).toString().padLeft(2, '0')}m';
  }

  factory CarePoint.fromMap(String id, Map<String, dynamic> map) {
    return CarePoint(
      id: id,
      name: map['name'] ?? '',
      type: map['type'] ?? CarePointType.hospital,
      lat: (map['lat'] as num?)?.toDouble() ?? 0,
      lng: (map['lng'] as num?)?.toDouble() ?? 0,
      phone: map['phone'],
      address: map['address'],
      description: map['description'],
      services: List<String>.from(map['services'] ?? const []),
      isRegistered: true,
      acceptingCases: map['acceptingCases'] ?? true,
      open24Hours: map['open24Hours'] ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'type': type,
        'lat': lat,
        'lng': lng,
        'phone': phone,
        'address': address,
        'description': description,
        'services': services,
        'acceptingCases': acceptingCases,
        'open24Hours': open24Hours,
        'updatedAt': Timestamp.now(),
      };

  CarePoint withRanking({
    double? distanceMeters,
    Duration? travelTime,
    String? matchReason,
  }) =>
      CarePoint(
        id: id,
        name: name,
        type: type,
        lat: lat,
        lng: lng,
        phone: phone,
        address: address,
        description: description,
        services: services,
        isRegistered: isRegistered,
        acceptingCases: acceptingCases,
        open24Hours: open24Hours,
        distanceMeters: distanceMeters ?? this.distanceMeters,
        travelTime: travelTime ?? this.travelTime,
        matchReason: matchReason ?? this.matchReason,
      );

  /// Recorded on the incident's referral chain.
  Map<String, dynamic> toReferralEntry() => {
        'carePointId': id,
        'name': name,
        'type': type,
        'phone': phone,
        'lat': lat,
        'lng': lng,
        'isRegistered': isRegistered,
        'distanceMeters': distanceMeters,
        'referredAt': DateTime.now().toIso8601String(),
      };
}
