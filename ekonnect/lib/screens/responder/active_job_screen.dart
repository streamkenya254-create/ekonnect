import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../models/incident_model.dart';
import '../../providers/incident_provider.dart';
import '../../services/location_service.dart';
import '../../services/marker_helper.dart';
import '../../services/routes_service.dart';
import '../../services/voice_guidance_service.dart';
import '../../models/care_point_model.dart';
import '../../services/firestore_service.dart';
import '../../widgets/user_avatar.dart';
import 'job_outcome_screen.dart';
import 'patient_screen.dart';
import 'referral_sheet.dart';

/// Exposes the "replay this route as if driving" control on the job map.
///
/// Test aid only — there is no way to exercise navigation, voice prompts or
/// patient-side tracking without physically travelling to an incident. Set to
/// false before shipping to real responders.
const bool kDriveSimulationEnabled = true;

class ActiveJobScreen extends StatefulWidget {
  final String incidentId;
  const ActiveJobScreen({super.key, required this.incidentId});

  @override
  State<ActiveJobScreen> createState() => _ActiveJobScreenState();
}

class _ActiveJobScreenState extends State<ActiveJobScreen> {
  GoogleMapController? _mapController;
  BitmapDescriptor? _patientMarkerIcon;

  // Route
  RouteResult? _route;
  bool _fetchingRoute = false;

  // Panel: expanded = full detail, minimised = compact driving strip
  bool _isExpanded = true;
  String? _trackedStatus; // detects status transitions

  // ── In-app navigation ──────────────────────────────────────────────────────
  // Navigation happens on this screen's own map; we deliberately never hand off
  // to the Google Maps app, so the responder stays inside the job context
  // (status controls, patient details, call/chat) the whole drive.
  bool _navMode = false;
  StreamSubscription<Position>? _posSub;
  LatLng? _myPos;
  double _myHeading = 0;

  final _voice = VoiceGuidanceService.instance;
  bool _voiceMuted = false;

  /// Tilted satellite look at the destination, so the responder can recognise
  /// the building before they get there.
  bool _dest3d = false;

  /// Test-mode only: drives a synthetic position along the route.
  bool _simulating = false;

  /// The care point currently being transported to, if any.
  CarePoint? _headingTo;
  bool _arrivedAtCarePoint = false;

  /// Where the crew was when they accepted, and whether we have already offered
  /// to mark them en route. Both exist so the offer is made exactly once.
  LatLng? _acceptedAt;
  bool _enRouteOffered = false;

  /// Guards the one-off "starting navigation" announcement per trip.
  bool _announcedStart = false;

  /// Re-route while driving, but rate-limited: the Routes API is billed per
  /// call, and GPS fires far more often than a route meaningfully changes.
  DateTime? _lastRouteFetch;
  LatLng? _lastRouteFrom;
  static const _minRerouteGap = Duration(seconds: 25);
  static const _minRerouteMetres = 150.0;

  static const _steps = [
    IncidentStatus.assigned,
    IncidentStatus.enRoute,
    IncidentStatus.arrived,
    IncidentStatus.resolved,
  ];
  // ── Lifecycle ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final provider = context.read<IncidentProvider>();
      provider.streamActiveIncident(widget.incidentId);
      provider.addListener(_onProviderUpdate);

      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      final incident = provider.activeIncident;
      final initials = (incident?.userName ?? '')
          .split(' ')
          .map((w) => w.isNotEmpty ? w[0] : '')
          .take(2)
          .join()
          .toUpperCase();
      final icon = await MarkerHelper.userPin(initials);
      if (mounted) setState(() => _patientMarkerIcon = icon);

