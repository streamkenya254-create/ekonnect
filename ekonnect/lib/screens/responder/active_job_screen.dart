import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../models/incident_model.dart';
import '../../providers/incident_provider.dart';
import '../../services/location_service.dart';
import '../../services/marker_helper.dart';
import '../../services/routes_service.dart';
import '../../services/voice_guidance_service.dart';
import '../../models/care_point_model.dart';
import '../../services/firestore_service.dart';
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
                  fontSize: 13, height: 1.4, color: AppColors.textMedium),
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
      await provider.resolveIncident();
      if (!mounted) return;
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
    final stepIdx = _steps.indexOf(incident.status).clamp(0, 3);
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
                              color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
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
                                fontSize: 13,
                                color: AppColors.textDark,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Turn-by-turn instruction banner (in-app navigation) ───────
          if (_navMode && _route != null)
            Positioned(
              top: topPad + 62,
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
                              color: AppColors.textMedium, fontSize: 12)),
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
              stepIdx: stepIdx,
              isExpanded: _isExpanded,
              distanceText: _route?.distanceText,
              durationText: _route?.durationText,
              onToggle: () => setState(() => _isExpanded = !_isExpanded),
              onAdvance: () => _advanceStatus(incident),
              onCancel: () => _cancelJob(incident),
              onCall: () async {
                final uri = Uri(scheme: 'tel', path: incident.userPhone);
                if (await canLaunchUrl(uri)) launchUrl(uri);
              },
              onChat: () => Navigator.pushNamed(context, AppRoutes.chat, arguments: {
                'incidentId': incident.id,
                'otherName': incident.userName,
                'otherPhone': incident.userPhone,
              }),
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

class _BottomPanel extends StatelessWidget {
  final IncidentModel incident;
  final Color color;
  final int stepIdx;
  final bool isExpanded;
  final String? distanceText;
  final String? durationText;
  final VoidCallback onToggle;
  final VoidCallback onAdvance;
  final VoidCallback onCancel;
  final VoidCallback onCall;
  final VoidCallback onChat;
  final VoidCallback onNavigate;

  static const _steps = [
    IncidentStatus.assigned,
    IncidentStatus.enRoute,
    IncidentStatus.arrived,
    IncidentStatus.resolved,
  ];
  static const _labels = ['Assigned', 'En Route', 'Arrived', 'Resolved'];
  static const _icons = [
    Icons.assignment_turned_in_outlined,
    Icons.directions_car_outlined,
    Icons.location_on_outlined,
    Icons.check_circle_outline,
  ];

  const _BottomPanel({
    required this.incident,
    required this.color,
    required this.stepIdx,
    required this.isExpanded,
    required this.distanceText,
    required this.durationText,
    required this.onToggle,
    required this.onAdvance,
    required this.onCancel,
    required this.onCall,
    required this.onChat,
    required this.onNavigate,
  });

  String get _nextLabel {
    final idx = _steps.indexOf(incident.status);
    if (idx < 0 || idx >= _labels.length - 1) return 'Done';
    return 'Mark: ${_labels[idx + 1]}';
  }

  Color get _nextColor {
    if (incident.status == IncidentStatus.arrived) return AppColors.success;
    return color;
  }

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
                // ── Stepper ──────────────────────────────────────────
                Row(
                  children: List.generate(_BottomPanel._steps.length, (i) {
                    final done = i <= p.stepIdx;
                    final active = i == p.stepIdx;
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
                                    done ? _BottomPanel._icons[i] : Icons.circle_outlined,
                                    size: active ? 17 : 13,
                                    color: done ? Colors.white : AppColors.textLight,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(_BottomPanel._labels[i],
                                    style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: active ? FontWeight.bold : FontWeight.normal,
                                        color: done ? p.color : AppColors.textLight),
                                    textAlign: TextAlign.center),
                              ],
                            ),
                          ),
                          if (i < _BottomPanel._steps.length - 1)
                            Expanded(
                              flex: 2,
                              child: Container(
                                height: 2,
                                margin: const EdgeInsets.only(bottom: 18),
                                decoration: BoxDecoration(
                                  color: i < p.stepIdx ? p.color : AppColors.divider,
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

                // ── Patient card ──────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: p.color.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: p.color.withValues(alpha: 0.18)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: p.color.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.person_pin_circle_outlined, color: p.color, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.incident.userName.isNotEmpty ? p.incident.userName : 'Unknown Patient',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textDark),
                            ),
                            Text(
                              p.incident.userPhone.isNotEmpty ? p.incident.userPhone : 'No phone',
                              style: TextStyle(color: p.color, fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                      // Quick call button
                      GestureDetector(
                        onTap: p.onCall,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.success,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.call, color: Colors.white, size: 18),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Chat
                      GestureDetector(
                        onTap: p.onChat,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: p.color.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.chat_bubble_outline, color: p.color, size: 18),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

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
                ] else ...[
                  ElevatedButton.icon(
                    onPressed: p.onAdvance,
                    icon: Icon(
                      p.incident.status == IncidentStatus.arrived
                          ? Icons.check_circle_outline
                          : Icons.arrow_forward_rounded,
                      size: 20,
                    ),
                    label: Text(p._nextLabel,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: p._nextColor,
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
                          fontSize: 13,
                          color: p.color),
                    ),
                    if (isEnRoute && hasEta)
                      Text('${p.durationText} · ${p.distanceText}',
                          style: const TextStyle(
                              color: AppColors.textMedium, fontSize: 11)),
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
                                fontSize: 12)),
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
                      color: p._nextColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(p._nextLabel,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
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
                    fontSize: 12,
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
                  color: Colors.white.withValues(alpha: 0.6), fontSize: 11),
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
