import 'dart:async';
import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../models/incident_model.dart';
import '../models/user_model.dart';
import '../services/firestore_service.dart';
import '../services/location_service.dart';

class IncidentProvider extends ChangeNotifier {
  UserModel? _currentUser;

  IncidentModel? _activeIncident;
  StreamSubscription? _activeIncidentSub;

  List<IncidentModel> _pendingIncidents = [];

  /// Jobs already under way whose crew has asked for a second pair of hands.
  /// Kept apart from [_pendingIncidents] so a backup request never looks like
  /// an unanswered emergency.
  List<IncidentModel> _backupRequests = [];
  StreamSubscription? _pendingSub;

  bool _isLoading = false;
  String? _error;

  IncidentModel? get activeIncident => _activeIncident;
  List<IncidentModel> get pendingIncidents => _pendingIncidents;
  List<IncidentModel> get backupRequests => _backupRequests;
  bool get isLoading => _isLoading;
  String? get error => _error;

  void updateCurrentUser(UserModel? user) {
    // Skip expensive subscription restarts when only non-routing fields change
    // (e.g. lat/lng location updates that Firestore streams every few seconds).
    final sameRoutingState = _currentUser != null &&
        user != null &&
        _currentUser!.uid == user.uid &&
        _currentUser!.effectiveRole == user.effectiveRole &&
        _currentUser!.isAvailable == user.isAvailable &&
        _currentUser!.currentIncidentId == user.currentIncidentId;

    _currentUser = user;
    if (user == null || sameRoutingState) return;

    // Use effectiveRole so mode switches (responder ↔ user) are respected.
    if (AppRoles.isResponder(user.effectiveRole)) {
      _subscribeToTeamIncidents(user);
    } else {
      // User is in regular (patient) mode — cancel responder streams.
      _pendingSub?.cancel();
      _pendingSub = null;
      if (_pendingIncidents.isNotEmpty) {
        _pendingIncidents = [];
        notifyListeners();
      }
      if (user.currentIncidentId != null) {
        // Regular user returning with an unresolved incident — re-attach to it.
        streamActiveIncident(user.currentIncidentId!);
      }
    }
  }

  // ── User: create SOS ─────────────────────────────────────────────────────────

  /// [notes] carries the AI triage summary and the caller's own words when the
  /// SOS came from a spoken report, so the responder sees context on arrival.
  Future<String?> createSOS(String type, {String? notes}) async {
    // Callers branch on [error] when this returns null, so a stale error from a
    // previous attempt must not leak into this one.
    _error = null;
    if (_currentUser == null) {
      _error = 'User not loaded. Please sign out and back in.';
      notifyListeners();
      return null;
    }
    // Block if a non-closed incident already exists
    if (_activeIncident != null && !_activeIncident!.isClosed) {
      _error = 'ACTIVE_INCIDENT:${_activeIncident!.id}:${_activeIncident!.type}';
      notifyListeners();
      return null;
    }
    _setLoading(true);
    try {
      // Walks precise → coarse → last-known internally, and tells us *which*
      // step failed so the user gets an actionable message instead of a blanket
      // "enable location permissions" even when permissions are already on.
      final fix = await LocationService.resolvePosition();
      if (!fix.isSuccess) {
        _error = 'LOCATION:${fix.message}';
        notifyListeners();
        return null;
      }
      final pos = fix.position!;

      final incident = IncidentModel(
        id: '',
        type: type,
        status: IncidentStatus.pending,
        userId: _currentUser!.uid,
        userName: _currentUser!.name,
        userPhone: _currentUser!.phone,
        userLat: pos.latitude,
        userLng: pos.longitude,
        createdAt: DateTime.now(),
        notes: notes,
      );

      final id = await FirestoreService.createIncident(incident);
      await FirestoreService.updateUser(
          _currentUser!.uid, {'currentIncidentId': id});
      streamActiveIncident(id);
      return id;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    } finally {
      _setLoading(false);
    }
  }

