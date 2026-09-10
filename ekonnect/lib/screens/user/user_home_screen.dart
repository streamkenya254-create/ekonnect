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
import '../../widgets/user_avatar.dart';
import '../../models/incident_model.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
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

  /// Opens the profile.
  ///
  /// Deliberately the same page, in the same state, as tapping the avatar.
  /// Arriving pre-opened in edit mode made "finish setting up your profile"
  /// look like a second, near-identical screen. AuthProvider streams the user
  /// doc, so the prompt here updates itself on the way back.
  Future<void> _openProfile() async {
    await Navigator.pushNamed(context, AppRoutes.profile);
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
      backgroundColor: AppColors.surfaceAlt,
      drawer: _buildDrawer(auth),
      // One map, one sheet. What changes is what the sheet holds: the SOS
      // selector, or the emergency already under way. Swapping whole screens
      // meant two GoogleMap instances, two cameras, and a jump every time the
      // state changed under the user.
      body: _buildHome(firstName, hasActive ? activeIncident : null),
    );
  }

  Widget _buildDrawer(AuthProvider auth) {
    final role = auth.user?.role ?? AppRoles.user;
    final isResponder = AppRoles.isResponder(role);
    final shortRole = role == AppRoles.ambulance ? 'Ambulance' : 'Responder';
    return AppDrawer(
      name: auth.user?.name ?? 'User',
      user: auth.user,
      subtitle: isResponder ? shortRole : 'Emergency User',
      // Only what the home screen does not already offer.
      //
      // AI Help, History, Providers and Tutorial are tiles on the sheet
      // below; 999 is the coral bar above them; Profile is the avatar in the
      // top bar; and "Home" is the screen the drawer is covering. Listing all
      // of that again made the drawer look full while saying nothing new.
      children: [
        DrawerTile(
          icon: Icons.notifications_none_rounded,
          label: 'Notifications',
          onTap: () {
            Navigator.pop(context);
            Navigator.pushNamed(context, AppRoutes.notifications);
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
  Widget _buildHome(String firstName, IncidentModel? active) {
    return Stack(
      children: [
        // Background: live responders map, full screen.
        Positioned.fill(child: _responderMapLayer()),

        // Floating top bar over the map.
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                _MapFab(
                  onTap: () => _scaffoldKey.currentState?.openDrawer(),
                  child: const Icon(Icons.menu_rounded,
                      color: AppColors.textDark, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 15,
                            offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // The purple mark is its own disc, so it needs no
                        // plate behind it on the white bar.
                        Image.asset(AppAssets.logoPurple,
                            width: 30, height: 30, fit: BoxFit.contain),
                        const SizedBox(width: 10),
                        const Text('eKonnect',
                            style: TextStyle(
                                color: AppColors.textDark,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                letterSpacing: -0.3)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _MapFab(
                  onTap: () => Navigator.pushNamed(context, AppRoutes.settings),
                  child: const Icon(Icons.settings_rounded,
                      color: AppColors.textDark, size: 22),
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
            initialChildSize: 0.60,
            minChildSize: 0.15,
            maxChildSize: 1.0,
            snap: true,
            snapSizes: const [0.15, 0.60, 1.0],
            builder: (context, scrollController) {
              final topPad = MediaQuery.of(context).padding.top;
              return ValueListenableBuilder<double>(
                valueListenable: _sheetExtent,
                builder: (context, extent, _) {
                  // Ramp from rounded sheet → flat full page as it nears full.
                  final full = ((extent - 0.9) / 0.1).clamp(0.0, 1.0);
                    final peek = extent < 0.28;
                  final radius = 32.0 * (1 - full);
                  final topInset = 12 + full * (topPad + 10);
                  return Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 30,
                            offset: const Offset(0, -5)),
                      ],
                    ),
                    child: ListView(
                      controller: scrollController,
                      // A peek has nothing below the greeting to scroll into,
                      // so 32 at the foot only pushed the greeting itself
                      // against the sheet's edge.
                      padding: EdgeInsets.fromLTRB(
                          24, topInset, 24, peek ? 12 : 32),
                      children: [
                        // Drag handle — fades out as the sheet becomes a full page.
                        Center(
                          child: Opacity(
                            opacity: (1 - full).clamp(0.0, 1.0),
                            child: Container(
                              width: 48,
                              height: 5,
                              margin: const EdgeInsets.only(bottom: 24),
                              decoration: BoxDecoration(
                                color: AppColors.divider.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        // Greeting
                        Row(
                          children: [
                            // The one place the user's own face belongs:
                            // beside their name, not floating over the map.
                            GestureDetector(
                              onTap: () => Navigator.pushNamed(
                                  context, AppRoutes.profile),
                              child: UserAvatar(
                                user: context.watch<AuthProvider>().user,
                                // Two lines of text tall: at 58 it read as an
                                // afterthought beside a 24pt name.
                                size: 66,
                                cornerRadius: 20,
                                background: AppColors.surfaceAlt,
                                foreground: AppColors.textDark,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Hi, $firstName',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.5,
                                          color: AppColors.textDark)),
                                  const SizedBox(height: 3),
                                  const Text(
                                      "You're safe. Help is one tap away.",
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: AppColors.textMedium)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        // Below this height the sheet cannot show the rest without
                        // cutting it in half, so it shows none of it. The greeting
                        // above stays, which is all a peek needs to identify itself.
                        if (!peek) ...[
                          const SizedBox(height: 28),
                          // The emergency under way outranks everything: while
                          // one is open, this is a tracking sheet.
                          if (active != null)
                            _ActiveIncidentCard(
                              incident: active,
                              onView: () => Navigator.pushNamed(
                                  context, AppRoutes.sosWaiting, arguments: {
                                'type': active.type,
                                'incidentId': active.id,
                              }),
                            )
                          else
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
                          onTap: _openProfile,
                        ),
                      );
                    }),

                    // ── Tier 1: still "send help" ──────────────────────────
                    // A second door into the SOS above, for callers who cannot
                    // categorise their own emergency. Sits tight under the
                    // selector so it reads as part of it, not as a rival card.
                    if (active == null) ...[
                      const SizedBox(height: 16),
                      VoiceReportButton(onTap: _startVoiceReport),
                    ],

                    // ── Tier 2: the lifeline ───────────────────────────────
                    // 999 outranks everything below because it is what still
                    // works when the app, the network, or dispatch does not.
                    const SizedBox(height: 24),
                    _Call999Bar(onTap: _call999),

                    // ── Tier 3: support, not urgent ────────────────────────
                    const SizedBox(height: 32),
                    const Text('Additional Support',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textDark)),
                    const SizedBox(height: 16),
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
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SupportTile(
                            asset: AppAssets.history,
                            label: 'History',
                            onTap: () => Navigator.pushNamed(
                                context, AppRoutes.incidentHistory),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SupportTile(
                            icon: Icons.shield_outlined,
                            label: 'Providers',
                            onTap: () => Navigator.pushNamed(
                                context, AppRoutes.myProviders),
                          ),
                        ),
                        const SizedBox(width: 12),
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
        return GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _position != null
                ? LatLng(_position!.latitude, _position!.longitude)
                : const LatLng(-1.286389, 36.817223),
            zoom: 14,
          ),
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          // Keeps Google's own controls clear of the floating bar.
          padding: const EdgeInsets.only(top: 80, bottom: 260),
          markers: markers,
          onMapCreated: (c) {
            if (_position != null) {
              c.animateCamera(CameraUpdate.newLatLng(
                  LatLng(_position!.latitude, _position!.longitude)));
            }
          },
        );
      },
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.25),
              blurRadius: 15,
              offset: const Offset(0, 6),
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle),
              child: Center(
                  child: SvgPicture.asset(AppAssets.call, width: 24, height: 24)),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Call 999',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text('Talk to emergency services now',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Colors.white, size: 28),
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
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.divider.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            asset != null
                ? SvgPicture.asset(asset!, width: 26, height: 26)
                : Icon(icon, color: AppColors.textDark, size: 26),
            const SizedBox(height: 10),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
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
                                            strokeWidth: _sending ? 7 : 6,
                                            backgroundColor: _sending
                                                ? AppColors.accent
                                                    .withValues(alpha: 0.18)
                                                : AppColors.divider,
                                            valueColor:
                                                const AlwaysStoppedAnimation(
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
                                            // The word stays put throughout;
                                            // only its weight eases back so the
                                            // button reads as working rather
                                            // than waiting to be pressed again.
                                            child: AnimatedOpacity(
                                              duration: const Duration(
                                                  milliseconds: 250),
                                              opacity: _sending ? 0.75 : 1,
                                              child: const Text('SOS',
                                                  style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 26,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      letterSpacing: 1)),
                                            ),
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
  const _MapFab({required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 15,
              offset: const Offset(0, 4),
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
        margin: EdgeInsets.zero,
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
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              child: Row(
                children: [
                  Container(
                    width: 56, height: 56,
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.cardTitle
                                .copyWith(color: AppColors.primary)),
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
                            Flexible(
                              child: Text(status,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.meta),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 11),
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
