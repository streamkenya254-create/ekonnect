import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_assets.dart';
import '../../core/constants.dart';
import '../../models/incident_model.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import 'complete_profile_sheet.dart';
import 'voice_report_sheet.dart';
import '../../providers/incident_provider.dart';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import '../../services/marker_helper.dart';
import '../../widgets/app_drawer.dart';

class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key});

  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends State<UserHomeScreen> {
  GoogleMapController? _mapController;
  Position? _position;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Tracks how far the home sheet is expanded (0..1) so the top padding and
  // corner radius can adapt as it covers the map.
  final ValueNotifier<double> _sheetExtent = ValueNotifier<double>(0.58);

  // Live-responder dot colours (functional map coding — outside the brand
  // palette on purpose so responder types are instantly distinguishable).
  static const _ambulanceColor = Color(0xFFE53935); // red
  static const _practitionerColor = Color(0xFF2E7D32); // green
  BitmapDescriptor? _dotAmbulance;
  BitmapDescriptor? _dotPractitioner;

  static const _sosTypes = [
    {'type': IncidentType.medical,  'label': 'Medical',  'asset': AppAssets.medical},
    {'type': IncidentType.fire,     'label': 'Fire',     'asset': AppAssets.fire},
    {'type': IncidentType.flood,    'label': 'Flood',    'asset': AppAssets.flood},
    {'type': IncidentType.security, 'label': 'Security', 'asset': AppAssets.security},
  ];

  @override
  void initState() {
    super.initState();
    _loadLocation();
    _buildDots();
  }

  Future<void> _buildDots() async {
    final amb = await MarkerHelper.dot('ambulance', _ambulanceColor);
    final prac = await MarkerHelper.dot('practitioner', _practitionerColor);
    if (!mounted) return;
    setState(() {
      _dotAmbulance = amb;
      _dotPractitioner = prac;
    });
  }

  @override
  void dispose() {
    _sheetExtent.dispose();
    super.dispose();
  }

  Future<void> _loadLocation() async {
    final pos = await LocationService.getCurrentPosition();
    if (!mounted) return;
    setState(() => _position = pos);
    if (pos != null) {
      _mapController?.animateCamera(
        CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)),
      );
    }
  }

  Future<void> _call999() async {
    final uri = Uri(scheme: 'tel', path: '999');
    if (await canLaunchUrl(uri)) launchUrl(uri);
  }

  Future<void> _openProfileSheet() async {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CompleteProfileSheet(),
    );
    // AuthProvider streams the user doc, so the prompt updates itself once
    // saved — nothing to refresh here.
  }

  /// Opens spoken reporting. The sheet returns a category (AI-derived or picked
  /// by hand) plus the triage notes, which are then sent as a normal SOS —
  /// so voice reporting shares every guard the manual path already has.
  Future<void> _startVoiceReport() async {
    final result = await showModalBottomSheet<VoiceReportResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const VoiceReportSheet(),
    );
    if (result == null || !mounted) return;
    await _triggerSOS(result.type, skipConfirm: true, notes: result.notes);
  }

  Future<void> _triggerSOS(String type,
      {bool skipConfirm = false, String? notes}) async {
    final provider = context.read<IncidentProvider>();
    final nav = Navigator.of(context);

    final existing = provider.activeIncident;
    if (existing != null && !existing.isClosed) {
      if (!mounted) return;
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.accent),
            const SizedBox(width: 8),
            const Text('Active Emergency'),
          ]),
          content: RichText(
            text: TextSpan(
              style: const TextStyle(color: AppColors.textDark, fontSize: 14, height: 1.5),
              children: [
                const TextSpan(text: 'You already have an active '),
                TextSpan(
                  text: IncidentType.label(existing.type),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                ),
                const TextSpan(text: ' emergency.\n\nWhat would you like to do?'),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('Cancel')),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(ctx, 'view'),
              icon: const Icon(Icons.visibility_outlined, size: 16),
              label: const Text('View Current'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, 'replace'),
              icon: Icon(IncidentType.icon(type), size: 16),
              label: const Text('Replace'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (choice == 'view') {
        nav.pushNamed(AppRoutes.sosWaiting, arguments: {'type': existing.type, 'incidentId': existing.id});
        return;
      }
      if (choice == 'replace') {
        await provider.cancelActiveIncident();
        if (!mounted) return;
      } else {
        return;
      }
    }

    // When triggered by the hold-to-send button, the deliberate 1-second hold
    // IS the confirmation, so we skip the extra dialog. Tap-based callers still
    // get the safety confirm.
    if (!skipConfirm) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(children: [
            Icon(IncidentType.icon(type), color: AppColors.primary),
            const SizedBox(width: 8),
            Text(IncidentType.label(type)),
          ]),
          content: const Text(
              'This will alert the nearest emergency responders with your GPS location.\n\nOnly use in a real emergency.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
              child: const Text('SEND SOS'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
    }

    final id = await provider.createSOS(type, notes: notes);
    if (!mounted) return;
    if (id != null) {
      nav.pushNamed(AppRoutes.sosWaiting, arguments: {'type': type, 'incidentId': id});
      return;
    }

    // An SOS is already in flight. That is not a failure — take the user to it
    // rather than telling them to call 999, which the generic branch below did.
    final error = provider.error ?? '';
    if (error.startsWith('ACTIVE_INCIDENT:')) {
      final parts = error.split(':');
      if (parts.length >= 3) {
        nav.pushNamed(AppRoutes.sosWaiting,
            arguments: {'type': parts[2], 'incidentId': parts[1]});
        return;
      }
    }

    // A location failure is recoverable — offer a retry rather than dead-ending
    // on a snackbar. Everything else is a hard failure, so 999 is the action.
    final isLocation = error.startsWith('LOCATION:');
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(isLocation
              ? error.substring('LOCATION:'.length)
              : (error.isEmpty
                  ? 'Could not send SOS. Call 999 immediately.'
                  : error)),
          backgroundColor: AppColors.accent,
          duration: const Duration(seconds: 10),
          action: isLocation
              ? SnackBarAction(
                  label: 'RETRY',
                  textColor: Colors.white,
                  onPressed: () => _triggerSOS(type,
                      skipConfirm: true, notes: notes),
                )
              : SnackBarAction(
                  label: 'CALL 999',
                  textColor: Colors.white,
                  onPressed: _call999),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final provider = context.watch<IncidentProvider>();
    final activeIncident = provider.activeIncident;
    final hasActive = activeIncident != null && !activeIncident.isClosed;
    final firstName = auth.user?.name.split(' ').first ?? 'there';

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.primaryDark,
      drawer: _buildDrawer(auth),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        switchInCurve: Curves.easeOutCubic,
        child: hasActive
            ? _buildTracking(activeIncident)
            : _buildIdle(firstName),
      ),
    );
  }

  Widget _buildDrawer(AuthProvider auth) {
    final role = auth.user?.role ?? AppRoles.user;
    final isResponder = AppRoles.isResponder(role);
    final shortRole = role == AppRoles.ambulance ? 'Ambulance' : 'Responder';
    return AppDrawer(
      name: auth.user?.name ?? 'User',
      subtitle: isResponder ? shortRole : 'Emergency User',
      subtitleIcon: Icons.emergency_rounded,
      children: [
        DrawerTile(
          icon: Icons.home_rounded,
          label: 'Home',
          onTap: () => Navigator.pop(context),
        ),
        DrawerTile(
          icon: Icons.smart_toy_rounded,
          label: 'AI Assistant',
          badge: 'NEW',
          onTap: () {
            Navigator.pop(context);
            Navigator.pushNamed(context, AppRoutes.aiChat);
          },
        ),
        DrawerTile(
          icon: Icons.history_rounded,
          label: 'History',
          onTap: () {
            Navigator.pop(context);
            Navigator.pushNamed(context, AppRoutes.incidentHistory);
          },
        ),
        DrawerTile(
          icon: Icons.play_circle_rounded,
          label: 'Tutorial',
          onTap: () {
            Navigator.pop(context);
            Navigator.pushNamed(context, AppRoutes.tutorial);
          },
        ),
        const DrawerSection('Account'),
        DrawerTile(
          icon: Icons.person_rounded,
          label: 'Profile',
          onTap: () {
            Navigator.pop(context);
            Navigator.pushNamed(context, AppRoutes.profile);
          },
        ),
        DrawerTile(
          icon: Icons.settings_rounded,
          label: 'Settings',
          onTap: () {
            Navigator.pop(context);
            Navigator.pushNamed(context, AppRoutes.settings);
          },
        ),
        if (isResponder)
          DrawerTile(
            icon: Icons.swap_horiz_rounded,
            label: shortRole,
            onTap: () async {
              Navigator.pop(context);
              await context.read<AuthProvider>().switchMode(null);
            },
          ),
        const DrawerDivider(),
        DrawerTile(
          icon: Icons.call_rounded,
          label: 'Call 999',
          emergency: true,
          onTap: () async {
            Navigator.pop(context);
            final uri = Uri(scheme: 'tel', path: '999');
            if (await canLaunchUrl(uri)) launchUrl(uri);
          },
        ),
        DrawerTile(
          icon: Icons.logout_rounded,
          label: 'Sign Out',
          emergency: true,
          onTap: () async {
            Navigator.pop(context);
            await context.read<AuthProvider>().signOut();
            if (mounted) {
              Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (_) => false);
            }
          },
        ),
      ],
    );
  }

  // ── Idle home — full-screen responders map with a draggable content sheet ──
  // Dragging the sheet down animates the live map to full-page; dragging up
  // brings the SOS controls back over it.
  Widget _buildIdle(String firstName) {
    return Stack(
      key: const ValueKey('idle'),
      children: [
        // Background: live responders map, full screen.
        Positioned.fill(child: _responderMapLayer()),

        // Floating top bar over the map.
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                _MapFab(
                  onTap: () => _scaffoldKey.currentState?.openDrawer(),
                  child: const Icon(Icons.menu_rounded, color: AppColors.textDark, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 2)),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 26, height: 26,
                          padding: const EdgeInsets.all(5),
                          decoration: const BoxDecoration(color: AppColors.textDark, shape: BoxShape.circle),
                          child: Image.asset(AppAssets.logo, fit: BoxFit.contain),
                        ),
                        const SizedBox(width: 8),
                        const Text('eKonnect',
                            style: TextStyle(
                                color: AppColors.textDark,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                letterSpacing: 0.3)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _MapFab(
                  onTap: () => Navigator.pushNamed(context, AppRoutes.profile),
                  child: const Icon(Icons.person_outline_rounded, color: AppColors.textDark, size: 22),
                ),
              ],
            ),
          ),
        ),

        // Draggable content sheet over the map. Expands to fully cover the map
        // on scroll-up (corners flatten into a clean full page), reveals the
        // map on scroll-down — content scrolls smoothly without being cut.
        NotificationListener<DraggableScrollableNotification>(
          onNotification: (n) {
            _sheetExtent.value = n.extent;
            return false;
          },
          child: DraggableScrollableSheet(
            initialChildSize: 0.58,
            minChildSize: 0.14,
            maxChildSize: 1.0,
            snap: true,
            snapSizes: const [0.14, 0.58, 1.0],
            builder: (context, scrollController) {
              final topPad = MediaQuery.of(context).padding.top;
              return ValueListenableBuilder<double>(
                valueListenable: _sheetExtent,
                builder: (context, extent, _) {
                  // Ramp from rounded sheet → flat full page as it nears full.
                  final full = ((extent - 0.9) / 0.1).clamp(0.0, 1.0);
                  final radius = 30.0 * (1 - full);
                  final topInset = 12 + full * (topPad + 10);
                  return Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, -4)),
                      ],
                    ),
                    child: ListView(
                      controller: scrollController,
                      padding: EdgeInsets.fromLTRB(20, topInset, 20, 32),
                      children: [
                        // Drag handle — fades out as the sheet becomes a full page.
                        Center(
                          child: Opacity(
                            opacity: (1 - full).clamp(0.0, 1.0),
                            child: Container(
                              width: 40,
                              height: 4,
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: AppColors.divider,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                        // Greeting
                        Text('Hi, $firstName 👋',
                            style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textDark)),
                        const SizedBox(height: 4),
                        Text("You're safe. Help is one tap away.",
                            style: TextStyle(fontSize: 13.5, color: AppColors.textMedium)),
                        const SizedBox(height: 20),
                        _SosSelector(sosTypes: _sosTypes, onSOS: _triggerSOS),

                  // Sits below the SOS button, never above it — the emergency
                  // action must always be the first thing within reach.
                  Builder(builder: (ctx) {
                    // Read here rather than closing over `build`: this sheet is
                    // constructed inside nested builders in another method.
                    final u = ctx.watch<AuthProvider>().user;
                    if (u == null || u.isProfileComplete) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: ProfilePromptCard(
                        progress: u.profileProgress,
                        missing: u.missingProfileSteps,
                        onTap: _openProfileSheet,
                      ),
                    );
                  }),

                  // ── Tier 1: still "send help" ──────────────────────────
                  // A second door into the SOS above, for callers who cannot
                  // categorise their own emergency. Sits tight under the
                  // selector so it reads as part of it, not as a rival card.
                  const SizedBox(height: 10),
                  VoiceReportButton(onTap: _startVoiceReport),

                  // ── Tier 2: the lifeline ───────────────────────────────
                  // 999 outranks everything below because it is what still
                  // works when the app, the network, or dispatch does not.
                  const SizedBox(height: 22),
                  _Call999Bar(onTap: _call999),

                  // ── Tier 3: support, not urgent ────────────────────────
                  const SizedBox(height: 22),
                  Text('More',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMedium,
                          letterSpacing: 0.3)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _SupportTile(
                          icon: Icons.smart_toy_outlined,
                          label: 'AI Help',
                          onTap: () =>
                              Navigator.pushNamed(context, AppRoutes.aiChat),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SupportTile(
                          asset: AppAssets.history,
                          label: 'History',
                          onTap: () => Navigator.pushNamed(
                              context, AppRoutes.incidentHistory),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SupportTile(
                          icon: Icons.shield_outlined,
                          label: 'Providers',
                          onTap: () => Navigator.pushNamed(
                              context, AppRoutes.myProviders),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SupportTile(
                          asset: AppAssets.tutorial,
                          label: 'Tutorial',
                          onTap: () =>
                              Navigator.pushNamed(context, AppRoutes.tutorial),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const _SafetyTip(),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // Full-screen live map of on-duty responders. Ambulances = red dots,
  // practitioners = green; the user's own position is the native blue dot.
  Widget _responderMapLayer() {
    return StreamBuilder<List<UserModel>>(
      stream: FirestoreService.streamAvailableResponders(),
      builder: (context, snap) {
        final responders = snap.data ?? const <UserModel>[];
        final markers = <Marker>{};
        for (final r in responders) {
          final isAmb = r.role == AppRoles.ambulance;
          final icon = isAmb ? _dotAmbulance : _dotPractitioner;
          markers.add(Marker(
            markerId: MarkerId(r.uid),
            position: LatLng(r.lat!, r.lng!),
            icon: icon ?? BitmapDescriptor.defaultMarker,
            anchor: const Offset(0.5, 0.5),
            infoWindow: InfoWindow(
              title: isAmb ? 'Ambulance' : 'Practitioner',
              snippet: r.name.isEmpty ? 'On duty' : r.name,
            ),
          ));
        }
        return Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _position != null
                    ? LatLng(_position!.latitude, _position!.longitude)
                    : const LatLng(-1.286389, 36.817223),
                zoom: 14,
              ),
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              padding: const EdgeInsets.only(top: 70, bottom: 260),
              markers: markers,
              onMapCreated: (c) {
                if (_position != null) {
                  c.animateCamera(CameraUpdate.newLatLng(
                      LatLng(_position!.latitude, _position!.longitude)));
                }
              },
            ),
            // On-duty count + legend, floating below the top bar.
            Positioned(
              top: 72,
              left: 16,
              right: 16,
              child: SafeArea(
                bottom: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppColors.textDark,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 8),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.local_hospital_rounded, color: Colors.white, size: 14),
                          const SizedBox(width: 5),
                          Text(
                            responders.isEmpty ? 'No responders on duty' : '${responders.length} on duty near you',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _LegendDot(color: _ambulanceColor, label: 'Ambulance'),
                          const SizedBox(width: 14),
                          _LegendDot(color: _practitionerColor, label: 'Practitioner'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Tracking view — map + active incident card ────────────────────────────
  Widget _buildTracking(IncidentModel incident) {
    return Stack(
      key: const ValueKey('tracking'),
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _position != null
                ? LatLng(_position!.latitude, _position!.longitude)
                : const LatLng(-1.286389, 36.817223),
            zoom: 15,
          ),
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          onMapCreated: (c) {
            _mapController = c;
            if (_position != null) {
              c.animateCamera(CameraUpdate.newLatLng(
                  LatLng(_position!.latitude, _position!.longitude)));
            }
          },
        ),

        // Top bar
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                _MapFab(
                  onTap: () => _scaffoldKey.currentState?.openDrawer(),
                  child: const Icon(Icons.menu_rounded, color: AppColors.textDark, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 2)),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 26, height: 26,
                          padding: const EdgeInsets.all(5),
                          decoration: const BoxDecoration(color: AppColors.textDark, shape: BoxShape.circle),
                          child: Image.asset(AppAssets.logo, fit: BoxFit.contain),
                        ),
                        const SizedBox(width: 8),
                        const Text('eKonnect',
                            style: TextStyle(
                                color: AppColors.textDark,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                letterSpacing: 0.3)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _MapFab(
                  onTap: () => Navigator.pushNamed(context, AppRoutes.profile),
                  child: const Icon(Icons.person_outline_rounded, color: AppColors.textDark, size: 22),
                ),
              ],
            ),
          ),
        ),

        // Right-side FABs
        Positioned(
          right: 16,
          bottom: 120,
          child: Column(
            children: [
              _MapFab(
                onTap: () {
                  if (_position != null) {
                    _mapController?.animateCamera(
                      CameraUpdate.newLatLng(LatLng(_position!.latitude, _position!.longitude)),
                    );
                  }
                },
                child: const Icon(Icons.my_location_rounded, color: AppColors.primary, size: 20),
              ),
              const SizedBox(height: 10),
              _MapFab(
                onTap: _call999,
                color: AppColors.accent,
                child: const Icon(Icons.call, color: Colors.white, size: 20),
              ),
            ],
          ),
        ),

        // Active incident card
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _ActiveIncidentCard(
            incident: incident,
            onView: () => Navigator.pushNamed(context, AppRoutes.sosWaiting, arguments: {
              'type': incident.type,
              'incidentId': incident.id,
            }),
          ),
        ),
      ],
    );
  }
}

// ── Quick action button ─────────────────────────────────────────────────────────

/// The direct line to emergency services.
///
/// Full width and the only accent-coloured element below the SOS button: when
/// the app cannot reach a responder, this is the fallback, so it must never be
/// just one tile among four equals.
class _Call999Bar extends StatelessWidget {
  final VoidCallback onTap;
  const _Call999Bar({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle),
              child: Center(
                  child: SvgPicture.asset(AppAssets.call, width: 26, height: 26)),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Call 999',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  SizedBox(height: 2),
                  Text('Talk to emergency services now',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: Colors.white70, size: 15),
          ],
        ),
      ),
    );
  }
}

