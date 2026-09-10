import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants.dart';

class IncidentModel {
  final String id;
  final String type;
  final String status;
  final String userId;
  final String userName;
  final String userPhone;
  final double userLat;
  final double userLng;
  final String? assignedTo;
  final String? assignedToName;
  final String? assignedToPhone;
  final String? assignedToRole;
  final String? assignedToSpecialization;
  final String? assignedToLicenseNumber;
  final String? assignedToVehicleNumber;
  /// The facility the responder answers for — "Oasis Hospital". Denormalised
  /// at accept time from the responder's profile so the patient sees who is
  /// coming *and* who they answer to, without a second lookup.
  final String? assignedToFacilityName;
  final String? assignedTeamId;
  final List<String> notifiedTeamIds;
  final List<Map<String, dynamic>> timeline;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final String? notes;

  /// Live position of the assigned responder, written every few seconds while
  /// they are on the job.
  ///
  /// Carried on the incident rather than only in Realtime Database so the
  /// patient's existing incident stream delivers it — no second listener, and
  /// no dependency on an RTDB instance existing.
  final double? responderLat;
  final double? responderLng;
  final double? responderHeading;
  final DateTime? responderLocationAt;

  /// Every care point this emergency has been sent to, oldest first.
  ///
  /// A chain rather than a single field because a responder may arrive, find
  /// the facility cannot help, and refer onward — all within the same
  /// emergency. Losing the earlier legs would erase the clinical history of
  /// where the patient has already been.
  final List<Map<String, dynamic>> referrals;

  /// Who this call is offered to: `ResponderVisibility.public` opens it to the
  /// public network, `.private` restricts it to [routedTeamId].
  ///
  /// Decided once at creation from the caller's subscriptions, so the routing
  /// cannot drift if their subscription changes mid-incident.
  final String routingScope;

  /// The private provider this call belongs to, when [routingScope] is private.
  final String? routedTeamId;

  /// Responders who handed this call on. They are never offered it again —
  /// a crew that could not help would otherwise keep receiving it.
  final List<String> declinedBy;

  /// Why a crew attended but could not finish. Required when an incident is
  /// closed unresolved, and shown to the patient and the console.
  final String? closedReason;

  /// A crew already on scene has asked for a second crew. The job stays theirs;
  /// this only opens it to others as backup.
  final bool backupRequested;
  final String? backupReason;

  /// Everyone answering this call, primary first.
  final List<Map<String, dynamic>> assignees;
  final String? routedTeamName;

  /// 'user' or 'responder' — who ended the incident. Null unless cancelled.
  final String? cancelledBy;

  /// A `CancelReasons` code, plus free text when the reason was "other".
  final String? cancelReason;
  final String? cancelNote;

  const IncidentModel({
    required this.id,
    required this.type,
    required this.status,
    required this.userId,
    required this.userName,
    required this.userPhone,
    required this.userLat,
    required this.userLng,
    this.assignedTo,
    this.assignedToName,
    this.assignedToPhone,
    this.assignedToRole,
    this.assignedToSpecialization,
    this.assignedToLicenseNumber,
    this.assignedToVehicleNumber,
    this.assignedToFacilityName,
    this.assignedTeamId,
    this.notifiedTeamIds = const [],
    this.timeline = const [],
    required this.createdAt,
    this.resolvedAt,
    this.notes,
    this.referrals = const [],
    this.routingScope = ResponderVisibility.public,
    this.routedTeamId,
    this.declinedBy = const [],
    this.closedReason,
    this.backupRequested = false,
    this.backupReason,
    this.assignees = const [],
    this.routedTeamName,
    this.responderLat,
    this.responderLng,
    this.responderHeading,
    this.responderLocationAt,
    this.cancelledBy,
    this.cancelReason,
    this.cancelNote,
  });

  /// True once the responder has published at least one position.
  bool get hasResponderLocation => responderLat != null && responderLng != null;

