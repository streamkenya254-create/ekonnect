import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

  /// Private providers whose cover is live right now.
  ///
  /// Registration alone is not cover: the facility confirms payment and writes
  /// `expiresAt`, and only then does that provider own this person's calls.
  /// Routing an unconfirmed or lapsed registration privately would take the
  /// caller off the public network in exchange for nothing — the worst
  /// possible outcome of a billing gap.
  ///
  /// Filtered in memory rather than in the query: pairing an inequality on
  /// `expiresAt` with the equality filters needs a composite index, and a
  /// missing index here would fail an emergency lookup.
  static Future<List<Map<String, dynamic>>> getActiveSubscriptions(
      String userId) async {
    final snap = await _db
        .collection(Collections.subscriptions)
        .where('userId', isEqualTo: userId)
        .where('status', isEqualTo: SubscriptionStatus.active)
        .get();
    final now = DateTime.now();
    return snap.docs
        .map((d) => {'id': d.id, ...d.data()})
        .where((s) {
          final raw = s['expiresAt'];
          final until = raw is Timestamp ? raw.toDate() : null;
          return until != null && until.isAfter(now);
        })
        .toList();
  }

  static Stream<List<Map<String, dynamic>>> streamSubscriptions(String userId) {
    return _db
        .collection(Collections.subscriptions)
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  /// Registers a client with a private provider.
  ///
  /// Deliberately writes no expiry: cover starts when the facility confirms
  /// payment in its portal, not when someone taps Register. The name and
  /// phone travel with the record because the facility's subscriber list
  /// cannot read the users collection to look them up.
  static Future<void> subscribeToTeam({
    required String userId,
    required TeamModel team,
    String? userName,
    String? userPhone,
  }) async {
    await _db.collection(Collections.subscriptions).add({
      'userId': userId,
      'userName': userName ?? '',
      'userPhone': userPhone ?? '',
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

  /// Thrown when a call has already been taken, or is no longer open.
  ///
  /// Carries a human sentence rather than a code because it is shown straight
  /// to a responder who just tapped Accept and needs to know why nothing
  /// happened.
  static const acceptRaceMessage = 'Another crew took this call first.';
  static const acceptClosedMessage = 'This call is no longer open.';

  /// Takes a call, if it is still there to take.
  ///
  /// A transaction, not a batch. The previous version wrote blind, so two
  /// crews tapping Accept within the same second both "won", and — worse — a
  /// stale screen could accept an incident that had already been cancelled,
  /// flipping it back to assigned. That is how one incident in testing
  /// collected three separate "Responder accepted" entries across two days and
  /// how a cancelled SOS came back to life.
  ///
  /// Returns normally on success; throws [StateError] with a readable message
  /// when the call was already taken or closed.
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
    String? responderFacility,
  }) async {
    final incidentRef = _db.collection(Collections.incidents).doc(incidentId);
    final responderRef = _db.collection(Collections.users).doc(responderId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(incidentRef);
      if (!snap.exists) throw StateError(acceptClosedMessage);

      final data = snap.data()!;
      final status = data['status'] as String?;
      final assignedTo = data['assignedTo'] as String?;

      // Re-accepting your own call is a no-op rather than an error: it happens
      // when a screen is re-entered and should not look like a failure.
      if (assignedTo == responderId) return;

      if (status != IncidentStatus.pending || assignedTo != null) {
        throw StateError(
          status == IncidentStatus.cancelled ||
                  status == IncidentStatus.resolved ||
                  status == IncidentStatus.closedUnresolved
              ? acceptClosedMessage
              : acceptRaceMessage,
        );
      }

      tx.update(incidentRef, {
        'status': IncidentStatus.assigned,
        'assignedTo': responderId,
        'assignedToName': responderName,
        'assignedToPhone': responderPhone,
        'assignedToRole': ?responderRole,
        'assignedToSpecialization': ?responderSpecialization,
        'assignedToLicenseNumber': ?responderLicenseNumber,
        'assignedToVehicleNumber': ?responderVehicleNumber,
        'assignedToFacilityName': ?responderFacility,
        'assignedTeamId': teamId,
        // The crew answering this call, primary first. Backup responders are
        // appended here when one is requested.
        'assignees': [
          {
            'uid': responderId,
            'name': responderName,
            'role': responderRole,
            'facility': responderFacility,
            'vehicle': responderVehicleNumber,
            'primary': true,
            'joinedAt': DateTime.now().toIso8601String(),
          }
        ],
        'timeline': FieldValue.arrayUnion([
          {'status': 'assigned', 'timestamp': DateTime.now().toIso8601String()}
        ]),
      });
      tx.update(responderRef, {
        'currentIncidentId': incidentId,
        'isAvailable': false,
      });
    });
  }

  /// How long a private provider gets its subscriber's call to itself.
  ///
  /// Exclusivity is what a client pays for, but it cannot be unlimited: a
  /// subscriber whose private ambulance is 80km away, or whose crew is all off
  /// duty, would otherwise wait for a crew that is never coming while public
  /// responders two streets away never hear about it.
  static const privateExclusivity = Duration(seconds: 90);

  /// Opens a private call to the public network after the exclusivity window.
  ///
  /// A transaction, so it cannot reopen a call that has meanwhile been
  /// accepted, cancelled or resolved — this fires from a timer on the
  /// patient's phone and may well arrive late.
  static Future<bool> openPrivateCallToPublic(String incidentId) async {
    final ref = _db.collection(Collections.incidents).doc(incidentId);
    return _db.runTransaction<bool>((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return false;
      final d = snap.data()!;
      if (d['status'] != IncidentStatus.pending) return false;
      if (d['assignedTo'] != null) return false;
      if (d['routingScope'] != ResponderVisibility.private) return false;

      tx.update(ref, {
        'routingScope': ResponderVisibility.public,
        // Kept, so the record still shows who had first refusal and the
        // provider can be held to it.
        'privateWindowExpired': true,
        'timeline': FieldValue.arrayUnion([
          {
            'status': 'opened_to_public',
            'reason': 'No response from ${d['routedTeamName'] ?? 'the private provider'} '
                'within ${privateExclusivity.inSeconds}s',
            'timestamp': DateTime.now().toIso8601String(),
          }
        ]),
      });
      return true;
    });
  }

  /// Closes a job the crew attended but could not finish.
  ///
  /// Distinct from cancelling. The reason is required because this is the
  /// record of a failure the network needs to see — "no ambulance available",
  /// "patient refused care" and "wrong address" call for three different fixes
  /// and would be indistinguishable filed as one.
  static Future<void> closeUnresolved({
    required String incidentId,
    required String responderId,
    required String reason,
  }) async {
    final batch = _db.batch();
    batch.update(_db.collection(Collections.incidents).doc(incidentId), {
      'status': IncidentStatus.closedUnresolved,
      'closedReason': reason,
      'closedBy': responderId,
      'resolvedAt': FieldValue.serverTimestamp(),
      'timeline': FieldValue.arrayUnion([
        {
          'status': IncidentStatus.closedUnresolved,
          'reason': reason,
          'timestamp': DateTime.now().toIso8601String(),
        }
      ]),
    });
    batch.update(_db.collection(Collections.users).doc(responderId), {
      'currentIncidentId': null,
      'isAvailable': true,
    });
    await batch.commit();
  }

  /// Puts the call back on the network for another crew, keeping the history.
  ///
  /// The incident is not recreated — one emergency stays one record, or the
  /// patient's timeline would fragment into unrelated jobs and every response
  /// time would be measured from the wrong moment.
  static Future<void> rebroadcast({
    required String incidentId,
    required String responderId,
    required String reason,
  }) async {
    final batch = _db.batch();
    batch.update(_db.collection(Collections.incidents).doc(incidentId), {
      'status': IncidentStatus.pending,
      'assignedTo': null,
      'assignedToName': null,
      'assignedToPhone': null,
      'assignedTeamId': null,
      'assignees': [],
      // Whoever hands it on cannot be offered it again, or a crew that cannot
      // help will keep receiving the same call.
      'declinedBy': FieldValue.arrayUnion([responderId]),
      'timeline': FieldValue.arrayUnion([
        {
          'status': 'rebroadcast',
          'reason': reason,
          'timestamp': DateTime.now().toIso8601String(),
        }
      ]),
    });
    batch.update(_db.collection(Collections.users).doc(responderId), {
      'currentIncidentId': null,
      'isAvailable': true,
    });
    await batch.commit();
  }

  /// Asks for a second crew on this job without giving it up.
  ///
  /// The incident stays assigned to the primary — the patient keeps seeing the
  /// crew already with them — and a flag opens it to others as backup.
  static Future<void> requestBackup({
    required String incidentId,
    required String reason,
  }) async {
    await _db.collection(Collections.incidents).doc(incidentId).update({
      'backupRequested': true,
      'backupReason': reason,
      'timeline': FieldValue.arrayUnion([
        {
          'status': 'backup_requested',
          'reason': reason,
          'timestamp': DateTime.now().toIso8601String(),
        }
      ]),
    });
  }

  /// Calls off a referral that is no longer needed.
  ///
  /// A crew halfway to a hospital whose patient has recovered, or who has been
  /// turned away, must be able to say so. Without this the journey record
  /// would show a transport leg that never ended, and the receiving facility
  /// would keep expecting someone.
  static Future<void> cancelReferral({
    required String incidentId,
    required String carePointName,
    required String reason,
  }) async {
    await _db.collection(Collections.incidents).doc(incidentId).update({
      'timeline': FieldValue.arrayUnion([
        {
          'status': 'referral_cancelled',
          'carePointName': carePointName,
          'reason': reason,
          'timestamp': DateTime.now().toIso8601String(),
        }
      ]),
    });
  }

  /// Stands down a backup request — the crew has managed after all.
  static Future<void> cancelBackupRequest(String incidentId) async {
    await _db.collection(Collections.incidents).doc(incidentId).update({
      'backupRequested': false,
      'backupReason': null,
      'timeline': FieldValue.arrayUnion([
        {
          'status': 'backup_stood_down',
          'timestamp': DateTime.now().toIso8601String(),
        }
      ]),
    });
  }

  /// A second crew joins a job that already has a primary.
  static Future<void> joinAsBackup({
    required String incidentId,
    required String responderId,
    required String responderName,
    String? responderRole,
    String? responderFacility,
    String? responderVehicle,
  }) async {
    final batch = _db.batch();
    batch.update(_db.collection(Collections.incidents).doc(incidentId), {
      'assignees': FieldValue.arrayUnion([
        {
          'uid': responderId,
          'name': responderName,
          'role': responderRole,
          'facility': responderFacility,
          'vehicle': responderVehicle,
          'primary': false,
          'joinedAt': DateTime.now().toIso8601String(),
        }
      ]),
      'backupRequested': false,
      'timeline': FieldValue.arrayUnion([
        {
          'status': 'backup_joined',
          'by': responderName,
          'timestamp': DateTime.now().toIso8601String(),
        }
      ]),
    });
    batch.update(_db.collection(Collections.users).doc(responderId), {
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
    // Only ever writes the *caller's* own user document.
    //
    // This used to clear both parties in one batch. The rules let a signed-in
    // person update only their own user doc, so the write for the other side
    // failed — and because it was one batch, the incident itself was never
    // closed either. Closing a job died with PERMISSION_DENIED and looked, on
    // screen, like nothing had happened at all.
    //
    // The other side clears itself: IncidentProvider watches the incident and
    // releases its own hold the moment it sees it closed.
    final me = FirebaseAuth.instance.currentUser?.uid;
    final batch = _db.batch();
    batch.update(_db.collection(Collections.incidents).doc(incidentId), {
      'status': status,
      'resolvedAt': Timestamp.now(),
      'timeline': FieldValue.arrayUnion([
        {'status': status, 'timestamp': DateTime.now().toIso8601String()}
      ]),
    });
    if (me != null && me == responderId) {
      // Free the responder so they show available again.
      batch.update(_db.collection(Collections.users).doc(responderId), {
        'currentIncidentId': null,
        'isAvailable': true,
      });
    }
    if (me != null && me == userId) {
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

  // Cancels the incident and releases whichever side is doing the cancelling.
  // The other side lets itself go when it sees the incident close — see
  // closeIncidentForResponder for why this cannot clear both.
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
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me != null && me == userId) {
      batch.update(_db.collection(Collections.users).doc(userId), {
        'currentIncidentId': null,
      });
    }
    if (me != null && responderId != null && me == responderId) {
      batch.update(_db.collection(Collections.users).doc(responderId), {
        'currentIncidentId': null,
        'isAvailable': true,
      });
    }
    await batch.commit();
  }

  // ── Notifications ──────────────────────────────────────────────────────────

  /// A kept copy of every push sent to this person.
  ///
  /// A push is a one-shot: swipe it away, or miss the banner, and it is gone.
  /// The Cloud Function writes one of these alongside each send so there is
  /// somewhere to find it again.
  static Stream<List<Map<String, dynamic>>> streamNotifications(String uid) {
    return _db
        .collection(Collections.notifications)
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  static Future<void> markNotificationRead(String id) async {
    await _db
        .collection(Collections.notifications)
        .doc(id)
        .update({'read': true});
  }

  /// One batch rather than fifty writes, and only the unread ones.
  static Future<void> markAllNotificationsRead(String uid) async {
    final snap = await _db
        .collection(Collections.notifications)
        .where('userId', isEqualTo: uid)
        .where('read', isEqualTo: false)
        .get();
    if (snap.docs.isEmpty) return;
    final batch = _db.batch();
    for (final d in snap.docs) {
      batch.update(d.reference, {'read': true});
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