  void streamActiveIncident(String id) {
    _activeIncidentSub?.cancel();
    _activeIncidentSub =
        FirestoreService.streamIncident(id).listen((incident) {
      _activeIncident = incident;

      // Whichever side closed the incident, both must tear their live plumbing
      // down. Doing it here rather than in each screen means it happens even if
      // the other party is backgrounded: otherwise a responder keeps publishing
      // GPS every 4s for a dead job — a phantom marker on the patient's map —
      // and the open subscription keeps spinners on screen after the job ends.
      //
      // [_activeIncident] deliberately keeps the *closed* incident rather than
      // being nulled: the screens watch `isClosed` to know to navigate home,
      // and `hasActive` checks treat a closed incident as no incident, so the
      // dashboards fall back to their normal state on their own.
      if (incident == null || incident.isClosed) {
        // Release our own hold. The party that closed the job could only
        // write their own user document — the rules forbid touching anyone
        // else's — so each side lets go here, on seeing the incident close.
        if (incident != null) _releaseSelf(incident);
        _stopLiveTrackingIfResponder();
        _activeIncidentSub?.cancel();
        _activeIncidentSub = null;
      }
      notifyListeners();
    });
  }

  /// Clears this device's own `currentIncidentId` once the job is over, so
  /// the next SOS is not blocked by a finished one.
  Future<void> _releaseSelf(IncidentModel incident) async {
    final user = _currentUser;
    if (user == null) return;
    if (user.currentIncidentId != incident.id) return;
    try {
      final data = <String, dynamic>{'currentIncidentId': null};
      // A responder is free to take the next call.
      if (AppRoles.isResponder(user.effectiveRole)) data['isAvailable'] = true;
      await FirestoreService.updateUser(user.uid, data);
    } catch (_) {
      // Best effort: a stale id is recoverable, since re-attaching to a closed
      // incident is allowed and no longer blocks a new one.
    }
  }

  /// Patients never publish live location, so only stop it for responders —
  /// avoids a pointless RTDB delete on every closed incident.
  void _stopLiveTrackingIfResponder() {
    final user = _currentUser;
    if (user == null) return;
    if (AppRoles.isResponder(user.effectiveRole)) {
      LocationService.stopLiveTracking(user.uid);
    }
  }

  // Patient cancels their own SOS — clears both user and any assigned responder.
  // [reason] is a `CancelReasons` code; [note] carries the free-text detail for
  // the "Another reason" option.
  Future<void> cancelActiveIncident({String? reason, String? note}) async {
    if (_activeIncident == null || _currentUser == null) return;
    final responderId = _activeIncident!.assignedTo;
    await FirestoreService.cancelIncidentWithCleanup(
      incidentId: _activeIncident!.id,
      userId: _currentUser!.uid,
      responderId: responderId,
      cancelledBy: 'user',
      reason: reason,
      note: note,
    );
    _activeIncidentSub?.cancel();
    _activeIncident = null;
    notifyListeners();
  }

