import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../models/incident_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/incident_provider.dart';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import '../../services/marker_helper.dart';
import '../../services/routes_service.dart';
import 'cancel_reason_sheet.dart';
import 'responder_profile_screen.dart';

class SOSWaitingScreen extends StatefulWidget {
  final String incidentType;
  final String incidentId;

  const SOSWaitingScreen({
    super.key,
    required this.incidentType,
    required this.incidentId,
  });

  @override
  State<SOSWaitingScreen> createState() => _SOSWaitingScreenState();
}

class _SOSWaitingScreenState extends State<SOSWaitingScreen>
    with SingleTickerProviderStateMixin {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  StreamSubscription? _responderSub;
  late final AnimationController _pulseCtrl;

  BitmapDescriptor? _userMarkerIcon;
  BitmapDescriptor? _responderMarkerIcon;
  int? _etaMinutes;

  // ── Live route from responder → user (Uber-style tracking) ────────────────
  RouteResult? _route;

  /// Rate-limits Routes API calls: the responder publishes GPS every 4s, but a
  /// road route only meaningfully changes after real movement.
  DateTime? _lastRouteFetch;
  LatLng? _lastRouteFrom;
  bool _fetchingRoute = false;
  static const _minRouteGap = Duration(seconds: 20);
  static const _minRouteMetres = 120.0;

  /// Camera is auto-fitted to the whole route once, then left alone so the
  /// user can pan without the map yanking back on every GPS tick.
  bool _didFitRoute = false;

  // True once the user themselves hit "Cancel SOS", so we can distinguish
  // a user-initiated cancel from a responder/system cancel.
  bool _userCancelled = false;

  // Fires after 10 min if still waiting for a responder.
  Timer? _broadcastTimer;

  /// Opens a private-routed call to the public network if the subscriber's own
  /// provider has not answered in time. Runs on the patient's phone because
  /// they are the one waiting and their app is the one that is definitely open.
  Timer? _privateWindowTimer;

  // Guards against showing multiple dialogs simultaneously.
  bool _dialogShown = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final provider = context.read<IncidentProvider>();
    provider.streamActiveIncident(widget.incidentId);
    provider.addListener(_onIncidentUpdate);

    // Pre-build user marker
    final incident = provider.activeIncident;
    final userName = incident?.userName ?? '';
    final initials = _initials(userName);
    // The patient's own face, so the map shows who is where rather than
    // two anonymous glyphs.
    final me = context.read<AuthProvider>().user;
    _userMarkerIcon = await MarkerHelper.photoPin(
      cacheKey: 'me_${me?.uid ?? ''}_${(me?.profilePhoto ?? '').length}',
      ringColor: AppColors.primary,
      photo: _photoBytes(me?.profilePhoto),
      initials: initials,
    );

    if (mounted && incident != null) {
      _setUserMarker(
          LatLng(incident.userLat, incident.userLng), initials);
    }

    // Start 10-minute countdown only while waiting for a responder.
    if (incident == null || incident.isPending) {
      _broadcastTimer = Timer(const Duration(minutes: 10), () {
        if (mounted && !_dialogShown) _showTimeoutDialog();
      });
    }

    // Private exclusivity: their provider gets first refusal, then everyone.
    if (incident != null &&
        incident.isPending &&
        incident.routingScope == ResponderVisibility.private) {
      _privateWindowTimer = Timer(FirestoreService.privateExclusivity, () async {
        final opened =
            await FirestoreService.openPrivateCallToPublic(widget.incidentId);
        if (!mounted || !opened) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Still looking — your call has been opened to all '
              'nearby responders.'),
          duration: Duration(seconds: 5),
        ));
      });
    }
  }

  void _onIncidentUpdate() {
    if (!mounted) return;
    final incident = context.read<IncidentProvider>().activeIncident;

    if (incident?.assignedTo != null && _responderSub == null) {
      _pulseCtrl.stop();
      _broadcastTimer?.cancel();
    _privateWindowTimer?.cancel(); // responder found — timeout no longer needed
      _startResponderTracking(incident!);
    }

    // Position published on the incident itself. This is the path that works
    // without a Realtime Database instance, and it arrives on the stream we
    // are already watching — so no extra listener is needed.
    if (incident != null && incident.hasResponderLocation) {
      _onResponderPosition(
        LatLng(incident.responderLat!, incident.responderLng!),
        incident.responderHeading ?? 0,
        incident,
      );
    }

    if (_dialogShown) return;

    if (incident?.status == IncidentStatus.resolved) {
      _dialogShown = true;
      _showRatingDialog(incident!.id);
    } else if (incident?.status == IncidentStatus.cancelled) {
      _dialogShown = true;

      // Who ended it is read from the incident, not from screen state.
      //
      // This used to test `_userCancelled`, a flag living only in this State
      // object. Re-entering the screen after cancelling (via the home banner,
      // or any rebuild) created a fresh State where the flag was false, so the
      // app concluded a *responder* had cancelled and silently re-broadcast a
      // brand-new emergency — which is why a cancelled SOS reappeared as a new
      // call on the responder side.
      final endedByResponder = incident!.cancelledBy == 'responder';
      if (endedByResponder) {
        _showRespCancelledDialog();
      }
      // Cancelled by this user (or by the system): nothing to ask, just leave.
      else if (mounted && !_userCancelled) {
        Navigator.of(context).pushReplacementNamed(AppRoutes.userHome);
      }
    }
  }

  void _startResponderTracking(IncidentModel incident) {
    // Realtime Database path. Optional — if no RTDB instance exists this never
    // emits, and the incident-document path in _onIncidentUpdate carries the
    // position instead.
    _responderSub = LocationService.streamResponderLocationWithHeading(
            incident.assignedTo!)
        .listen((data) {
      if (data == null || !mounted) return;
      _onResponderPosition(
        LatLng(data['lat']!, data['lng']!),
        data['heading'] ?? 0.0,
        incident,
      );
    }, onError: (_) {
      // No RTDB configured; harmless.
    });
  }

  /// Single place that turns a responder position into map + card state,
  /// whichever channel delivered it.
  Future<void> _onResponderPosition(
      LatLng latlng, double heading, IncidentModel incident) async {
    final responderInitials = _initials(incident.assignedToName ?? '');
    final dest = LatLng(incident.userLat, incident.userLng);

    // Straight-line ETA immediately, so the card is never blank while the road
    // route is in flight. The route result overwrites it when it lands.
    if (_route == null) {
      final distM = _haversineMeters(
          latlng.latitude, latlng.longitude, dest.latitude, dest.longitude);
      // 40 km/h average emergency response speed
      final eta = (distM / (40000.0 / 3600) / 60).ceil().clamp(1, 99);
      if (mounted) setState(() => _etaMinutes = eta);
    }

    _maybeFetchRoute(latlng, dest);

    // Their face, not a vehicle glyph. The heading arrow told the patient
    // which way the van was pointing, which is not a thing they can act on;
    // knowing who is coming is.
    if (incident.assignedTo != null) {
      await _loadResponderPhoto(incident.assignedTo!);
    }
    _responderMarkerIcon = await MarkerHelper.photoPin(
      cacheKey: 'crew_${incident.assignedTo ?? ''}_${(_responderPhoto ?? '').length}',
      ringColor: IncidentType.color(incident.type),
      photo: _photoBytes(_responderPhoto),
      initials: responderInitials,
    );

    if (!mounted) return;
    setState(() {
      _markers.removeWhere((m) => m.markerId.value == 'responder');
      _markers.add(Marker(
        markerId: const MarkerId('responder'),
        position: latlng,
        icon: _responderMarkerIcon!,
        infoWindow: InfoWindow(
          title: incident.assignedToName ?? 'Responder',
          snippet: 'On the way',
        ),
        anchor: const Offset(0.5, 0.85),
        zIndexInt: 3,
      ));
    });
  }

  /// Fetches the road route responder → user, throttled by time and distance.
  Future<void> _maybeFetchRoute(LatLng from, LatLng to) async {
    if (_fetchingRoute) return;

    final elapsed = _lastRouteFetch == null
        ? _minRouteGap
        : DateTime.now().difference(_lastRouteFetch!);
    final moved = _lastRouteFrom == null
        ? _minRouteMetres
        : RoutesService.metresBetween(_lastRouteFrom!, from);

    final worthFetching =
        (elapsed >= _minRouteGap && moved >= 25) || moved >= _minRouteMetres;
    if (!worthFetching) return;

    _fetchingRoute = true;
    try {
      final route = await RoutesService.compute(origin: from, destination: to);
      if (!mounted) return;
      setState(() {
        _route = route;
        _etaMinutes = route.etaMinutes;
      });
      _lastRouteFetch = DateTime.now();
      _lastRouteFrom = from;

      // Frame the whole journey once; afterwards leave the camera to the user.
      if (!_didFitRoute && route.points.length > 1) {
        _didFitRoute = true;
        _fitRoute(route.points);
      }
    } finally {
      _fetchingRoute = false;
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
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(minLat - 0.004, minLng - 0.004),
        northeast: LatLng(maxLat + 0.004, maxLng + 0.004),
      ),
      70,
    ));
  }

  double _haversineMeters(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final phi1 = lat1 * pi / 180;
    final phi2 = lat2 * pi / 180;
    final dPhi = (lat2 - lat1) * pi / 180;
    final dLambda = (lng2 - lng1) * pi / 180;
    final a = sin(dPhi / 2) * sin(dPhi / 2) +
        cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  void _setUserMarker(LatLng pos, String initials) {
    if (_userMarkerIcon == null) return;
    setState(() {
      _markers.removeWhere((m) => m.markerId.value == 'user');
      _markers.add(Marker(
        markerId: const MarkerId('user'),
        position: pos,
        icon: _userMarkerIcon!,
        infoWindow: const InfoWindow(title: 'Your Location'),
        anchor: const Offset(0.5, 0.85),
        zIndexInt: 2,
      ));
    });
  }

  /// The responder's path to the user. A straight-line estimate renders thin
  /// and translucent so it never reads as a real road route.
  Set<Polyline> _buildPolylines() {
    final route = _route;
    if (route == null || route.isEmpty) return {};
    return {
      Polyline(
        polylineId: const PolylineId('responder_route'),
        points: route.points,
        color: route.isEstimate
            ? AppColors.primary.withValues(alpha: 0.4)
            : AppColors.primary,
        width: route.isEstimate ? 3 : 6,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
      ),
    };
  }

  Future<void> _callResponder(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) launchUrl(uri);
  }

  /// Cancelling always goes through a reason. Requiring one both slows down an
  /// accidental tap on a live emergency and records *why* the SOS ended, which
  /// a bare yes/no confirm threw away.
  Future<void> _cancelSOS() async {
    final incident = context.read<IncidentProvider>().activeIncident;
    final hasResponder = incident?.assignedTo != null;

    final outcome = await showModalBottomSheet<CancelOutcome>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CancelReasonSheet(hasResponder: hasResponder),
    );

    if (outcome == null || !mounted) return;

    _userCancelled = true;
    _broadcastTimer?.cancel();
    _privateWindowTimer?.cancel();
    final provider = context.read<IncidentProvider>();
    final nav = Navigator.of(context);
    await provider.cancelActiveIncident(
      reason: outcome.reason,
      note: outcome.note,
    );
    if (!mounted) return;
    // Home is where the emergency-type grid lives, so "wrong type" lands in the
    // right place too.
    nav.pushReplacementNamed(AppRoutes.userHome);
  }

  // Shown when the 10-minute broadcast timer fires with no responder.
  void _showTimeoutDialog() {
    if (!mounted || _dialogShown) return;
    _dialogShown = true;
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Still need help?'),
        content: const Text(
            'No responder has been assigned after 10 minutes. Would you like to broadcast again?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _userCancelled = true;
              context
                  .read<IncidentProvider>()
                  .cancelActiveIncident(reason: CancelReasons.noResponder)
                  .then((_) {
                if (mounted) {
                  Navigator.pushReplacementNamed(context, AppRoutes.userHome);
                }
              });
            },
            child: const Text('No, Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              _dialogShown = false;
              _rebroadcast();
            },
            child: const Text('Yes, Try Again'),
          ),
        ],
      ),
    );
  }

  // Shown when the responder (not the user) cancels the incident.
  void _showRespCancelledDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Responder Unavailable'),
        content: const Text(
            'The assigned responder had to cancel. We will broadcast your SOS again immediately.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _userCancelled = true;
              context
                  .read<IncidentProvider>()
                  .cancelActiveIncident(
                      reason: CancelReasons.responderCancelled)
                  .then((_) {
                if (mounted) {
                  Navigator.pushReplacementNamed(context, AppRoutes.userHome);
                }
              });
            },
            child: const Text('Cancel SOS'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              _rebroadcast();
            },
            child: const Text('Re-broadcast'),
          ),
        ],
      ),
    );
  }

  // Shown after successful resolution — user rates the response.
  void _showRatingDialog(String incidentId) {
    if (!mounted) return;
    int selected = 5;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDs) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Rate the Response'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('The responder has marked this incident resolved. How was the response?'),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  5,
                  (i) => GestureDetector(
                    onTap: () => setDs(() => selected = i + 1),
                    child: Icon(
                      i < selected ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: Colors.amber,
                      size: 36,
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                if (mounted) {
                  Navigator.pushReplacementNamed(context, AppRoutes.userHome);
                }
              },
              child: const Text('Skip'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white),
              onPressed: () async {
                await FirestoreService.rateIncident(
                    incidentId: incidentId, rating: selected);
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  Navigator.pushReplacementNamed(context, AppRoutes.userHome);
                }
              },
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }

  // Cancel the current SOS and re-create a new one with the same type.
  Future<void> _rebroadcast() async {
    if (!mounted) return;
    final provider = context.read<IncidentProvider>();
    final nav = Navigator.of(context);
    // Clear the cancelled incident first. Flagged as a re-broadcast so it is
    // not counted as the user abandoning the emergency.
    await provider.cancelActiveIncident(reason: CancelReasons.rebroadcast);
    if (!mounted) return;
    // Create a fresh SOS
    final newId = await provider.createSOS(widget.incidentType);
    if (newId != null && mounted) {
      nav.pushReplacementNamed(AppRoutes.sosWaiting, arguments: {
        'type': widget.incidentType,
        'incidentId': newId,
      });
    } else if (mounted) {
      nav.pushReplacementNamed(AppRoutes.userHome);
    }
  }

  String _initials(String name) {
    return name
        .split(' ')
        .map((w) => w.isNotEmpty ? w[0] : '')
        .take(2)
        .join()
        .toUpperCase();
  }

  /// The crew's photo, for the pin and the collapsed card. Fetched once per
  /// assignment: the incident carries their name and number, never a picture.
  String? _responderPhoto;
  String? _photoFetchedFor;

  /// How far the status sheet is open, 0..1.
  ///
  /// Watching the ambulance approach is the point of this screen, and a fixed
  /// panel covered most of the map. The sheet is the patient's control over
  /// that trade: drag down for map, up for detail.
  final ValueNotifier<double> _sheetExtent = ValueNotifier<double>(0.55);

  Future<void> _loadResponderPhoto(String uid) async {
    if (_photoFetchedFor == uid) return;
    _photoFetchedFor = uid;
    try {
      final u = await FirestoreService.getUser(uid);
      if (mounted && (u?.profilePhoto ?? '').isNotEmpty) {
        setState(() => _responderPhoto = u!.profilePhoto);
      }
    } catch (_) {/* initials remain, which is enough */}
  }

  /// Photos are stored as `data:image/jpeg;base64,…` on the user document.
  static Uint8List? _photoBytes(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return base64Decode(raw.contains(',') ? raw.split(',').last : raw);
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    context.read<IncidentProvider>().removeListener(_onIncidentUpdate);
    _responderSub?.cancel();
    _broadcastTimer?.cancel();
    _privateWindowTimer?.cancel();
    _sheetExtent.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final incident = context.watch<IncidentProvider>().activeIncident;
    final color = IncidentType.color(widget.incidentType);
    final isWaiting = incident?.assignedTo == null;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: color,
        title: Row(
          children: [
            Icon(IncidentType.icon(widget.incidentType),
                color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(IncidentType.label(widget.incidentType)),
          ],
        ),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.call, color: Colors.white),
            tooltip: 'Call 999',
            onPressed: () async {
              final uri = Uri(scheme: 'tel', path: '999');
              if (await canLaunchUrl(uri)) launchUrl(uri);
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // Map
          Positioned.fill(
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: incident != null
                        ? LatLng(incident.userLat, incident.userLng)
                        : const LatLng(-1.286389, 36.817223),
                    zoom: 15,
                  ),
                  markers: _markers,
                  polylines: _buildPolylines(),
                  myLocationEnabled: false,
                  zoomControlsEnabled: false,
                  mapType: MapType.normal,
                  onMapCreated: (c) {
                    _mapController = c;
                    if (incident != null) {
                      _setUserMarker(
                        LatLng(incident.userLat, incident.userLng),
                        _initials(incident.userName),
                      );
                    }
                  },
                ),
                // Pulse while waiting
                if (isWaiting)
                  Positioned(
                    top: 12,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: AnimatedBuilder(
                        animation: _pulseCtrl,
                        builder: (_, _) => _WaitingBanner(
                            t: _pulseCtrl.value, color: color),
                      ),
                    ),
                  ),
                // Responder on-the-way banner
                if (!isWaiting && incident != null)
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: _MovingBanner(
                      incident: incident,
                      color: color,
                      eta: _etaMinutes,
                    ),
                  ),
              ],
            ),
          ),

          // ── Status sheet ────────────────────────────────────────────
          //
          // Drag it down and it hands the map back, keeping only what
          // changes: the crew's face, their name, the ETA. Drag it up and
          // the detail returns. The map underneath is never rebuilt, so the
          // camera and the route survive every drag.
          NotificationListener<DraggableScrollableNotification>(
            onNotification: (n) {
              _sheetExtent.value = n.extent;
              return false;
            },
            child: DraggableScrollableSheet(
              initialChildSize: 0.55,
              minChildSize: 0.16,
              maxChildSize: 0.92,
              snap: true,
              snapSizes: const [0.16, 0.55, 0.92],
              builder: (context, scrollController) {
                return ValueListenableBuilder<double>(
                  valueListenable: _sheetExtent,
                  builder: (context, extent, _) {
                    // Three states, not a continuum: a patient watching an
                    // ambulance should not have to hold the sheet at an exact
                    // height to read something.
                    final peek = extent < 0.28;
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(
                            top: Radius.circular(28 * (1 - ((extent - 0.8) / 0.12).clamp(0.0, 1.0)))),
                        boxShadow: const [
                          BoxShadow(
                              color: Colors.black12,
                              blurRadius: 20,
                              offset: Offset(0, -4))
                        ],
                      ),
                      child: ListView(
                        controller: scrollController,
                        padding: EdgeInsets.fromLTRB(20, 10, 20, peek ? 10 : 28),
                        children: [
                          Center(
                            child: Container(
                              width: 44,
                              height: 5,
                              margin: const EdgeInsets.only(bottom: 14),
                              decoration: BoxDecoration(
                                color: AppColors.divider,
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                          // Waiting has its own peek tier. Without one, the
                          // full panel was rendered into a 0.16-high sheet and
                          // clipped mid-word — a broken screen at exactly the
                          // moment the caller is watching the map.
                          if (peek && isWaiting)
                            _PeekWaiting(
                              color: color,
                              t: _pulseCtrl,
                              onCall999: () async {
                                final uri = Uri(scheme: 'tel', path: '999');
                                if (await canLaunchUrl(uri)) launchUrl(uri);
                              },
                              onCancel: _cancelSOS,
                            )
                          else if (peek && incident != null)
                            _PeekRow(
                              incident: incident,
                              color: color,
                              eta: _etaMinutes,
                              photo: _responderPhoto,
                              onOpenProfile: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ResponderProfileScreen(
                                      incident: incident),
                                ),
                              ),
                              onCall: () =>
                                  _callResponder(incident.assignedToPhone ?? ''),
                            )
                          else ...[
                // Status pill
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isWaiting)
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: color),
                        )
                      else
                        Icon(Icons.check_circle, size: 14, color: color),
                      const SizedBox(width: 8),
                      Text(
                        incident != null
                            ? IncidentStatus.label(incident.status)
                            : 'Sending SOS…',
                        style: TextStyle(
                            color: color, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                if (!isWaiting && incident != null) ...[
                  // Trip strip: distance · travel time · arrival clock time
                  if (_route != null) ...[
                    _TripStrip(route: _route!, color: color),
                    const SizedBox(height: 12),
                  ],
                  // Responder card
                  _ResponderCard(
                    incident: incident,
                    color: color,
                    eta: _etaMinutes,
                    photo: _responderPhoto,
                    onOpenProfile: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ResponderProfileScreen(incident: incident),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Call + Chat
                  Row(
                    children: [
                      Expanded(
                        child: _ActionBtn(
                          icon: Icons.call,
                          label: 'Call',
                          color: AppColors.success,
                          onTap: () => _callResponder(
                              incident.assignedToPhone ?? ''),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ActionBtn(
                          icon: Icons.chat_bubble_outline,
                          label: 'Chat',
                          color: AppColors.secondary,
                          onTap: () => Navigator.pushNamed(
                            context,
                            AppRoutes.chat,
                            arguments: {
                              'incidentId': widget.incidentId,
                              'otherName': incident.assignedToName,
                              'otherPhone': incident.assignedToPhone,
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Single cancel entry point. "I'm OK" used to sit here as its
                  // own button; it is now one of the reasons inside the cancel
                  // sheet, so there is one way to end an SOS instead of two.
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.cancel_outlined, size: 17),
                      label: const Text('Cancel Emergency'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.emergency,
                        side: const BorderSide(color: AppColors.emergency),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _cancelSOS,
                    ),
                  ),
                ] else ...[
                  _ActionBtn(
                    icon: Icons.call,
                    label: 'Call 999 While Waiting',
                    color: AppColors.emergency,
                    onTap: () async {
                      final uri = Uri(scheme: 'tel', path: '999');
                      if (await canLaunchUrl(uri)) launchUrl(uri);
                    },
                    outlined: true,
                  ),
                  const SizedBox(height: 12),
                  // Cancel is always available while waiting
                  TextButton(
                    onPressed: _cancelSOS,
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.textLight),
                    child: const Text('Cancel SOS'),
                  ),
                ],
                          ],
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _MovingBanner extends StatelessWidget {
  final IncidentModel incident;
  final Color color;
  final int? eta;
  const _MovingBanner({required this.incident, required this.color, this.eta});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_responderIcon(incident.assignedToRole), color: color, size: 18),
          const SizedBox(width: 8),
          Text(
            '${incident.assignedToName ?? "Responder"} is on the way',
            style: TextStyle(
                color: color, fontWeight: FontWeight.w600, fontSize: 14),
          ),
          if (eta != null) ...[
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '~$eta min',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static IconData _responderIcon(String? role) {
    switch (role) {
      case AppRoles.practitioner:
        return Icons.medical_services;
      default:
        return Icons.local_hospital_rounded;
    }
  }
}

class _ResponderCard extends StatelessWidget {
  final IncidentModel incident;
  final Color color;
  final int? eta;
  final String? photo;
  final VoidCallback onOpenProfile;

  const _ResponderCard({
    required this.incident,
    required this.color,
    required this.onOpenProfile,
    this.eta,
    this.photo,
  });

  static IconData _roleIcon(String? role) {
    switch (role) {
      case AppRoles.practitioner:
        return Icons.medical_services;
      default:
        return Icons.local_hospital_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = incident.assignedToName ?? 'Responder';
    final role = incident.assignedToRole;
    final specialization = incident.assignedToSpecialization;
    final licenseNumber = incident.assignedToLicenseNumber;
    final vehicleNumber = incident.assignedToVehicleNumber;
    final facility = incident.assignedToFacilityName;
    final phone = incident.assignedToPhone ?? '';
    final roleLabel = role != null
        ? AppRoles.displayLabel(role)
        : 'Emergency Responder';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row: avatar / name / live + ETA ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Role icon avatar
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  boxShadow: [
                    BoxShadow(
                        color: color.withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 3))
                  ],
                ),
                child: Icon(_roleIcon(role), color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: AppColors.textDark),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              roleLabel,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: color,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Who they answer to. "Ben, ambulance driver" is a person;
                    // "Ben, ambulance driver, Oasis Hospital" is someone
                    // accountable to an institution — which is the whole point
                    // of a verified network.
                    if (facility != null && facility.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Icon(Icons.apartment_rounded,
                              size: 13, color: AppColors.textLight),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              facility,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textLight),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              // Live indicator + ETA badge
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.success),
                      ),
                      const SizedBox(width: 4),
                      const Text('live',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.success,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                  if (eta != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                              color: color.withValues(alpha: 0.4),
                              blurRadius: 6,
                              offset: const Offset(0, 2))
                        ],
                      ),
                      child: Column(
                        children: [
                          Text(
                            '~$eta min',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold),
                          ),
                          const Text(
                            'ETA',
                            style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),

          // ── Detail rows ────────────────────────────
          if (specialization != null && specialization.isNotEmpty ||
              licenseNumber != null && licenseNumber.isNotEmpty ||
              vehicleNumber != null && vehicleNumber.isNotEmpty ||
              phone.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.divider),
            const SizedBox(height: 10),
          ],
          if (specialization != null && specialization.isNotEmpty)
            _DetailRow(
                icon: Icons.science_outlined, label: specialization),
          if (licenseNumber != null && licenseNumber.isNotEmpty)
            _DetailRow(
                icon: Icons.badge_outlined,
                label: 'License: $licenseNumber'),
          if (vehicleNumber != null && vehicleNumber.isNotEmpty)
            _DetailRow(
                icon: Icons.directions_car_outlined,
                label: 'Vehicle: $vehicleNumber'),
          if (phone.isNotEmpty)
            _DetailRow(
                icon: Icons.phone_outlined,
                label: phone,
                highlight: true,
                highlightColor: color),
        ],
      ),
    );
  }
}

/// The crew's photograph, falling back to their initials.
class _Face extends StatelessWidget {
  final String? photo;
  final String name;
  final Color color;
  final double size;
  const _Face({
    required this.photo,
    required this.name,
    required this.color,
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) {
    final bytes = _SOSWaitingScreenState._photoBytes(photo);
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(RegExp(r's+')).take(2)
            .map((w) => w[0].toUpperCase()).join();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        image: bytes == null
            ? null
            : DecorationImage(image: MemoryImage(bytes), fit: BoxFit.cover),
      ),
      child: bytes != null
          ? null
          : Center(
              child: Text(initials,
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: size * 0.34)),
            ),
    );
  }
}

/// The sheet at its smallest: who is coming, how far off, and one tap each
/// to their profile or their phone. Everything else is a drag away.
/// The sheet at its smallest while nobody has answered yet.
///
/// One line of state and two round actions. Icons alone are enough here: by
/// the time the sheet is collapsed the caller has already read the labels
/// full-size, and what they need back is the map, not the wording.
class _PeekWaiting extends StatelessWidget {
  final Color color;
  final Animation<double> t;
  final VoidCallback onCall999;
  final VoidCallback onCancel;

  const _PeekWaiting({
    required this.color,
    required this.t,
    required this.onCall999,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // The same pulse the map banner uses, so the two read as one state.
        AnimatedBuilder(
          animation: t,
          builder: (_, _) {
            final scale = 0.7 + 0.3 * (0.5 + 0.5 * sin(t.value * 2 * pi));
            return Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              child: Container(
                width: 16 * scale,
                height: 16 * scale,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            );
          },
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Waiting for a responder',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.cardTitle),
              const SizedBox(height: 2),
              const Text('Stay where you are',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.meta),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _PeekAction(
          icon: Icons.call_rounded,
          tooltip: 'Call 999',
          background: AppColors.accent,
          foreground: Colors.white,
          onTap: onCall999,
        ),
        const SizedBox(width: 8),
        _PeekAction(
          icon: Icons.close_rounded,
          tooltip: 'Cancel SOS',
          background: AppColors.surfaceAlt,
          foreground: AppColors.textMedium,
          onTap: onCancel,
        ),
      ],
    );
  }
}

/// A round icon button sized for a thumb, with the label kept as a tooltip so
/// the meaning is still reachable.
class _PeekAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  const _PeekAction({
    required this.icon,
    required this.tooltip,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(color: background, shape: BoxShape.circle),
          child: Icon(icon, color: foreground, size: 21),
        ),
      ),
    );
  }
}

