/// Every meaningful moment in an emergency, in order.
///
/// The incident's `status` only ever tells you where things stand *now*. Once a
/// call is closed it says nothing about how long help took, where the patient
/// was taken, or how many places turned them away. This log is the record that
/// survives — it is what the admin audits and what the patient sees in history.
class IncidentEventType {
  /// Caller pressed SOS.
  static const created = 'created';

  /// A responder took the job.
  static const accepted = 'accepted';

  /// Responder started travelling to the patient.
  static const enRoute = 'en_route';

  /// Responder reached the patient.
  static const arrived = 'arrived';

  /// A care point was chosen for this patient.
  static const referred = 'referred';

  /// Responder left the scene heading for a care point.
  static const departedFor = 'departed_for';

  /// Responder reached that care point with the patient.
  static const arrivedAt = 'arrived_at';

  /// The care point could not take the patient — the journey continues.
  static const declined = 'declined';

  /// Care delivered; the emergency is over.
  static const resolved = 'resolved';

  static const cancelled = 'cancelled';

  static String label(String? type) {
    switch (type) {
      case created:
        return 'SOS raised';
      case accepted:
        return 'Responder accepted';
      case enRoute:
        return 'On the way';
      case arrived:
        return 'Reached patient';
      case referred:
        return 'Referred';
      case departedFor:
        return 'Left for care point';
      case arrivedAt:
        return 'Arrived at care point';
      case declined:
        return 'Turned away';
      case resolved:
        return 'Resolved';
      case cancelled:
        return 'Cancelled';
      default:
        return type ?? 'Update';
    }
  }
}

/// One entry in an incident's journey.
class IncidentEvent {
  final String type;
  final DateTime at;

  /// Who caused it, when that is meaningful.
  final String? actorName;

  /// The care point involved, for referral and transport events.
  final String? carePointName;
  final String? carePointId;

  /// Free text — why a facility declined, what the responder found.
  final String? note;

  const IncidentEvent({
    required this.type,
    required this.at,
    this.actorName,
    this.carePointName,
    this.carePointId,
    this.note,
  });

  /// Incidents written before this log existed stored a bare status. Map those
  /// onto real events so historical journeys still read correctly rather than
  /// showing raw database values to a patient.
  static const _legacyStatusToEvent = {
    'pending': IncidentEventType.created,
    'assigned': IncidentEventType.accepted,
    'en_route': IncidentEventType.enRoute,
    'arrived': IncidentEventType.arrived,
    'resolved': IncidentEventType.resolved,
    'cancelled': IncidentEventType.cancelled,
    'referred': IncidentEventType.referred,
  };

  /// Tolerant of the older `{status, timestamp}` shape already in Firestore,
  /// so historical incidents still render instead of vanishing.
  static IncidentEvent? tryParse(Map<String, dynamic> map) {
    final rawTime = map['timestamp'] ?? map['at'];
    final at = rawTime is String ? DateTime.tryParse(rawTime) : null;
    if (at == null) return null;

    final raw = (map['event'] ?? map['status'] ?? 'update').toString();

    return IncidentEvent(
      type: _legacyStatusToEvent[raw] ?? raw,
      at: at,
      actorName: map['actorName'] as String?,
      carePointName: (map['carePoint'] ?? map['carePointName']) as String?,
      carePointId: map['carePointId'] as String?,
      note: map['note'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'event': type,
        'timestamp': at.toIso8601String(),
        if (actorName != null) 'actorName': actorName,
        if (carePointName != null) 'carePointName': carePointName,
        if (carePointId != null) 'carePointId': carePointId,
        if (note != null) 'note': note,
      };

  String get label {
    final base = IncidentEventType.label(type);
    if (carePointName == null) return base;
    switch (type) {
      case IncidentEventType.departedFor:
        return 'Left for $carePointName';
      case IncidentEventType.arrivedAt:
        return 'Arrived at $carePointName';
      case IncidentEventType.declined:
        return '$carePointName could not help';
      case IncidentEventType.referred:
        return 'Referred to $carePointName';
      default:
        return base;
    }
  }
}

/// Durations derived from a journey — the numbers an admin actually wants.
class IncidentTimings {
  final List<IncidentEvent> events;

  const IncidentTimings(this.events);

  factory IncidentTimings.from(List<Map<String, dynamic>> raw) {
    final parsed = raw
        .map(IncidentEvent.tryParse)
        .whereType<IncidentEvent>()
        .toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    return IncidentTimings(parsed);
  }

  DateTime? _first(String type) {
    for (final e in events) {
      if (e.type == type) return e.at;
    }
    return null;
  }

  DateTime? _last(String type) {
    DateTime? found;
    for (final e in events) {
      if (e.type == type) found = e.at;
    }
    return found;
  }

  DateTime? get raisedAt => _first(IncidentEventType.created);
  DateTime? get acceptedAt => _first(IncidentEventType.accepted);
  DateTime? get arrivedAt => _first(IncidentEventType.arrived);
  DateTime? get closedAt =>
      _last(IncidentEventType.resolved) ?? _last(IncidentEventType.cancelled);

  /// How long the caller waited for anyone to take the job.
  Duration? get timeToAccept => _between(raisedAt, acceptedAt);

  /// How long the responder took to reach the patient once they accepted.
  /// This is the response-time figure that actually matters.
  Duration? get timeToReach => _between(acceptedAt, arrivedAt);

  /// Total from pressing SOS to reaching the patient.
  Duration? get totalResponseTime => _between(raisedAt, arrivedAt);

  /// How long the whole emergency ran.
  Duration? get totalDuration => _between(raisedAt, closedAt);

  /// Time spent with the patient before transporting them.
  Duration? get timeOnScene =>
      _between(arrivedAt, _first(IncidentEventType.departedFor));

  /// Each transport leg: left for X at T1, reached X at T2.
  List<({String carePoint, DateTime departed, DateTime? arrived})>
      get transportLegs {
    final legs = <({String carePoint, DateTime departed, DateTime? arrived})>[];
    for (var i = 0; i < events.length; i++) {
      final e = events[i];
      if (e.type != IncidentEventType.departedFor) continue;

      DateTime? reached;
      for (var j = i + 1; j < events.length; j++) {
        final later = events[j];
        if (later.type == IncidentEventType.arrivedAt &&
            (later.carePointId == e.carePointId ||
                later.carePointName == e.carePointName)) {
          reached = later.at;
          break;
        }
      }
      legs.add((
        carePoint: e.carePointName ?? 'Care point',
        departed: e.at,
        arrived: reached,
      ));
    }
    return legs;
  }

  /// How many facilities turned the patient away.
  int get declinedCount =>
      events.where((e) => e.type == IncidentEventType.declined).length;

  static Duration? _between(DateTime? a, DateTime? b) {
    if (a == null || b == null) return null;
    final d = b.difference(a);
    return d.isNegative ? null : d;
  }

  /// "4 min", "1h 12m", "48 sec"
  static String format(Duration? d) {
    if (d == null) return '—';
    if (d.inMinutes < 1) return '${d.inSeconds} sec';
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    return '${d.inHours}h ${(d.inMinutes % 60).toString().padLeft(2, '0')}m';
  }
}