      // Already enRoute (e.g. screen re-entered mid-drive) — resume guidance.
      if (incident?.status == IncidentStatus.enRoute) {
        _trackedStatus = incident!.status;
        _startNavigation(incident);
      }
    });
  }

  void _onProviderUpdate() {
    if (!mounted) return;
    final incident = context.read<IncidentProvider>().activeIncident;

    // Auto-navigate home when closed
    if (incident != null && incident.isClosed) {
      context.read<IncidentProvider>().removeListener(_onProviderUpdate);
      Navigator.pushReplacementNamed(context, AppRoutes.responderHome);
      return;
    }

    // React to status transitions
    if (incident != null && incident.status != _trackedStatus) {
      final prev = _trackedStatus;
      _trackedStatus = incident.status;

      if (incident.status == IncidentStatus.enRoute) {
        // Marking en route starts turn-by-turn guidance on this screen's map.
        _startNavigation(incident);
      } else if (incident.status == IncidentStatus.arrived &&
          prev == IncidentStatus.enRoute) {
        // Arrived: tear navigation down first (it stops any in-flight prompt),
        // then announce, so the arrival line is not cut off mid-sentence.
        _stopNavigation();
        _voice.announceArrival();
        setState(() => _isExpanded = true);
      }
    }
  }

  @override
  void dispose() {
    try {
      context.read<IncidentProvider>().removeListener(_onProviderUpdate);
    } catch (_) {}
    _posSub?.cancel();
    _voice.stop();
    _mapController?.dispose();
    super.dispose();
  }

  // ── Route fetching ───────────────────────────────────────────────────────────

  String? get _patientName =>
      context.read<IncidentProvider>().activeIncident?.userName;

  Future<void> _fetchRoute(double destLat, double destLng,
      {bool fitCamera = true}) async {
    if (_fetchingRoute) return;

    final origin = _myPos ??
        await LocationService.getCurrentPosition()
            .then((p) => p == null ? null : LatLng(p.latitude, p.longitude));
    if (!mounted || origin == null) return;

    setState(() => _fetchingRoute = true);
    try {
      // Steps are only needed for turn-by-turn, so skip them otherwise.
      final route = await RoutesService.compute(
        origin: origin,
        destination: LatLng(destLat, destLng),
        includeSteps: true,
      );
      if (!mounted) return;

      final isReroute = _route != null;
      setState(() => _route = route);
      _lastRouteFetch = DateTime.now();
      _lastRouteFrom = origin;

      if (_navMode && !route.isEstimate) {
        if (!_announcedStart) {
          _announcedStart = true;
          _voice.announceStart(
            distanceText: route.distanceText,
            durationText: route.durationText,
            patientName: _patientName,
          );
        } else if (isReroute) {
          _voice.announceRerouted();
        }
      }

      if (fitCamera && !_navMode) _fitRoute(route.points);
    } finally {
      if (mounted) setState(() => _fetchingRoute = false);
    }
  }

  void _fitRoute(List<LatLng> points) {
    if (points.isEmpty || _mapController == null) return;
    var minLat = points.first.latitude, maxLat = points.first.latitude;
    var minLng = points.first.longitude, maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat - 0.005, minLng - 0.005),
          northeast: LatLng(maxLat + 0.005, maxLng + 0.005),
        ),
        80,
      ),
    );
  }

  // ── In-app navigation ──────────────────────────────────────────────────────

  void _startNavigation(IncidentModel incident) {
    if (_navMode) return;
    setState(() {
      _navMode = true;
      _isExpanded = false;
    });

    _announcedStart = false;
    _voice.init().then((_) {
      _voice.reset();
      if (mounted) setState(() => _voiceMuted = _voice.isMuted);
    });

    _posSub?.cancel();
    _posSub = LocationService.positionStream().listen((pos) {
      if (!mounted) return;
      final here = LatLng(pos.latitude, pos.longitude);
      // GPS heading is unreliable when stationary; fall back to route bearing.
      final heading = pos.speed > 1.0
          ? pos.heading
          : (_route != null && _route!.points.length > 1
              ? RoutesService.bearingBetween(here, _route!.points.last)
              : _myHeading);

      setState(() {
        _myPos = here;
        _myHeading = heading;
      });

      _followCamera(here, heading);
      _speakGuidance(here);
      _maybeReroute(incident, here);
      _maybeOfferEnRoute(incident, here);
    });

    // Kick off an immediate route so the first frame already has guidance.
    _fetchRoute(incident.userLat, incident.userLng, fitCamera: false);
  }

  void _stopNavigation() {
    _posSub?.cancel();
    _posSub = null;
    _voice.stop();
    if (mounted) setState(() => _navMode = false);
    if (_route != null) _fitRoute(_route!.points);
  }

  /// Speaks the current manoeuvre. The service decides whether this particular
  /// prompt is actually due, so it is safe to call on every GPS tick.
  void _speakGuidance(LatLng here) {
    final route = _route;
    if (route == null || route.isEstimate) return;
    final step = route.currentStep(here);
    if (step == null) return;

    _voice.announceStep(
      instruction: step.instruction,
      metresToStep: RoutesService.metresBetween(here, step.endLocation).round(),
    );
  }

  /// Hands the patient on to a hospital, clinic or station.
  ///
  /// Available from "arrived" onward and reusable: if a facility turns the
  /// patient away, the responder refers again and the attempt is appended to
  /// the chain rather than replacing the previous one.
  Future<void> _openReferral(IncidentModel incident) async {
    final LatLng origin;
    final mine = _myPos;
    if (mine != null) {
      origin = mine;
    } else {
      final pos = await LocationService.getCurrentPosition();
      // Fall back to the patient's location — the responder is standing there.
      origin = pos != null
          ? LatLng(pos.latitude, pos.longitude)
          : LatLng(incident.userLat, incident.userLng);
    }

    if (!mounted) return;
    final chosen = await showModalBottomSheet<CarePoint>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ReferralSheet(incident: incident, origin: origin),
    );
    if (chosen == null || !mounted) return;

    await FirestoreService.addReferral(
      incidentId: incident.id,
      referral: chosen.toReferralEntry(),
    );

    // A previous care point is being left behind — record that it could not
    // help, otherwise the journey looks like the patient wandered for no
    // reason. The reason is asked for, never assumed.
    final previous = incident.referrals.isNotEmpty
        ? incident.referrals.last
        : null;
    if (previous != null && mounted) {
      final reason = await _askDeclineReason(previous['name'] as String? ?? '');
      if (reason != null) {
        await FirestoreService.logDeclined(
          incidentId: incident.id,
          carePointId: previous['carePointId'] as String? ?? '',
          carePointName: previous['name'] as String? ?? 'Care point',
          reason: reason,
        );
      }
    }

    // Departure and arrival are logged separately: the gap between them is the
    // transport time, which is invisible if only arrival is recorded.
    await FirestoreService.logDeparture(
      incidentId: incident.id,
      carePointId: chosen.id,
      carePointName: chosen.name,
    );
    if (!mounted) return;

    setState(() => _headingTo = chosen);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(chosen.isVisitable
            ? 'Taking patient to ${chosen.name}'
            : '${chosen.name} notified'),
        backgroundColor: AppColors.success,
      ),
    );

    // Navigate on to the facility when it is somewhere the patient is taken.
    if (chosen.isVisitable) {
      setState(() => _route = null);
      _fetchRoute(chosen.lat, chosen.lng, fitCamera: !_navMode);
    }
  }

  /// Everything about the patient, on demand.
  ///
  /// The panel used to print name and number permanently, which cost a third
  /// of its height on a leg where the crew already has the patient beside
  /// them. Here there is room for what actually gets looked up mid-job — the
  /// triage notes, the emergency type, the pickup point.
  /// Opens the patient in full.
  ///
  /// A page rather than a sheet: it carries their photo, their contact and
  /// the way to message them, which is what the card gave up to stay legible
  /// with a patient in front of you.
  Future<void> _showPatientDetails(IncidentModel incident) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PatientScreen(incident: incident)),
    );
  }

  /// Calls off the referral. The patient recovered, the facility turned them
  /// away, or it was chosen in error — either way the crew is back on scene
  /// and the transport leg should not sit half-finished in the record.
  Future<void> _cancelReferral(IncidentModel incident) async {
    final target = _headingTo;
    if (target == null) return;

    final reason = await _quickReason(
      title: 'Cancel this referral?',
      blurb: 'The journey to ${target.name} is called off and you go back to '
          'being on scene. The attempt stays in the record.',
      hint: 'Patient recovered, no longer needs transport',
      confirm: 'Cancel referral',
    );
    if (reason == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    await context.read<IncidentProvider>().cancelReferral(target.name, reason);
    if (!mounted) return;

    setState(() {
      _headingTo = null;
      _arrivedAtCarePoint = false;
      _route = null;
    });
    // Back to the patient as the destination.
    _fetchRoute(incident.userLat, incident.userLng, fitCamera: !_navMode);
    messenger.showSnackBar(
      SnackBar(content: Text('Referral to ${target.name} cancelled')),
    );
  }

  Future<void> _standDownBackup() async {
    final messenger = ScaffoldMessenger.of(context);
    await context.read<IncidentProvider>().cancelBackupRequest();
    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('Backup request stood down')),
    );
  }

  Future<String?> _quickReason({
    required String title,
    required String blurb,
    required String hint,
    required String confirm,
  }) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(blurb,
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textLight)),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: hint,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Keep it')),
          ElevatedButton(
            onPressed: () {
              final v = controller.text.trim();
              if (v.isEmpty) return;
              Navigator.pop(ctx, v);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.emergency),
            child: Text(confirm),
          ),
        ],
      ),
    );
  }

  /// Confirms arrival at the care point currently being travelled to.
  Future<void> _confirmArrivalAtCarePoint(IncidentModel incident) async {
    final target = _headingTo;
    if (target == null) return;

    await FirestoreService.logArrivalAtCarePoint(
      incidentId: incident.id,
      carePointId: target.id,
      carePointName: target.name,
    );
    if (!mounted) return;
    setState(() => _arrivedAtCarePoint = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Arrival at ${target.name} recorded'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  Future<String?> _askDeclineReason(String carePointName) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Why the move?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Briefly, why could $carePointName not take this patient? This '
              'stays on the incident record.',
              style: const TextStyle(
                  fontSize: 14, height: 1.4, color: AppColors.textMedium),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLength: 120,
              decoration: InputDecoration(
                hintText: 'e.g. No ICU bed available',
                counterText: '',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Skip'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  /// Swoops to a tilted, close-in satellite view of the patient's location.
  /// Google Maps renders 3D buildings and terrain at this tilt/zoom, which is
  /// far more recognisable on arrival than a flat road map.
  void _toggleDestination3d(IncidentModel incident) {
    final on = !_dest3d;
    setState(() => _dest3d = on);

    if (on) {
      // Leave navigation follow-mode alone; this is a look-ahead, not a route.
      _mapController?.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(incident.userLat, incident.userLng),
          zoom: 18.5,
          tilt: 67,
          bearing: _myPos == null
              ? 0
              : RoutesService.bearingBetween(
                  _myPos!, LatLng(incident.userLat, incident.userLng)),
        ),
      ));
    } else if (_navMode && _myPos != null) {
      _followCamera(_myPos!, _myHeading);
    } else if (_route != null) {
      _fitRoute(_route!.points);
    }
  }

  /// Replays the route as if driving it. Without this there is no way to see
  /// navigation, voice prompts or patient-side tracking work short of
  /// physically travelling to the incident.
  Future<void> _toggleSimulation(IncidentModel incident) async {
    if (_simulating) {
      LocationService.stopSimulation();
      setState(() => _simulating = false);
      _stopNavigation();
      return;
    }

    // Need a route to drive along; fetch one if navigation has not yet got it.
    if (_route == null || _route!.points.length < 2) {
      await _fetchRoute(incident.userLat, incident.userLng, fitCamera: false);
    }
    final route = _route;
    if (!mounted || route == null || route.points.length < 2) return;

    setState(() => _simulating = true);
    LocationService.startSimulation(route.points, speedKmh: 45);

    // Re-subscribe so navigation reads the simulated stream instead of GPS.
    if (_navMode) {
      _posSub?.cancel();
      _posSub = null;
      setState(() => _navMode = false);
    }
    _startNavigation(incident);
  }

  void _followCamera(LatLng here, double heading) {
    _mapController?.animateCamera(CameraUpdate.newCameraPosition(
      CameraPosition(target: here, zoom: 17.5, bearing: heading, tilt: 50),
    ));
  }

  /// Re-fetches the route only when it is actually worth spending a call:
  /// enough time has passed, or the driver has moved far enough.
  /// Offers to mark en route once the crew has actually set off.
  ///
  /// A prompt, not an automatic flip. Detection is a heuristic — a crew
  /// crossing a car park looks identical to a crew pulling away — and silently
  /// telling a patient someone is on the way when they are still finding their
  /// keys is a worse failure than asking. One tap either way, offered once.
  void _maybeOfferEnRoute(IncidentModel incident, LatLng here) {
    if (_enRouteOffered) return;
    if (incident.status != IncidentStatus.assigned) return;

    final origin = _acceptedAt;
    if (origin == null) {
      _acceptedAt = here;
      return;
    }

    final movedFromStart = RoutesService.metresBetween(origin, here);
    if (movedFromStart < 120) return;

    // Moving is not enough — it has to be movement *towards* the patient, or
    // a crew heading home for their shift change would be marked en route.
    final dest = LatLng(incident.userLat, incident.userLng);
    final before = RoutesService.metresBetween(origin, dest);
    final now = RoutesService.metresBetween(here, dest);
    if (now >= before - 80) return;

    _enRouteOffered = true;
    _promptEnRoute();
  }

  Future<void> _promptEnRoute() async {
    final provider = context.read<IncidentProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('On your way?'),
        content: const Text(
            'It looks like you have set off. Marking en route starts live '
            'tracking for the patient and gives them an arrival estimate.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not yet')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Yes, en route'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await provider.updateStatus(IncidentStatus.enRoute);
  }

  void _maybeReroute(IncidentModel incident, LatLng here) {
    // No route yet means the initial fetch failed — typically GPS was not warm
    // at the instant navigation started, so _fetchRoute bailed with no origin.
    // Retry on every fix until one lands. Without this a *stationary* responder
    // never satisfies the movement thresholds below, so they would sit in
    // navigation mode with no line, no instructions and no ETA, indefinitely.
    if (_route == null) {
      _fetchRoute(incident.userLat, incident.userLng, fitCamera: false);
      return;
    }

    final now = DateTime.now();
    final elapsed = _lastRouteFetch == null
        ? _minRerouteGap
        : now.difference(_lastRouteFetch!);
    final moved = _lastRouteFrom == null
        ? _minRerouteMetres
        : RoutesService.metresBetween(_lastRouteFrom!, here);

    if ((elapsed >= _minRerouteGap && moved >= 30) ||
        moved >= _minRerouteMetres) {
      _fetchRoute(incident.userLat, incident.userLng, fitCamera: false);
    }
  }

  // ── Actions ──────────────────────────────────────────────────────────────────

  Future<void> _advanceStatus(IncidentModel incident) async {
    final provider = context.read<IncidentProvider>();
    final nav = Navigator.of(context);

    // ── Transport leg ────────────────────────────────────────────────
    final target = _headingTo;
    if (target != null && target.isVisitable) {
      if (!_arrivedAtCarePoint) {
        await _confirmArrivalAtCarePoint(incident);
        return;
      }
      // Handed over: the patient is now the facility's, so the job closes.
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Handed over to ${target.name}?'),
          content: const Text(
              'Confirms the patient has been admitted and closes the job. '
              'The full journey stays on the record.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Not yet')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success),
              child: const Text('Confirm handover'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
      // Pass the incident this screen is showing: the provider's copy can be
      // null on a resumed or backup job, and closing must not depend on it.
      final closed = await provider.resolveIncident(incident: incident);
      if (!mounted) return;
      if (!closed) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(provider.error ?? 'Could not close this job.'),
          backgroundColor: AppColors.emergency,
        ));
        return;
      }
      nav.pushReplacementNamed(AppRoutes.responderHome);
      return;
    }

    // ── Leg to the patient ───────────────────────────────────────────
    final nextIndex = _steps.indexOf(incident.status) + 1;
    if (nextIndex >= _steps.length) return;
    final nextStatus = _steps[nextIndex];

    if (nextStatus == IncidentStatus.resolved) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Resolve Incident?'),
          content: const Text(
              'Mark this incident as resolved? This will close the job and notify the patient.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
              child: const Text('Resolve'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
      // Pass the incident this screen is showing: the provider's copy can be
      // null on a resumed or backup job, and closing must not depend on it.
      final closed = await provider.resolveIncident(incident: incident);
      if (!mounted) return;
      if (!closed) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(provider.error ?? 'Could not close this job.'),
          backgroundColor: AppColors.emergency,
        ));
        return;
      }
      nav.pushReplacementNamed(AppRoutes.responderHome);
    } else {
      await provider.updateStatus(nextStatus);
    }
  }

  Future<void> _cancelJob(IncidentModel incident) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Cancel this job?'),
        content: const Text(
            'The patient will be notified and given the option to re-broadcast their SOS.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep Job')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Cancel', style: TextStyle(color: AppColors.emergency)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final nav = Navigator.of(context);
    await context.read<IncidentProvider>().cancelActiveIncidentByResponder();
    if (mounted) nav.pushReplacementNamed(AppRoutes.responderHome);
  }

  // Navigation is handled in-app by [_startNavigation]; we intentionally do not
  // hand off to the Google Maps app, which would drop the responder out of the
  // job context mid-drive.

  // ── Build ────────────────────────────────────────────────────────────────────

  /// A real road route draws solid; a straight-line estimate draws thin and
  /// translucent so it never reads as an actual drivable path.
  Set<Polyline> _buildPolylines() {
    final route = _route;
    if (route == null || route.isEmpty) return {};
    return {
      Polyline(
        polylineId: const PolylineId('route'),
        points: route.points,
        color: route.isEstimate
            ? AppColors.primary.withValues(alpha: 0.45)
            : AppColors.primary,
        width: route.isEstimate ? 3 : 6,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final incident = context.watch<IncidentProvider>().activeIncident;
    if (incident == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final color = IncidentType.color(incident.type);
    final journey = JobJourney.of(
      incident,
      headingTo: _headingTo,
      arrivedAtCarePoint: _arrivedAtCarePoint,
    );
    final isEnRoute = incident.status == IncidentStatus.enRoute;
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      body: Stack(
        children: [
          // ── Full-screen map ──────────────────────────────────────────
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: LatLng(incident.userLat, incident.userLng),
              zoom: 15,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            // Hybrid keeps street labels over the satellite imagery, so the
            // 3D look-ahead stays navigable rather than being pretty but mute.
            mapType: _dest3d ? MapType.hybrid : MapType.normal,
            buildingsEnabled: true,
            markers: {
              Marker(
                markerId: const MarkerId('patient'),
                position: LatLng(incident.userLat, incident.userLng),
                icon: _patientMarkerIcon ??
                    BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                anchor: const Offset(0.5, 0.85),
                infoWindow: InfoWindow(
                    title: incident.userName, snippet: incident.userPhone),
              ),
            },
            polylines: _buildPolylines(),
            onMapCreated: (c) {
              _mapController = c;
              c.animateCamera(
                  CameraUpdate.newLatLng(LatLng(incident.userLat, incident.userLng)));
            },
          ),

          // ── Floating top bar ─────────────────────────────────────────
          Positioned(
            top: topPad + 8,
            left: 12,
            right: 12,
            child: Row(
              children: [
                // Incident type chip
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 10)
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(IncidentType.icon(incident.type), color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      Text(IncidentType.label(incident.type),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const Spacer(),
                // Home button
                GestureDetector(
                  onTap: () => Navigator.pushReplacementNamed(context, AppRoutes.responderHome),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8)
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.home_outlined, size: 16, color: AppColors.textDark),
                        SizedBox(width: 4),
                        Text('Home',
                            style: TextStyle(
                                fontSize: 14,
                                color: AppColors.textDark,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── What this leg is, and how to call it off ──────────────────
          //
          // A referral or a backup request changes what the crew is doing; the
          // map should say so, and both are things that get overtaken by
          // events — the patient recovers, the second crew turns out not to be
          // needed. Neither used to be reversible.
          if (_headingTo != null || incident.backupRequested)
            Positioned(
              top: topPad + 62,
              left: 12,
              // Clear of the floating control column, which was slicing
              // "Cancel referral" off the edge of the screen.
              right: 76,
              child: _LegBanner(
                title: _headingTo != null
                    ? 'Transporting to ${_headingTo!.name}'
                    : 'Backup requested',
                subtitle: _headingTo != null
                    ? (_arrivedAtCarePoint
                        ? 'Arrived — confirm the handover below'
                        : 'Destination changed to the care point')
                    : 'Waiting for a second crew to join you',
                icon: _headingTo != null
                    ? Icons.local_hospital_rounded
                    : Icons.group_add_rounded,
                colour: _headingTo != null ? AppColors.accent : AppColors.primary,
                cancelLabel: _headingTo != null ? 'Cancel referral' : 'Stand down',
                onCancel: _headingTo != null
                    ? () => _cancelReferral(incident)
                    : _standDownBackup,
              ),
            ),

          // ── Turn-by-turn instruction banner (in-app navigation) ───────
          if (_navMode && _route != null)
            Positioned(
              top: topPad + (_headingTo != null || incident.backupRequested ? 136 : 62),
              left: 12,
              right: 12,
              child: _NavBanner(
                route: _route!,
                myPos: _myPos,
                color: color,
                muted: _voiceMuted,
                onToggleMute: () async {
                  final muted = await _voice.toggleMute();
                  if (mounted) setState(() => _voiceMuted = muted);
                },
              ),
            )
          // ── ETA card — driving, but not in full navigation mode ────────
          else if (isEnRoute && _route != null)
            Positioned(
              top: topPad + 62,
              left: 12,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 12)
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Icon(Icons.timer_outlined, size: 14, color: color),
                    const SizedBox(width: 6),
                    Text(_route!.durationText,
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 17, color: color)),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 1),
                      child: Text(_route!.distanceText,
                          style: const TextStyle(
                              color: AppColors.textMedium, fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ),

          // ── Right-side floating buttons ──────────────────────────────
          Positioned(
            right: 12,
            bottom: _isExpanded ? 400 : 110,
            child: Column(
              children: [
                // Refresh / loading route
                _MapBtn(
                  onTap: _fetchingRoute
                      ? null
                      : () => _fetchRoute(incident.userLat, incident.userLng),
                  child: _fetchingRoute
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.primary))
                      : const Icon(Icons.route_rounded, color: AppColors.primary, size: 20),
                ),
                const SizedBox(height: 8),
                // Start / stop in-app navigation
                _MapBtn(
                  onTap: () => _navMode
                      ? _stopNavigation()
                      : _startNavigation(incident),
                  color: _navMode ? AppColors.emergency : AppColors.primary,
                  child: Icon(
                    _navMode ? Icons.close_rounded : Icons.navigation_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                // Referral becomes relevant once the crew is with the patient
                // and knows what they actually need.
                if (incident.status == IncidentStatus.arrived ||
                    incident.referrals.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _MapBtn(
                    onTap: () => _openReferral(incident),
                    color: AppColors.accent,
                    child: const Icon(Icons.local_hospital_rounded,
                        color: Colors.white, size: 20),
                  ),
                ],
                // Confirms the transport leg has ended, which is what turns
                // "left at 14:02" into a measurable journey time.
                if (_headingTo != null &&
                    !_arrivedAtCarePoint &&
                    _headingTo!.isVisitable) ...[
                  const SizedBox(height: 8),
                  _MapBtn(
                    onTap: () => _confirmArrivalAtCarePoint(incident),
                    color: AppColors.success,
                    child: const Icon(Icons.flag_rounded,
                        color: Colors.white, size: 20),
                  ),
                ],
                const SizedBox(height: 8),
                // 3D look at the destination
                _MapBtn(
                  onTap: () => _toggleDestination3d(incident),
                  color: _dest3d ? AppColors.primary : null,
                  child: Icon(
                    Icons.threed_rotation_rounded,
                    color: _dest3d ? Colors.white : AppColors.primary,
                    size: 20,
                  ),
                ),
                if (kDriveSimulationEnabled) ...[
                  const SizedBox(height: 8),
                  _MapBtn(
                    onTap: () => _toggleSimulation(incident),
                    color: _simulating ? AppColors.success : null,
                    child: Icon(
                      _simulating
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: _simulating ? Colors.white : AppColors.success,
                      size: 22,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                // Re-centre: on me while navigating, else on the patient
                _MapBtn(
                  onTap: () {
                    if (_navMode && _myPos != null) {
                      _followCamera(_myPos!, _myHeading);
                    } else {
                      _mapController?.animateCamera(CameraUpdate.newLatLng(
                          LatLng(incident.userLat, incident.userLng)));
                    }
                  },
                  child: Icon(Icons.my_location_rounded, color: color, size: 20),
                ),
              ],
            ),
          ),

          // ── Bottom panel ─────────────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomPanel(
              incident: incident,
              color: color,
              journey: journey,
              isExpanded: _isExpanded,
              distanceText: _route?.distanceText,
              durationText: _route?.durationText,
              onToggle: () => setState(() => _isExpanded = !_isExpanded),
              onAdvance: () => _advanceStatus(incident),
              onCancel: () => _cancelJob(incident),
              onNotResolved: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => JobOutcomeScreen(
                    incident: incident,
                    onRefer: () => _openReferral(incident),
                  ),
                ),
              ),
              onPatientDetails: () => _showPatientDetails(incident),
              onNavigate: () =>
                  _navMode ? _stopNavigation() : _startNavigation(incident),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bottom Panel ──────────────────────────────────────────────────────────────

/// The stage of the job the crew is actually in.
///
/// The old bar was four fixed dots — Assigned, En Route, Arrived, Resolved —
/// which stopped describing anything the moment a referral turned the job into
/// a second trip. A journey with a referral has two legs and the crew is in
/// one of them; the bar now says which, and what the steps of *that* leg are.
class JobJourney {
  final String title;
  final String? subtitle;
  final List<String> labels;
  final List<IconData> icons;
  final int index;

  /// Second leg — transporting to a care point rather than driving to a
  /// patient. The map swaps its destination to match.
  final bool isTransportLeg;

  /// What the big button says here. "Resolved" is wrong on a transport leg:
  /// the crew is not finishing the job, they are handing the patient over.
  final String primaryLabel;
  final IconData primaryIcon;

  const JobJourney({
    required this.title,
    this.subtitle,
    required this.labels,
    required this.icons,
    required this.index,
    required this.primaryLabel,
    required this.primaryIcon,
    this.isTransportLeg = false,
  });

  static const _toPatientLabels = ['Assigned', 'On the way', 'On scene'];
  static const _toPatientIcons = [
    Icons.assignment_turned_in_outlined,
    Icons.directions_car_outlined,
    Icons.location_on_outlined,
  ];
  static const _transportLabels = ['Referred', 'Transporting', 'Handed over'];
  static const _transportIcons = [
    Icons.local_hospital_outlined,
    Icons.airport_shuttle_outlined,
    Icons.how_to_reg_outlined,
  ];

  factory JobJourney.of(
    IncidentModel incident, {
    CarePoint? headingTo,
    required bool arrivedAtCarePoint,
  }) {
    if (headingTo != null && headingTo.isVisitable) {
      return JobJourney(
        title: 'Taking ${incident.userName} to ${headingTo.name}',
        subtitle: arrivedAtCarePoint
            ? 'Patient delivered — close the job when they are admitted'
            : 'Referral accepted. Drive when ready.',
        labels: _transportLabels,
        icons: _transportIcons,
        index: arrivedAtCarePoint ? 2 : 1,
        isTransportLeg: true,
        primaryLabel: arrivedAtCarePoint
            ? 'Handed over — close job'
            : 'Arrived at ${headingTo.name}',
        primaryIcon: arrivedAtCarePoint
            ? Icons.how_to_reg_rounded
            : Icons.flag_rounded,
      );
    }

    final idx = switch (incident.status) {
      IncidentStatus.enRoute => 1,
      IncidentStatus.arrived => 2,
      _ => 0,
    };
    return JobJourney(
      title: switch (idx) {
        0 => 'Call accepted',
        1 => 'On the way to ${incident.userName}',
        _ => 'On scene with ${incident.userName}',
      },
      subtitle: idx == 2 ? 'Assess, then choose how this job ends' : null,
      labels: _toPatientLabels,
      icons: _toPatientIcons,
      index: idx,
      primaryLabel: switch (idx) {
        0 => 'Mark on the way',
        1 => 'Mark arrived',
        _ => 'Resolved — job done',
      },
      primaryIcon: switch (idx) {
        0 => Icons.directions_car_rounded,
        1 => Icons.location_on_rounded,
        _ => Icons.check_circle_outline,
      },
    );
  }
}

class _BottomPanel extends StatelessWidget {
  final IncidentModel incident;
  final Color color;
  final JobJourney journey;
  final bool isExpanded;
  final String? distanceText;
  final String? durationText;
  final VoidCallback onToggle;
  final VoidCallback onAdvance;
  final VoidCallback onCancel;
  final VoidCallback onNotResolved;
  final VoidCallback onPatientDetails;
  final VoidCallback onNavigate;


  const _BottomPanel({
    required this.incident,
    required this.color,
    required this.journey,
    required this.isExpanded,
    required this.distanceText,
    required this.durationText,
    required this.onToggle,
    required this.onAdvance,
    required this.onCancel,
    required this.onNotResolved,
    required this.onPatientDetails,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Expandable detail panel ──────────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOutCubic,
            child: isExpanded ? _DetailPanel(this) : const SizedBox.shrink(),
          ),

          // ── Always-visible compact strip ─────────────────────────────
          _CompactStrip(this),
        ],
      ),
    );
  }
}

// ── Detail panel (expanded) ───────────────────────────────────────────────────

class _DetailPanel extends StatelessWidget {
  final _BottomPanel p;
  const _DetailPanel(this.p);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, -4))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          GestureDetector(
            onTap: p.onToggle,
            child: Container(
              color: Colors.transparent,
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
              child: Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Which leg of the journey this is ─────────────────
                Row(
                  children: [
                    if (p.journey.isTransportLeg)
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('LEG 2',
                            style: TextStyle(
                                fontSize: 11,
                                letterSpacing: 0.8,
                                fontWeight: FontWeight.bold,
                                color: AppColors.accent)),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.journey.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.cardTitle,
                          ),
                          if (p.journey.subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(p.journey.subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.meta),
                          ],
                        ],
                      ),
                    ),
                    // The patient, as a face in the corner. Everything the
                    // card used to spell out — their name, a call button, a
                    // message button — is one tap behind it now.
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: p.onPatientDetails,
                      child: UserAvatar(
                        user: null,
                        fallbackName: p.incident.userName,
                        size: 46,
                        background: p.color.withValues(alpha: 0.12),
                        foreground: p.color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // ── Stepper ──────────────────────────────────────────
                Row(
                  children: List.generate(p.journey.labels.length, (i) {
                    final done = i <= p.journey.index;
                    final active = i == p.journey.index;
                    return Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  width: active ? 34 : 26,
                                  height: active ? 34 : 26,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: done ? p.color : AppColors.divider,
                                    boxShadow: active
                                        ? [BoxShadow(color: p.color.withValues(alpha: 0.4), blurRadius: 10)]
                                        : null,
                                  ),
                                  child: Icon(
                                    done ? p.journey.icons[i] : Icons.circle_outlined,
                                    size: active ? 17 : 13,
                                    color: done ? Colors.white : AppColors.textLight,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                // One line, always. "Assigned" was breaking
                                // to "Assign / ed" once the columns narrowed.
                                Text(p.journey.labels[i],
                                    maxLines: 1,
                                    overflow: TextOverflow.visible,
                                    softWrap: false,
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: active ? FontWeight.bold : FontWeight.normal,
                                        color: done ? p.color : AppColors.textLight),
                                    textAlign: TextAlign.center),
                              ],
                            ),
                          ),
                          if (i < p.journey.labels.length - 1)
                            Expanded(
                              flex: 2,
                              child: Container(
                                height: 2,
                                margin: const EdgeInsets.only(bottom: 18),
                                decoration: BoxDecoration(
                                  color: i < p.journey.index ? p.color : AppColors.divider,
                                  borderRadius: BorderRadius.circular(1),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                ),

                const SizedBox(height: 14),

                // ── Action buttons ────────────────────────────────────
                if (p.incident.isClosed) ...[
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pushReplacementNamed(context, AppRoutes.responderHome),
                    icon: const Icon(Icons.home_rounded, size: 20),
                    label: const Text('Done — Go Home',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ] else if (p.incident.status == IncidentStatus.arrived) ...[
                  // With the patient. This is the moment every remaining
                  // decision belongs to, and until now the only way to refer
                  // was an unlabelled hospital icon floating on the map.
                  ElevatedButton.icon(
                    onPressed: p.onAdvance,
                    icon: Icon(p.journey.primaryIcon, size: 20),
                    label: Text(p.journey.primaryLabel,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: p.onNotResolved,
                    icon: const Icon(Icons.more_horiz_rounded, size: 18),
                    label: const Text('Not resolved — other options',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textMedium,
                      side: const BorderSide(color: AppColors.divider),
                      minimumSize: const Size(double.infinity, 46),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ] else ...[
                  ElevatedButton.icon(
                    onPressed: p.onAdvance,
                    icon: Icon(
                      p.incident.status == IncidentStatus.arrived
                          ? Icons.check_circle_outline
                          : Icons.arrow_forward_rounded,
                      size: 20,
                    ),
                    label: Text(p.journey.primaryLabel,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: p.color,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: p.onCancel,
                    icon: const Icon(Icons.cancel_outlined, size: 16, color: AppColors.emergency),
                    label: const Text('Cancel Job',
                        style: TextStyle(color: AppColors.emergency, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.emergency),
                      minimumSize: const Size(double.infinity, 44),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ],

                const SizedBox(height: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Compact driving strip ─────────────────────────────────────────────────────

class _CompactStrip extends StatelessWidget {
  final _BottomPanel p;
  const _CompactStrip(this.p);

  @override
  Widget build(BuildContext context) {
    final isEnRoute = p.incident.status == IncidentStatus.enRoute;
    final hasEta = p.distanceText != null;

    return GestureDetector(
      onTap: p.onToggle,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: p.isExpanded
              ? BorderRadius.zero
              : const BorderRadius.vertical(top: Radius.circular(22)),
          boxShadow: p.isExpanded
              ? null
              : [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, -3))],
          border: Border(
            top: BorderSide(color: p.color.withValues(alpha: 0.25), width: 2),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              // Status indicator dot
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.color,
                  boxShadow: [BoxShadow(color: p.color.withValues(alpha: 0.5), blurRadius: 6)],
                ),
              ),
              const SizedBox(width: 10),

              // Status label
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      IncidentStatus.label(p.incident.status),
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: p.color),
                    ),
                    if (isEnRoute && hasEta)
                      Text('${p.durationText} · ${p.distanceText}',
                          style: const TextStyle(
                              color: AppColors.textMedium, fontSize: 12.5)),
                  ],
                ),
              ),

              // Navigate button (only while driving)
              if (isEnRoute)
                GestureDetector(
                  onTap: p.onNavigate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: p.color,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.navigation_rounded, color: Colors.white, size: 14),
                        SizedBox(width: 4),
                        Text('Navigate',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13)),
                      ],
                    ),
                  ),
                )
              else if (!p.incident.isClosed)
                // Quick-advance when not driving
                GestureDetector(
                  onTap: p.onAdvance,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: p.color,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(p.journey.primaryLabel,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                  ),
                ),

              const SizedBox(width: 8),

              // Expand / collapse chevron
              Icon(
                p.isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                color: AppColors.textLight,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Small floating map button ─────────────────────────────────────────────────

class _MapBtn extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;
  final Color? color;
  const _MapBtn({required this.onTap, required this.child, this.color});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color ?? Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 10,
                offset: const Offset(0, 2))
          ],
        ),
        child: Center(child: child),
      ),
    );
  }
}