/// Non-urgent destinations. Compact and visually quiet by design — these are
/// things a user browses, never things they need in an emergency.
class _SupportTile extends StatelessWidget {
  final IconData? icon;
  final String? asset;
  final String label;
  final VoidCallback onTap;

  const _SupportTile({
    required this.label,
    required this.onTap,
    this.icon,
    this.asset,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            asset != null
                ? SvgPicture.asset(asset!, width: 28, height: 28)
                : Icon(icon, color: AppColors.textDark, size: 26),
            const SizedBox(height: 7),
            Text(label,
                style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ── Safety tip banner ────────────────────────────────────────────────────────────

class _SafetyTip extends StatelessWidget {
  const _SafetyTip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.tips_and_updates_rounded, color: AppColors.textMedium, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Keep calm and stay where you are after sending an SOS — responders see your live location.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textMedium, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Map legend dot ───────────────────────────────────────────────────────────────

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 2),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                color: AppColors.textMedium,
                fontWeight: FontWeight.w500)),
      ],
    );
  }
}

// ── SOS morph selector (tap a type → morphs into a hold-to-send SOS button) ──────

class _SosSelector extends StatefulWidget {
  final List<Map<String, Object>> sosTypes;
  final Future<void> Function(String type, {bool skipConfirm}) onSOS;

