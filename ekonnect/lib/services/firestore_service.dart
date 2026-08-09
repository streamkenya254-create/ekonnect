import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../models/incident_event.dart';
import '../models/incident_model.dart';
import '../models/message_model.dart';
import '../models/team_model.dart';
import '../models/user_model.dart';
import '../core/constants.dart';

class FirestoreService {
  static final _db = FirebaseFirestore.instance;

  // ── Users ──────────────────────────────────────────────────────────────────

  static Future<void> createUser(UserModel user) async {
    await _db.collection(Collections.users).doc(user.uid).set(user.toMap());
  }

  static Future<UserModel?> getUser(String uid) async {
    final doc = await _db.collection(Collections.users).doc(uid).get();
    if (!doc.exists) return null;
    return UserModel.fromMap(doc.id, doc.data()!);
  }

  static Stream<UserModel?> streamUser(String uid) {
    return _db.collection(Collections.users).doc(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      return UserModel.fromMap(doc.id, doc.data()!);
    });
  }

  static Future<void> updateUser(String uid, Map<String, dynamic> data) async {
    await _db.collection(Collections.users).doc(uid).update(data);
  }

  static Future<void> setOnlineStatus(String uid,
      {required bool isOnline, bool? isAvailable}) async {
    final data = <String, dynamic>{'isOnline': isOnline};
    if (isAvailable != null) data['isAvailable'] = isAvailable;
    await _db.collection(Collections.users).doc(uid).update(data);
  }

  /// On-duty (available) responders that have a known location — powers the
  /// user's "responders near you" map. Single `where` avoids a composite
  /// index; role + location filtering is done client-side.
  static Stream<List<UserModel>> streamAvailableResponders() {
    return _db
        .collection(Collections.users)
        .where('isAvailable', isEqualTo: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => UserModel.fromMap(d.id, d.data()))
            .where((u) =>
                AppRoles.isResponder(u.role) &&
                u.lat != null &&
                u.lng != null)
            .toList());
  }

  // ── Incidents ──────────────────────────────────────────────────────────────

  static Future<String> createIncident(IncidentModel incident) async {
    final ref = _db.collection(Collections.incidents).doc();

    // Routing is decided once, here, from the caller's subscriptions. Never
    // recompute it later: a subscription lapsing mid-emergency must not silently
    // hand the call to a different provider.
    TeamModel? privateTeam;
    try {
      privateTeam = await resolveRoutingTeam(
        userId: incident.userId,
        incidentType: incident.type,
      );
    } catch (_) {
      // Routing lookup must never block an emergency — fall back to public.
    }

    final withId = IncidentModel(
      id: ref.id,
      type: incident.type,
      status: incident.status,
      userId: incident.userId,
      userName: incident.userName,
      userPhone: incident.userPhone,
      userLat: incident.userLat,
      userLng: incident.userLng,
      createdAt: incident.createdAt,
      notes: incident.notes,
      routingScope: privateTeam != null
          ? ResponderVisibility.private
          : ResponderVisibility.public,
      routedTeamId: privateTeam?.id,
      routedTeamName: privateTeam?.name,
      timeline: [
        {'status': 'pending', 'timestamp': DateTime.now().toIso8601String()}
      ],
    );
    await ref.set(withId.toMap());
    return ref.id;
  }

  static Stream<IncidentModel?> streamIncident(String id) {
    return _db.collection(Collections.incidents).doc(id).snapshots().map((doc) {
      if (!doc.exists) return null;
      return IncidentModel.fromMap(doc.id, doc.data()!);
    });
  }

  static Stream<List<IncidentModel>> streamPendingIncidents(String incidentType) {
    return _db
        .collection(Collections.incidents)
        .where('type', isEqualTo: incidentType)
        .where('status', isEqualTo: IncidentStatus.pending)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => IncidentModel.fromMap(d.id, d.data()))
            .toList());
  }

  // ── Subscriptions ──────────────────────────────────────────────────────────

  /// Private providers a user is currently registered with.
  static Future<List<Map<String, dynamic>>> getActiveSubscriptions(
      String userId) async {
    final snap = await _db
        .collection(Collections.subscriptions)
        .where('userId', isEqualTo: userId)
        .where('status', isEqualTo: SubscriptionStatus.active)
        .get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  static Stream<List<Map<String, dynamic>>> streamSubscriptions(String userId) {
    return _db
        .collection(Collections.subscriptions)
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  static Future<void> subscribeToTeam({
    required String userId,
    required TeamModel team,
  }) async {
    await _db.collection(Collections.subscriptions).add({
      'userId': userId,
      'teamId': team.id,
      'teamName': team.name,
      'status': SubscriptionStatus.active,
      'createdAt': Timestamp.now(),
    });
  }

  static Future<void> cancelSubscription(String subscriptionId) async {
    await _db.collection(Collections.subscriptions).doc(subscriptionId).update({
      'status': SubscriptionStatus.cancelled,
      'cancelledAt': Timestamp.now(),
    });
  }

  /// Decides who an incoming call belongs to.
  ///
  /// If the caller is registered with a private provider that covers this
  /// emergency type, that provider gets it exclusively — the whole point of
  /// subscribing is being served by your own company. Otherwise it goes to the
  /// public network.
  static Future<TeamModel?> resolveRoutingTeam({
    required String userId,
    required String incidentType,
  }) async {
    final subs = await getActiveSubscriptions(userId);
    if (subs.isEmpty) return null;

    for (final sub in subs) {
      final teamId = sub['teamId'] as String?;
      if (teamId == null) continue;
      final doc = await _db.collection(Collections.teams).doc(teamId).get();
      if (!doc.exists) continue;
      final team = TeamModel.fromMap(doc.id, doc.data()!);
      if (team.isPrivate && team.respondsTo.contains(incidentType)) {
        return team;
      }
    }
    return null;
  }

  // Single orderBy — no whereIn — to avoid composite index requirement.
  // Type + status filtering is done client-side in IncidentProvider.
  static Stream<List<IncidentModel>> streamAllPendingIncidents() {
    return _db
        .collection(Collections.incidents)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => IncidentModel.fromMap(d.id, d.data()))
            .toList());
  }

  static Stream<List<IncidentModel>> streamUserIncidents(String userId) {
    return _db
        .collection(Collections.incidents)
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => IncidentModel.fromMap(d.id, d.data()))
            .toList());
  }

  static Stream<List<IncidentModel>> streamResponderIncidents(String responderId) {
    return _db
        .collection(Collections.incidents)
        .where('assignedTo', isEqualTo: responderId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => IncidentModel.fromMap(d.id, d.data()))
            .toList());
  }

  static Future<void> acceptIncident({
    required String incidentId,
    required String responderId,
    required String responderName,
    required String responderPhone,
    required String teamId,
    String? responderRole,
    String? responderSpecialization,
    String? responderLicenseNumber,
    String? responderVehicleNumber,
  }) async {
    final batch = _db.batch();
    final incidentRef = _db.collection(Collections.incidents).doc(incidentId);
    final responderRef = _db.collection(Collections.users).doc(responderId);

    batch.update(incidentRef, {
      'status': IncidentStatus.assigned,
      'assignedTo': responderId,
      'assignedToName': responderName,
      'assignedToPhone': responderPhone,
      'assignedToRole': ?responderRole,
      'assignedToSpecialization': ?responderSpecialization,
      'assignedToLicenseNumber': ?responderLicenseNumber,
      'assignedToVehicleNumber': ?responderVehicleNumber,
      'assignedTeamId': teamId,
      'timeline': FieldValue.arrayUnion([
        {'status': 'assigned', 'timestamp': DateTime.now().toIso8601String()}
      ]),
    });
    batch.update(responderRef, {
      'currentIncidentId': incidentId,
      'isAvailable': false,
    });
    await batch.commit();
  }

  /// Publishes the responder's live position onto the incident.
  ///
  /// Deliberately a plain field update rather than a Realtime Database write:
  /// the patient already streams this document, so the position reaches them
  /// with no extra listener and no RTDB instance required.
  static Future<void> updateResponderLocation({
    required String incidentId,
    required double lat,
    required double lng,
    double? heading,
  }) async {
    await _db.collection(Collections.incidents).doc(incidentId).update({
      'responderLat': lat,
      'responderLng': lng,
      'responderHeading': heading,
      'responderLocationAt': Timestamp.now(),
    });
  }

  /// Appends one event to an incident's journey log.
  ///
  /// Every transition goes through here so the audit trail cannot drift from
  /// what actually happened. `arrayUnion` keeps concurrent writes safe.
  static Future<void> logEvent({
    required String incidentId,
    required String event,
    String? actorName,
    String? carePointId,
    String? carePointName,
    String? note,
  }) async {
    await _db.collection(Collections.incidents).doc(incidentId).update({
      'timeline': FieldValue.arrayUnion([
        IncidentEvent(
          type: event,
          at: DateTime.now(),
          actorName: actorName,
          carePointId: carePointId,
          carePointName: carePointName,
          note: note,
        ).toMap()
      ]),
    });
  }

  /// Records that the responder has left the scene for a care point, and that
  /// they later reached it.
  ///
  /// Split into two events on purpose: the gap between them is the transport
  /// time, which is invisible if you only record arrival.
  static Future<void> logDeparture({
    required String incidentId,
    required String carePointId,
    required String carePointName,
    String? note,
  }) =>
      logEvent(
        incidentId: incidentId,
        event: IncidentEventType.departedFor,
        carePointId: carePointId,
        carePointName: carePointName,
        note: note,
      );

  static Future<void> logArrivalAtCarePoint({
    required String incidentId,
    required String carePointId,
    required String carePointName,
  }) =>
      logEvent(
        incidentId: incidentId,
        event: IncidentEventType.arrivedAt,
        carePointId: carePointId,
        carePointName: carePointName,
      );

  /// The care point could not take the patient. Recorded so the journey shows
  /// *why* the patient was moved on rather than appearing to wander.
  static Future<void> logDeclined({
    required String incidentId,
    required String carePointId,
    required String carePointName,
    required String reason,
  }) =>
      logEvent(
        incidentId: incidentId,
        event: IncidentEventType.declined,
        carePointId: carePointId,
        carePointName: carePointName,
        note: reason,
      );

  /// Appends a care point to the incident's referral chain.
  ///
  /// Uses `arrayUnion` so two responders acting at once cannot clobber each
  /// other's entry, and never overwrites earlier legs — the chain is the record
  /// of everywhere this patient has already been sent.
  static Future<void> addReferral({
    required String incidentId,
    required Map<String, dynamic> referral,
    String? note,
  }) async {
    await _db.collection(Collections.incidents).doc(incidentId).update({
      'referrals': FieldValue.arrayUnion([referral]),
      'timeline': FieldValue.arrayUnion([
        {
          'status': 'referred',
          'timestamp': DateTime.now().toIso8601String(),
          'carePoint': referral['name'],
          'note': ?note,
        }
      ]),
    });
  }

  static Future<void> updateIncidentStatus(
      String incidentId, String status) async {
    final update = <String, dynamic>{
      'status': status,
      'timeline': FieldValue.arrayUnion([
        {'status': status, 'timestamp': DateTime.now().toIso8601String()}
      ]),
    };
    if (status == IncidentStatus.resolved ||
        status == IncidentStatus.cancelled) {
      update['resolvedAt'] = Timestamp.now();
    }
    await _db.collection(Collections.incidents).doc(incidentId).update(update);
  }

  static Future<void> closeIncidentForResponder({
    required String responderId,
    required String incidentId,
    required String status,
    String? userId,
  }) async {
    final batch = _db.batch();
    batch.update(_db.collection(Collections.incidents).doc(incidentId), {
      'status': status,
      'resolvedAt': Timestamp.now(),
      'timeline': FieldValue.arrayUnion([
        {'status': status, 'timestamp': DateTime.now().toIso8601String()}
      ]),
    });
    // Free the responder so they show available again
    batch.update(_db.collection(Collections.users).doc(responderId), {
      'currentIncidentId': null,
      'isAvailable': true,
    });
    // Also clear the patient's active incident so they can raise a new SOS
    if (userId != null) {
      batch.update(_db.collection(Collections.users).doc(userId), {
        'currentIncidentId': null,
      });
    }
    await batch.commit();
  }

  static Future<void> rateIncident({
    required String incidentId,
    required int rating,
    String? note,
  }) async {
    final data = <String, dynamic>{'rating': rating};
    if (note != null && note.isNotEmpty) data['ratingNote'] = note;
    await _db.collection(Collections.incidents).doc(incidentId).update(data);
  }

  // Used when patient cancels — clears both sides in one batch
  static Future<void> cancelIncidentWithCleanup({
    required String incidentId,
    required String userId,
    String? responderId,
    String cancelledBy = 'user',
    String? reason,
    String? note,
  }) async {
    final batch = _db.batch();
    batch.update(_db.collection(Collections.incidents).doc(incidentId), {
      'status': IncidentStatus.cancelled,
      'cancelledBy': cancelledBy,
      'cancelReason': reason,
      // Only set for the free-text "Another reason" option.
      'cancelNote': note,
      'resolvedAt': Timestamp.now(),
      'timeline': FieldValue.arrayUnion([
        {
          'status': IncidentStatus.cancelled,
          'timestamp': DateTime.now().toIso8601String(),
          'reason': ?reason,
        }
      ]),
    });
    batch.update(_db.collection(Collections.users).doc(userId), {
      'currentIncidentId': null,
    });
    if (responderId != null) {
      batch.update(_db.collection(Collections.users).doc(responderId), {
        'currentIncidentId': null,
        'isAvailable': true,
      });
    }
    await batch.commit();
  }

  // ── Chat ───────────────────────────────────────────────────────────────────

  static Stream<List<MessageModel>> streamMessages(String incidentId) {
    return _db
        .collection(Collections.incidents)
        .doc(incidentId)
        .collection(Collections.messages)
        .orderBy('timestamp')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => MessageModel.fromMap(d.id, d.data()))
            .toList());
  }

  static Future<void> sendMessage(String incidentId, MessageModel msg) async {
    final ref = _db
        .collection(Collections.incidents)
        .doc(incidentId)
        .collection(Collections.messages)
        .doc(const Uuid().v4());
    await ref.set(msg.toMap());
  }

  // ── Teams ──────────────────────────────────────────────────────────────────

  static Stream<List<TeamModel>> streamTeams() {
    return _db.collection(Collections.teams).snapshots().map(
        (snap) => snap.docs.map((d) => TeamModel.fromMap(d.id, d.data())).toList());
  }

  static Future<List<TeamModel>> getTeams() async {
    final snap = await _db.collection(Collections.teams).get();
    return snap.docs.map((d) => TeamModel.fromMap(d.id, d.data())).toList();
  }

  static Future<TeamModel?> getTeamForIncidentType(String incidentType) async {
    final snap = await _db
        .collection(Collections.teams)
        .where('respondsTo', arrayContains: incidentType)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return TeamModel.fromMap(snap.docs.first.id, snap.docs.first.data());
  }

  static Future<void> saveTeam(TeamModel team) async {
    await _db.collection(Collections.teams).doc(team.id).set(team.toMap());
  }

  static Future<void> deleteTeam(String teamId) async {
    await _db.collection(Collections.teams).doc(teamId).delete();
  }

  // ── App Config ─────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getAppConfig() async {
    final doc = await _db
        .collection(Collections.appConfig)
        .doc('settings')
        .get();
    return doc.data() ?? {};
  }

  static Future<void> updateAppConfig(Map<String, dynamic> data) async {
    await _db
        .collection(Collections.appConfig)
        .doc('settings')
        .set(data, SetOptions(merge: true));
  }
}