class _PeekRow extends StatelessWidget {
  final IncidentModel incident;
  final Color color;
  final int? eta;
  final String? photo;
  final VoidCallback onOpenProfile;
  final VoidCallback onCall;

  const _PeekRow({
    required this.incident,
    required this.color,
    required this.onOpenProfile,
    required this.onCall,
    this.eta,
    this.photo,
  });

  @override
  Widget build(BuildContext context) {
    final name = incident.assignedToName ?? 'Responder';
    return Row(
      children: [
        GestureDetector(
          onTap: onOpenProfile,
          child: _Face(photo: photo, name: name, color: color, size: 48),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: GestureDetector(
            onTap: onOpenProfile,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.cardTitle),
                const SizedBox(height: 2),
                Text(
                    eta != null
                        ? '~ min away'
                        : IncidentStatus.label(incident.status),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.meta),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: onCall,
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: const Icon(Icons.call_rounded, color: Colors.white, size: 21),
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool highlight;
  final Color? highlightColor;

  const _DetailRow({
    required this.icon,
    required this.label,
    this.highlight = false,
    this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = highlight
        ? (highlightColor ?? AppColors.primary)
        : AppColors.textMedium;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                  fontSize: 14,
                  color: highlight ? c : AppColors.textDark,
                  fontWeight:
                      highlight ? FontWeight.w600 : FontWeight.normal),
            ),
          ),
        ],
      ),
    );
  }
}