  const _SosSelector({required this.sosTypes, required this.onSOS});

  @override
  State<_SosSelector> createState() => _SosSelectorState();
}

class _SosSelectorState extends State<_SosSelector>
    with TickerProviderStateMixin {
  late final AnimationController _morph; // 0 = grid, 1 = expanded
  late final AnimationController _pulse; // ambient pulse on armed button
  late final AnimationController _hold;  // fills while holding → fires SOS

  String? _armedType;
  bool _sending = false;

  static const _cardH = 130.0; // height of one card in the 2×2 grid
  static const _gap = 12.0;

  @override
  void initState() {
    super.initState();
    _morph = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380));
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
    _hold = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100));

    _morph.addStatusListener((s) {
      if (s == AnimationStatus.dismissed && mounted) {
        setState(() => _armedType = null);
      }
    });
    _hold.addStatusListener((s) {
      if (s == AnimationStatus.completed) _send();
    });
  }

  @override
  void dispose() {
    _morph.dispose();
    _pulse.dispose();
    _hold.dispose();
    super.dispose();
  }

  void _arm(String type) {
    HapticFeedback.selectionClick();
    setState(() => _armedType = type);
    _morph.forward();
  }

  void _disarm() {
    if (_sending) return;
    HapticFeedback.selectionClick();
    _hold.reverse();
    _morph.reverse();
  }

  void _onHoldStart() {
    if (_sending || _armedType == null || _morph.value < 0.98) return;
    HapticFeedback.mediumImpact();
    _hold.forward(from: _hold.value);
  }

  void _onHoldEnd() {
    if (_sending && _hold.isCompleted) return;
    if (!_hold.isCompleted) _hold.reverse();
  }

  Future<void> _send() async {
    final type = _armedType;
    if (type == null || _sending) return;
    setState(() => _sending = true);
    HapticFeedback.heavyImpact();
    try {
      await widget.onSOS(type, skipConfirm: true);
    } finally {
      // Must be in a finally: if onSOS throws or returns without navigating
      // (e.g. an incident is already active), the button would otherwise stay
      // stuck on "Sending…" forever with no way to retry.
      if (mounted) {
        _hold.reset();
        _morph.reverse();
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final armed = _armedType != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SizeTransition(
                sizeFactor: anim, alignment: Alignment.topCenter, child: child),
          ),
          child: armed
              ? Column(
                  key: const ValueKey('armed'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${IncidentType.label(_armedType!)}?',
                        style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textDark)),
                    const SizedBox(height: 3),
                    const Text('Hold the button to alert responders.',
                        style: TextStyle(fontSize: 13, color: AppColors.textMedium)),
                  ],
                )
              : Column(
                  key: const ValueKey('idle'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("What's your emergency?",
                        style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textDark)),
                    const SizedBox(height: 3),
                    const Text('Tap a type, then hold to send.',
                        style: TextStyle(fontSize: 13, color: AppColors.textMedium)),
                  ],
                ),
        ),
        const SizedBox(height: 16),

        LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final cardW = (w - _gap) / 2;
            final gridH = _cardH * 2 + _gap;

            return AnimatedBuilder(
              animation: Listenable.merge([_morph, _pulse, _hold]),
              builder: (context, _) {
                final t = Curves.easeInOutCubic.transform(_morph.value);
                final armedIdx = _armedType == null
                    ? -1
                    : widget.sosTypes.indexWhere((e) => e['type'] == _armedType);

                final tiles = <Widget>[];
                for (int i = 0; i < widget.sosTypes.length; i++) {
                  final type = widget.sosTypes[i]['type'] as String;
                  final label = widget.sosTypes[i]['label'] as String;
                  final asset = widget.sosTypes[i]['asset'] as String;
                  final gridLeft = (i % 2) * (cardW + _gap);
                  final gridTop = (i ~/ 2) * (_cardH + _gap);

                  if (armedIdx == i) {
                    tiles.add(Positioned(
                      left: lerpDouble(gridLeft, 0, t),
                      top: lerpDouble(gridTop, 0, t),
                      width: lerpDouble(cardW, w, t),
                      height: lerpDouble(_cardH, gridH, t),
                      child: _selectedCard(type, label, asset, t, w, gridH),
                    ));
                  } else {
                    final fade =
                        armedIdx == -1 ? 1.0 : (1 - t * 1.8).clamp(0.0, 1.0);
                    tiles.add(Positioned(
                      left: gridLeft,
                      top: gridTop,
                      width: cardW,
                      height: _cardH,
                      child: IgnorePointer(
                        ignoring: armedIdx != -1,
                        child: Opacity(
                          opacity: fade,
                          child: Transform.scale(
                            scale: lerpDouble(1, 0.9, t)!,
                            child: _gridCard(type, label, asset),
                          ),
                        ),
                      ),
                    ));
                  }
                }

                return SizedBox(
                  height: gridH,
                  width: w,
                  child: Stack(clipBehavior: Clip.none, children: tiles),
                );
              },
            );
          },
        ),
      ],
    );
  }

  // One card in the 2×2 grid — light-grey, big colourful illustration + label.
  Widget _gridCard(String type, String label, String asset) {
    return GestureDetector(
      onTap: () => _arm(type),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(20),
        ),
        child: _cardFace(asset, label),
      ),
    );
  }

  Widget _cardFace(String asset, String label) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SvgPicture.asset(asset, width: 62, height: 62),
        const SizedBox(height: 12),
        Text(label,
            style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 15,
                fontWeight: FontWeight.bold)),
      ],
    );
  }

  // Armed state: the tapped card grows to fill the whole 2×2 area and reveals
  // a big coral hold-to-send SOS button.
  Widget _selectedCard(String type, String label, String asset, double t,
      double fullWidth, double fullHeight) {
    final holdV = _hold.value;
    final pulseScale =
        1 + 0.04 * (0.5 + 0.5 * math.sin(_pulse.value * 2 * math.pi));

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06 + 0.04 * holdV),
            blurRadius: 16 + 8 * holdV,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Collapsing compact face — visible only at the very start.
          if (t < 0.4)
            Positioned.fill(
              child: Opacity(
                opacity: (1 - t * 2.5).clamp(0.0, 1.0),
                child: _cardFace(asset, label),
              ),
            ),

          // Armed content, rendered at full size and clipped as the card grows.
          Positioned.fill(
            child: ClipRect(
              child: Opacity(
                opacity: (t * 1.4 - 0.4).clamp(0.0, 1.0),
                child: OverflowBox(
                  minWidth: 0,
                  maxWidth: fullWidth,
                  minHeight: 0,
                  maxHeight: fullHeight,
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: fullWidth,
                    height: fullHeight,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
                      child: Column(
                        children: [
                          // Identity
                          Row(
                            children: [
                              SvgPicture.asset(asset, width: 34, height: 34),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: AppColors.textDark,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                          // Big hold-to-send SOS button
                          Expanded(
                            child: Center(
                              child: GestureDetector(
                                onTapDown: (_) => _onHoldStart(),
                                onTapUp: (_) => _onHoldEnd(),
                                onTapCancel: _onHoldEnd,
                                child: Transform.scale(
                                  scale: pulseScale,
                                  child: SizedBox(
                                    width: 132,
                                    height: 132,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        SizedBox(
                                          width: 132,
                                          height: 132,
                                          child: CircularProgressIndicator(
                                            value: _sending ? null : holdV,
                                            strokeWidth: 6,
                                            backgroundColor: AppColors.divider,
                                            valueColor: const AlwaysStoppedAnimation(
                                                AppColors.accent),
                                          ),
                                        ),
                                        Container(
                                          width: 106,
                                          height: 106,
                                          decoration: BoxDecoration(
                                            color: AppColors.accent,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: AppColors.accent
                                                    .withValues(alpha: 0.4),
                                                blurRadius: 16,
                                                offset: const Offset(0, 6),
                                              ),
                                            ],
                                          ),
                                          child: Center(
                                            child: _sending
                                                ? const SizedBox(
                                                    width: 26,
                                                    height: 26,
                                                    child: CircularProgressIndicator(
                                                        strokeWidth: 3,
                                                        color: Colors.white),
                                                  )
                                                : const Text('SOS',
                                                    style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 26,
                                                        fontWeight: FontWeight.w900,
                                                        letterSpacing: 1)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Text(_sending ? 'Sending…' : 'Hold to send',
                              style: const TextStyle(
                                  color: AppColors.textMedium,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Cancel (✕)
          if (t > 0.6 && !_sending)
            Positioned(
              top: 14,
              right: 14,
              child: Opacity(
                opacity: ((t - 0.6) * 2.5).clamp(0.0, 1.0),
                child: GestureDetector(
                  onTap: _disarm,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: AppColors.textDark, size: 18),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Floating map button ────────────────────────────────────────────────────────

class _MapFab extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;
  final Color? color;
  const _MapFab({required this.onTap, required this.child, this.color});

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
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(child: child),
      ),
    );
  }
}

// ── Active incident card (floating trip-card style) ─────────────────────────────

class _ActiveIncidentCard extends StatelessWidget {
  final IncidentModel incident;
  final VoidCallback onView;
  const _ActiveIncidentCard({required this.incident, required this.onView});

  @override
  Widget build(BuildContext context) {
    final icon = IncidentType.icon(incident.type);
    final label = IncidentType.label(incident.type);
    final status = IncidentStatus.label(incident.status);
    final hasResponder = incident.assignedTo != null;

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, -2)),
          ],
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.15), width: 1.5),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            onTap: onView,
            borderRadius: BorderRadius.circular(22),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  Container(
                    width: 50, height: 50,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 3))],
                    ),
                    child: Icon(icon, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.primary)),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            if (!hasResponder)
                              const SizedBox(
                                width: 10, height: 10,
                                child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.accent),
                              )
                            else
                              const Icon(Icons.check_circle, size: 12, color: AppColors.primary),
                            const SizedBox(width: 6),
                            Text(status,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textMedium,
                                    fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('View',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