  // Patient marks their own incident resolved (e.g., responder already dropped them
  // off but forgot to close the job in the app).
  Future<void> resolveActiveIncidentByUser() async {
    if (_activeIncident == null || _currentUser == null) return;
    final responderId = _activeIncident!.assignedTo;
    if (responderId == null) return;
    _setLoading(true);
    try {
      await FirestoreService.closeIncidentForResponder(
        responderId: responderId,
        incidentId: _activeIncident!.id,
        status: IncidentStatus.resolved,
        userId: _currentUser!.uid,
      );
      _activeIncidentSub?.cancel();
      _activeIncident = null;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  // ── Responder: accept & manage incident ──────────────────────────────────────

  void _subscribeToTeamIncidents(UserModel user) {
    _pendingSub?.cancel();

    // If responder already has an active incident resume it
    if (user.currentIncidentId != null) {
      streamActiveIncident(user.currentIncidentId!);
    }

    // OFF-duty responders must not receive new incident alerts.
    if (!user.isAvailable) {
      if (_pendingIncidents.isNotEmpty || _backupRequests.isNotEmpty) {
        _pendingIncidents = [];
        _backupRequests = [];
        notifyListeners();
      }
      return;
    }

    const activeStatuses = [
      IncidentStatus.pending,
      IncidentStatus.assigned,
      IncidentStatus.enRoute,
      IncidentStatus.arrived,
    ];

    // Practitioners see medical only; ambulance sees everything.
    // Use effectiveRole so mode switches are respected.
    final relevantTypes = user.effectiveRole == AppRoles.ambulance
        ? [
            IncidentType.medical,
            IncidentType.fire,
            IncidentType.flood,
            IncidentType.security
          ]
        : [IncidentType.medical];

    _pendingSub =
        FirestoreService.streamAllPendingIncidents().listen((all) {
      final mine = all
          .where((i) => activeStatuses.contains(i.status))
          .where((i) => relevantTypes.contains(i.type))
          .where((i) => _isRoutedTo(i, user));

      _pendingIncidents = mine
          // Only show incidents not yet taken, or taken by this responder
          .where((i) => i.assignedTo == null || i.assignedTo == user.uid)
          .toList();

      _backupRequests = mine
          .where((i) => i.backupRequested)
          .where((i) => i.assignedTo != null && i.assignedTo != user.uid)
          // Not already aboard.
          .where((i) => !i.assignees.any((a) => a['uid'] == user.uid))
          .toList();

      notifyListeners();
    });
  }

  /// Whether this responder is entitled to see a given call.
  ///
  /// A private crew answers only their own provider's clients — that exclusivity
  /// is what a client pays a private provider for. Equally, public responders
  /// must never see a private provider's subscriber calls.
  bool _isRoutedTo(IncidentModel incident, UserModel user) {
    // A crew that has already handed this call on must not be offered it back.
    if (incident.declinedBy.contains(user.uid)) return false;

    if (user.isPrivateResponder) {
      // Their own provider's call, whether or not the exclusivity window has
      // since expired — they were the first choice and may still take it.
      return incident.routedTeamId != null &&
          incident.routedTeamId == user.teamId;
    }
    // Public crews see open calls, including a private one whose provider did
    // not answer inside the exclusivity window.
    return incident.routingScope != ResponderVisibility.private;
  }

  /// Returns true only if this responder now owns the call.
  ///
  /// Callers must not navigate to the job screen on false — losing the race is
  /// normal and common, and pushing a crew into a job somebody else is driving
  /// to is worse than telling them plainly that they missed it.
  Future<bool> acceptIncident(String incidentId) async {
    if (_currentUser == null) return false;
    _setLoading(true);
    _error = null;
    try {
      await FirestoreService.acceptIncident(
        incidentId: incidentId,
        responderId: _currentUser!.uid,
        responderName: _currentUser!.name,
        responderPhone: _currentUser!.phone,
        teamId: _currentUser!.teamId ?? '',
        responderRole: _currentUser!.role,
        responderSpecialization: _currentUser!.specialization,
        responderLicenseNumber: _currentUser!.licenseNumber,
        responderVehicleNumber: _currentUser!.vehicleNumber,
        // Already denormalised onto the profile when an administrator attached
        // the responder to a care point, so this costs no extra read.
        responderFacility: _currentUser!.organisation,
      );
      streamActiveIncident(incidentId);
      LocationService.startLiveTracking(_currentUser!.uid,
          incidentId: incidentId);
      return true;
    } on StateError catch (e) {
      // Already taken or already closed — expected, not a fault.
      _error = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Attended, but the job could not be finished. Needs a reason.
  Future<bool> closeUnresolved(String reason, {IncidentModel? incident}) async {
    final target = incident ?? _activeIncident;
    final responderId = _currentUser?.uid;
    if (target == null || responderId == null) {
      _error = 'Could not close this job. Try again.';
      notifyListeners();
      return false;
    }
    try {
      await FirestoreService.closeUnresolved(
        incidentId: target.id,
        responderId: responderId,
        reason: reason,
      );
      LocationService.stopLiveTracking(responderId);
      _activeIncident = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Hands the call back to the network for a crew better placed to take it.
  Future<void> rebroadcast(String reason) async {
    if (_activeIncident == null || _currentUser == null) return;
    await FirestoreService.rebroadcast(
      incidentId: _activeIncident!.id,
      responderId: _currentUser!.uid,
      reason: reason,
    );
    LocationService.stopLiveTracking(_currentUser!.uid);
    _activeIncident = null;
    notifyListeners();
  }

  /// Calls off a referral in progress.
  Future<void> cancelReferral(String carePointName, String reason) async {
    if (_activeIncident == null) return;
    await FirestoreService.cancelReferral(
      incidentId: _activeIncident!.id,
      carePointName: carePointName,
      reason: reason,
    );
  }

  /// Stands down a backup request.
  Future<void> cancelBackupRequest() async {
    if (_activeIncident == null) return;
    await FirestoreService.cancelBackupRequest(_activeIncident!.id);
  }

  /// Joins a job somebody else is already running, as backup.
  Future<bool> joinAsBackup(String incidentId) async {
    if (_currentUser == null) return false;
    try {
      await FirestoreService.joinAsBackup(
        incidentId: incidentId,
        responderId: _currentUser!.uid,
        responderName: _currentUser!.name,
        responderRole: _currentUser!.role,
        responderFacility: _currentUser!.organisation,
        responderVehicle: _currentUser!.vehicleNumber,
      );
      streamActiveIncident(incidentId);
      LocationService.startLiveTracking(_currentUser!.uid,
          incidentId: incidentId);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Asks for a second crew while staying on the job.
  Future<void> requestBackup(String reason) async {
    if (_activeIncident == null) return;
    await FirestoreService.requestBackup(
      incidentId: _activeIncident!.id,
      reason: reason,
    );
  }

  Future<void> updateStatus(String status, {IncidentModel? incident}) async {
    final target = incident ?? _activeIncident;
    if (target == null || _currentUser == null) return;
    await FirestoreService.updateIncidentStatus(target.id, status);
    // Immediately reflect locally so the stepper updates without waiting for
    // the stream to come back.
    _activeIncident = target.copyWith(status: status);
    notifyListeners();
  }

  // Responder cancels a job they already accepted (can't make it, wrong location, etc.)
  Future<void> cancelActiveIncidentByResponder() async {
    if (_activeIncident == null || _currentUser == null) return;
    LocationService.stopLiveTracking(_currentUser!.uid);
    await FirestoreService.cancelIncidentWithCleanup(
      incidentId: _activeIncident!.id,
      userId: _activeIncident!.userId,
      responderId: _currentUser!.uid,
      cancelledBy: 'responder',
    );
    _activeIncidentSub?.cancel();
    _activeIncident = null;
    notifyListeners();
  }

  /// Closes a job as resolved.
  ///
  /// Takes the incident the caller is actually looking at. This used to read
  /// [_activeIncident] alone and `return` when it was null — so on any screen
  /// whose incident came from its own stream (a resumed job, a crew who joined
  /// as backup, a user document whose `currentIncidentId` had been cleared)
  /// the button wrote nothing at all, the screen went home as though it had
  /// worked, and the job stayed open and kept appearing as incoming.
  ///
  /// Returns false when it could not write, so the caller can say so instead
  /// of navigating away on a lie.
  Future<bool> resolveIncident({IncidentModel? incident}) async {
    final target = incident ?? _activeIncident;
    final responderId = _currentUser?.uid;
    if (target == null || responderId == null) {
      _error = 'Could not close this job. Try again.';
      notifyListeners();
      return false;
    }

    try {
      LocationService.stopLiveTracking(responderId);
      await FirestoreService.closeIncidentForResponder(
        responderId: responderId,
        incidentId: target.id,
        status: IncidentStatus.resolved,
        userId: target.userId, // clears patient's currentIncidentId
      );
      _activeIncidentSub?.cancel();
      _activeIncident = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  void clearActiveIncident() {
    _activeIncidentSub?.cancel();
    _activeIncident = null;
    notifyListeners();
  }

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }

  @override
  void dispose() {
    _activeIncidentSub?.cancel();
    _pendingSub?.cancel();
    super.dispose();
  }
}