class _WaitingBanner extends StatelessWidget {
  final double t;
  final Color color;
  const _WaitingBanner({required this.t, required this.color});

  @override
  Widget build(BuildContext context) {
    final opacity = 0.6 + 0.4 * (t < 0.5 ? t * 2 : (1 - t) * 2);
    return Opacity(
      opacity: opacity,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 8),
            Text('Alerting nearby responders…',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool outlined;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    if (outlined) {
      return OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18, color: color),
        label: Text(label, style: TextStyle(color: color)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

// ── Trip strip ────────────────────────────────────────────────────────────────

/// Uber-style journey summary: how far the responder is, how long they'll take,
/// and the clock time they should arrive.
class _TripStrip extends StatelessWidget {
  final RouteResult route;
  final Color color;

  const _TripStrip({required this.route, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _cell(
                icon: Icons.route_outlined,
                label: 'Distance',
                value: route.distanceText,
                color: color,
              ),
              _divider(),
              _cell(
                icon: Icons.timer_outlined,
                label: 'Travel time',
                value: route.durationText,
                color: color,
                emphasise: true,
              ),
              _divider(),
              _cell(
                icon: Icons.schedule_rounded,
                label: 'Arrives',
                value: route.arrivalText(),
                color: color,
              ),
            ],
          ),
          // Never let an approximation pass for a real routed ETA.
          if (route.isEstimate) ...[
            const SizedBox(height: 10),
            Text(
              'Straight-line estimate — live routing unavailable',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.textMedium.withValues(alpha: 0.9),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 34,
        color: AppColors.divider.withValues(alpha: 0.6),
      );

  Widget _cell({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    bool emphasise = false,
  }) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              fontSize: emphasise ? 17 : 15,
              fontWeight: FontWeight.bold,
              color: emphasise ? color : AppColors.textDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textMedium),
          ),
        ],
      ),
    );
  }
}