// ── In-app navigation banner ──────────────────────────────────────────────────

/// Shows the current manoeuvre plus remaining distance/ETA, replacing the old
/// hand-off to the Google Maps app.
class _NavBanner extends StatelessWidget {
  final RouteResult route;
  final LatLng? myPos;
  final Color color;
  final bool muted;
  final VoidCallback onToggleMute;

  const _NavBanner({
    required this.route,
    required this.myPos,
    required this.color,
    required this.muted,
    required this.onToggleMute,
  });

  @override
  Widget build(BuildContext context) {
    final step = myPos == null ? null : route.currentStep(myPos!);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.primaryDark,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 14)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_iconFor(step?.instruction), color: Colors.white, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  step?.instruction ?? 'Head to the patient',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.25),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Voice can be silenced without leaving navigation — a responder
              // on a phone call still needs the visual guidance.
              GestureDetector(
                onTap: onToggleMute,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    color: muted
                        ? Colors.white.withValues(alpha: 0.5)
                        : Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (step != null) ...[
                _pill(_metres(step.distanceMeters)),
                const SizedBox(width: 8),
              ],
              _pill(route.durationText, strong: true),
              const SizedBox(width: 8),
              _pill(route.distanceText),
              const Spacer(),
              Text(
                'ETA ${route.arrivalText()}',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          // Be explicit when the Routes API is unavailable — a straight-line
          // guess must never masquerade as real turn-by-turn guidance.
          if (route.isEstimate) ...[
            const SizedBox(height: 8),
            Text(
              'Approximate — live routing unavailable',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6), fontSize: 12.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pill(String text, {bool strong = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: strong ? 0.22 : 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: Colors.white,
            fontSize: strong ? 13 : 12,
            fontWeight: strong ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      );

  static String _metres(int m) =>
      m < 1000 ? '$m m' : '${(m / 1000).toStringAsFixed(1)} km';

  /// Maps the Routes API instruction text onto a manoeuvre icon.
  static IconData _iconFor(String? instruction) {
    final s = (instruction ?? '').toLowerCase();
    if (s.contains('left')) return Icons.turn_left_rounded;
    if (s.contains('right')) return Icons.turn_right_rounded;
    if (s.contains('u-turn')) return Icons.u_turn_left_rounded;
    if (s.contains('roundabout')) return Icons.roundabout_left_rounded;
    if (s.contains('merge')) return Icons.merge_rounded;
    if (s.contains('destination') || s.contains('arrive')) {
      return Icons.place_rounded;
    }
    return Icons.straight_rounded;
  }
}


/// Names the leg the crew is on, and gives them a way out of it.
class _LegBanner extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color colour;
  final String cancelLabel;
  final VoidCallback onCancel;

  const _LegBanner({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colour,
    required this.cancelLabel,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colour.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colour.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 19, color: colour),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark)),
                const SizedBox(height: 1),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12.5, color: AppColors.textLight)),
              ],
            ),
          ),
          TextButton(
            onPressed: onCancel,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.emergency,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 34),
            ),
            child: Text(cancelLabel,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