  factory IncidentModel.fromMap(String id, Map<String, dynamic> map) {
    return IncidentModel(
      id: id,
      type: map['type'] ?? '',
      status: map['status'] ?? 'pending',
      userId: map['userId'] ?? '',
      userName: map['userName'] ?? '',
      userPhone: map['userPhone'] ?? '',
      userLat: (map['userLat'] as num?)?.toDouble() ?? 0.0,
      userLng: (map['userLng'] as num?)?.toDouble() ?? 0.0,
      assignedTo: map['assignedTo'],
      assignedToName: map['assignedToName'],
      assignedToPhone: map['assignedToPhone'],
      assignedToRole: map['assignedToRole'],
      assignedToSpecialization: map['assignedToSpecialization'],
      assignedToLicenseNumber: map['assignedToLicenseNumber'],
      assignedToVehicleNumber: map['assignedToVehicleNumber'],
      assignedToFacilityName: map['assignedToFacilityName'],
      assignedTeamId: map['assignedTeamId'],
      notifiedTeamIds: List<String>.from(map['notifiedTeamIds'] ?? []),
      timeline: List<Map<String, dynamic>>.from(map['timeline'] ?? []),
      createdAt: map['createdAt'] != null
          ? (map['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      resolvedAt: map['resolvedAt'] != null
          ? (map['resolvedAt'] as Timestamp).toDate()
          : null,
      notes: map['notes'],
      referrals: List<Map<String, dynamic>>.from(map['referrals'] ?? const []),
      // Incidents created before private routing existed are public calls.
      routingScope: map['routingScope'] ?? ResponderVisibility.public,
      routedTeamId: map['routedTeamId'],
      declinedBy: List<String>.from(map['declinedBy'] ?? const []),
      closedReason: map['closedReason'],
      backupRequested: map['backupRequested'] ?? false,
      backupReason: map['backupReason'],
      assignees: List<Map<String, dynamic>>.from(
          (map['assignees'] ?? const []).map((e) => Map<String, dynamic>.from(e))),
      routedTeamName: map['routedTeamName'],
      responderLat: (map['responderLat'] as num?)?.toDouble(),
      responderLng: (map['responderLng'] as num?)?.toDouble(),
      responderHeading: (map['responderHeading'] as num?)?.toDouble(),
      responderLocationAt: map['responderLocationAt'] != null
          ? (map['responderLocationAt'] as Timestamp).toDate()
          : null,
      cancelledBy: map['cancelledBy'],
      cancelReason: map['cancelReason'],
      cancelNote: map['cancelNote'],
    );
  }

  Map<String, dynamic> toMap() => {
        'type': type,
        'status': status,
        'userId': userId,
        'userName': userName,
        'userPhone': userPhone,
        'userLat': userLat,
        'userLng': userLng,
        'assignedTo': assignedTo,
        'assignedToName': assignedToName,
        'assignedToPhone': assignedToPhone,
        'assignedToRole': assignedToRole,
        'assignedToSpecialization': assignedToSpecialization,
        'assignedToLicenseNumber': assignedToLicenseNumber,
        'assignedToVehicleNumber': assignedToVehicleNumber,
        'assignedToFacilityName': assignedToFacilityName,
        'assignedTeamId': assignedTeamId,
        'notifiedTeamIds': notifiedTeamIds,
        'timeline': timeline,
        'createdAt': Timestamp.fromDate(createdAt),
        'resolvedAt': resolvedAt != null ? Timestamp.fromDate(resolvedAt!) : null,
        'notes': notes,
        'referrals': referrals,
        'routingScope': routingScope,
        'routedTeamId': routedTeamId,
        'declinedBy': declinedBy,
        'closedReason': closedReason,
        'backupRequested': backupRequested,
        'backupReason': backupReason,
        'assignees': assignees,
        'routedTeamName': routedTeamName,
        'cancelledBy': cancelledBy,
        'cancelReason': cancelReason,
        'cancelNote': cancelNote,
      };

  IncidentModel copyWith({
    String? status,
    String? assignedTo,
    String? assignedToName,
    String? assignedToPhone,
    String? assignedToRole,
    String? assignedToSpecialization,
    String? assignedToLicenseNumber,
    String? assignedToVehicleNumber,
    String? assignedToFacilityName,
    String? assignedTeamId,
    List<Map<String, dynamic>>? timeline,
    DateTime? resolvedAt,
    String? notes,
  }) =>
      IncidentModel(
        id: id,
        type: type,
        status: status ?? this.status,
        userId: userId,
        userName: userName,
        userPhone: userPhone,
        userLat: userLat,
        userLng: userLng,
        assignedTo: assignedTo ?? this.assignedTo,
        assignedToName: assignedToName ?? this.assignedToName,
        assignedToPhone: assignedToPhone ?? this.assignedToPhone,
        assignedToRole: assignedToRole ?? this.assignedToRole,
        assignedToSpecialization: assignedToSpecialization ?? this.assignedToSpecialization,
        assignedToLicenseNumber: assignedToLicenseNumber ?? this.assignedToLicenseNumber,
        assignedToVehicleNumber: assignedToVehicleNumber ?? this.assignedToVehicleNumber,
        assignedToFacilityName: assignedToFacilityName ?? this.assignedToFacilityName,
        assignedTeamId: assignedTeamId ?? this.assignedTeamId,
        notifiedTeamIds: notifiedTeamIds,
        timeline: timeline ?? this.timeline,
        createdAt: createdAt,
        resolvedAt: resolvedAt ?? this.resolvedAt,
        notes: notes ?? this.notes,
        referrals: referrals,
        // Routing is fixed at creation and must never be recomputed later.
        routingScope: routingScope,
        routedTeamId: routedTeamId,
        routedTeamName: routedTeamName,
        // Written server-side, so preserve verbatim rather than overwriting.
        responderLat: responderLat,
        responderLng: responderLng,
        responderHeading: responderHeading,
        responderLocationAt: responderLocationAt,
        cancelledBy: cancelledBy,
        cancelReason: cancelReason,
        cancelNote: cancelNote,
      );

  bool get isPending => status == 'pending';
  bool get isActive =>
      status == 'assigned' || status == 'en_route' || status == 'arrived';
  /// Delegates to [IncidentStatus.closed] rather than listing statuses here.
  /// This used to test resolved/cancelled only, so a job closed as
  /// 'not resolved' counted as still live: its card stayed on the home
  /// screen and, because an open emergency hides the SOS selector, the
  /// caller could not raise a new one.
  bool get isClosed => IncidentStatus.isClosed(status);
}
