import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_assets.dart';
import '../../core/constants.dart';
import '../../models/incident_model.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/incident_provider.dart';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import '../../services/marker_helper.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/incident_card_widget.dart';
import '../../widgets/user_avatar.dart';

class ResponderHomeScreen extends StatefulWidget {
  const ResponderHomeScreen({super.key});

  @override
  State<ResponderHomeScreen> createState() => _ResponderHomeScreenState();
}

class _ResponderHomeScreenState extends State<ResponderHomeScreen> {
  bool _isAvailable = false;
  Position? _position;
  GoogleMapController? _mapController;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final Map<String, BitmapDescriptor> _incidentMarkers = {};

  // Tracks how far the content sheet is expanded (0..1) so the top padding and
  // corner radius adapt as it covers the map — same behaviour as the user home.
  final ValueNotifier<double> _sheetExtent = ValueNotifier<double>(0.55);

  /// Whether this launch has already restored a job in progress.
  ///
  /// Reopening the app mid-job should land the crew back on that job. Pressing
  /// Home *from* that job should not — and because this screen re-ran the same
  /// restore on every build of itself, the Home button appeared dead: it
  /// returned here and was immediately pushed back. Static, so it survives
  /// this screen being rebuilt but not the process.
  static bool _restoredActiveJob = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final user = context.read<AuthProvider>().user;
      setState(() => _isAvailable = user?.isAvailable ?? false);

      // Mark the visit before deciding, not after: a crew who launches with
      // no job, accepts one, then presses Home must not be pushed back into
      // it either. Only the very first appearance of this screen restores.
      final firstVisit = !_restoredActiveJob;
      _restoredActiveJob = true;

      final active = context.read<IncidentProvider>().activeIncident;
      if (firstVisit && active != null && active.isActive) {
        Navigator.pushNamed(context, AppRoutes.activeJob, arguments: active.id);
        return;
      }
      final pos = await LocationService.getCurrentPosition();
      if (mounted) setState(() => _position = pos);
      if (pos != null) {
        _mapController?.animateCamera(
            CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)));
      }

      for (final type in [
        IncidentType.medical,
        IncidentType.fire,
        IncidentType.flood,
        IncidentType.security
      ]) {
        final icon = await MarkerHelper.incidentPin(type);
        if (mounted) setState(() => _incidentMarkers[type] = icon);
      }
    });
  }

  @override
  void dispose() {
    _sheetExtent.dispose();
    super.dispose();
  }

  /// Who this responder answers for, in one word or one name.
  ///
  /// Three cases, and the crew should be able to tell them apart at a glance:
  /// they work for a facility, they are on the open network, or they answer
  /// only their own clients. The name wins when there is one — 'Oasis
  /// Specialist Hospital' says more than 'Private' ever could.
  static String _scopeOf(UserModel? user) {
    final org = (user?.organisation ?? '').trim();
    if (org.isNotEmpty) return org;
    switch (user?.visibility) {
      case ResponderVisibility.private:
        return 'Private';
      case ResponderVisibility.clients:
        return 'Named clients';
      default:
        return 'Independent · Public network';
    }
  }

  Future<void> _toggleAvailability(bool val) async {
    final auth = context.read<AuthProvider>();
    final user = auth.user;

    // Hard gate: an unverified responder must never be able to put themselves
    // on the live network. Going on duty means real emergencies get routed to
    // them, so this is a safety boundary, not a UI nicety.
    if (val && user != null && !user.canRespond) {
      _showVerificationBlockedSheet(user);
      return;
    }

    setState(() => _isAvailable = val);
    await FirestoreService.setOnlineStatus(
      auth.user!.uid,
      isOnline: true,
      isAvailable: val,
    );
  }

  void _showVerificationBlockedSheet(UserModel user) {
    final status = user.verificationStatus;
    final color = VerificationStatus.color(status);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_user_outlined, color: color, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    VerificationStatus.label(status),
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold, color: color),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              switch (status) {
                VerificationStatus.rejected =>
                  'Your responder application was not approved, so you cannot '
                      'go on duty.',
                VerificationStatus.suspended =>
                  'Your responder access has been suspended. Contact your '
                      'organisation to restore it.',
                _ => 'An administrator still needs to verify your credentials '
                    'before you can receive emergencies. You will be able to go '
                    'on duty as soon as that is done.',
              },
              style: const TextStyle(
                  fontSize: 14, height: 1.45, color: AppColors.textMedium),
            ),
            if ((user.verificationNote ?? '').isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  user.verificationNote!,
                  style: const TextStyle(
                      fontSize: 14, height: 1.4, color: AppColors.textDark),
                ),
              ),
            ],
            if ((user.organisation ?? '').isNotEmpty) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(Icons.business_rounded,
                      size: 16, color: AppColors.textMedium),
                  const SizedBox(width: 8),
                  Text(user.organisation!,
                      style: const TextStyle(
                          fontSize: 14, color: AppColors.textMedium)),
                ],
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _accept(IncidentModel incident) async {
    final provider = context.read<IncidentProvider>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final won = await provider.acceptIncident(incident.id);
    if (!mounted) return;

    if (!won) {
      messenger.showSnackBar(SnackBar(
        content: Text(provider.error ?? 'Could not take this call.'),
        backgroundColor: AppColors.textDark,
      ));
      return;
    }
    nav.pushNamed(AppRoutes.activeJob, arguments: incident.id);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final provider = context.watch<IncidentProvider>();
    final incidents = provider.pendingIncidents;
    final user = auth.user;

    final isAmbulance = user?.role == AppRoles.ambulance;
    final roleLabel = isAmbulance ? 'Ambulance' : 'Practitioner';
    final firstName = user?.name.split(' ').first ?? 'Responder';

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.primaryDark,
      drawer: _buildDrawer(user?.name ?? 'Responder', roleLabel),
      body: Stack(
        children: [
          // Background: full-screen live map of incoming incidents.
          Positioned.fill(child: _mapLayer(incidents)),

          // Floating top bar over the map.
          _topBar(),

          // Draggable content sheet — statistics + incidents. Scroll up covers
          // the map into a clean full page; scroll down reveals the map beneath.
          NotificationListener<DraggableScrollableNotification>(
            onNotification: (n) {
              _sheetExtent.value = n.extent;
              return false;
            },
            child: DraggableScrollableSheet(
              initialChildSize: 0.55,
              minChildSize: 0.16,
              maxChildSize: 1.0,
              snap: true,
              snapSizes: const [0.16, 0.55, 1.0],
              builder: (context, scrollController) {
                final topPad = MediaQuery.of(context).padding.top;
                return ValueListenableBuilder<double>(
                  valueListenable: _sheetExtent,
                  builder: (context, extent, _) {
                    final full = ((extent - 0.9) / 0.1).clamp(0.0, 1.0);
                    final peek = extent < 0.28;
                    final radius = 30.0 * (1 - full);
                    final topInset = 12 + full * (topPad + 10);
                    return Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(radius)),
                        boxShadow: const [
                          BoxShadow(
                              color: Colors.black26,
                              blurRadius: 20,
                              offset: Offset(0, -4)),
                        ],
                      ),
                      child: ListView(
                        controller: scrollController,
                        padding: EdgeInsets.fromLTRB(20, topInset, 20, peek ? 12 : 32),
                        children: [
                          // Drag handle — fades as the sheet becomes a full page.
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

                          // Identity — big role illustration + greeting.
                          Row(
                            children: [
                              // The one place the responder's own face
                              // belongs: beside their name, not floating over
                              // the map where it competed with the duty pill.
                              GestureDetector(
                                onTap: () => Navigator.pushNamed(
                                    context, AppRoutes.profile),
                                child: UserAvatar(
                                  user: user,
                                  size: 58,
                                  cornerRadius: 18,
                                  background: AppColors.surfaceAlt,
                                  foreground: AppColors.textDark,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Hi, $firstName',
                                        style: const TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.textDark)),
                                    const SizedBox(height: 2),
                                    Text('$roleLabel · ${_scopeOf(user)}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 14,
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
                            const SizedBox(height: 18),

                            // The job in progress, if there is one. Leaving it
                            // to check the map is normal; losing the way back
                            // to it is not.
                            Builder(builder: (ctx) {
                              final active =
                                  ctx.watch<IncidentProvider>().activeIncident;
                              if (active == null || !active.isActive) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 18),
                                child: _ActiveJobCard(incident: active),
                              );
                            }),

                            // Duty toggle.
                            _dutyToggle(),

                            const SizedBox(height: 22),

                            // Statistics.
                            const Text('Overview',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textMedium,
                                    letterSpacing: 0.3)),
                            const SizedBox(height: 12),
                            _statsRow(incidents.length),
                            const SizedBox(height: 22),

                            // Incoming incidents / status.
                            _incidentsSection(incidents),
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

  // ── Top bar ───────────────────────────────────────────────────────────────
  Widget _topBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(
          children: [
            _circleBtn(
              icon: Icons.menu_rounded,
              onTap: () => _scaffoldKey.currentState?.openDrawer(),
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
            _circleBtn(
              icon: Icons.settings_rounded,
              onTap: () => Navigator.pushNamed(context, AppRoutes.settings),
            ),
          ],
        ),
      ),
    );
  }

  /// Either an icon or, for the profile button, the user's own face.
  Widget _circleBtn(
      {IconData? icon, Widget? child, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 10,
                offset: const Offset(0, 2)),
          ],
        ),
        child: child == null
            ? Icon(icon, color: AppColors.textDark, size: 22)
            : Center(child: child),
      ),
    );
  }

  // Duty status pill in the top bar — tap to go on / off duty.
  Widget _mapLayer(List<IncidentModel> incidents) {
    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _position != null
                ? LatLng(_position!.latitude, _position!.longitude)
                : const LatLng(-1.286389, 36.817223),
            zoom: 13,
          ),
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          padding: const EdgeInsets.only(top: 70, bottom: 320),
          markers: incidents.map((inc) {
            final icon = _incidentMarkers[inc.type] ??
                BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueRose);
            return Marker(
              markerId: MarkerId(inc.id),
              position: LatLng(inc.userLat, inc.userLng),
              icon: icon,
              infoWindow: InfoWindow(
                  title: IncidentType.label(inc.type), snippet: inc.userName),
            );
          }).toSet(),
          onMapCreated: (c) {
            _mapController = c;
            if (_position != null) {
              c.animateCamera(CameraUpdate.newLatLng(
                  LatLng(_position!.latitude, _position!.longitude)));
            }
          },
        ),

      ],
    );
  }

  // ── Statistics row — live incoming, colleagues on duty, own status ─────────
  Widget _statsRow(int incoming) {
    return StreamBuilder<List<UserModel>>(
      stream: FirestoreService.streamAvailableResponders(),
      builder: (context, snap) {
        final onDuty = snap.data?.length ?? 0;
        return Row(
          children: [
            Expanded(
              child: _StatTile(
                value: '$incoming',
                label: 'Incoming',
                color: AppColors.accent,
                icon: Icons.notifications_active_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatTile(
                value: '$onDuty',
                label: 'On duty',
                color: const Color(0xFF2E7D32),
                icon: Icons.group_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatTile(
                value: _isAvailable ? 'On' : 'Off',
                label: 'You',
                color:
                    _isAvailable ? const Color(0xFF2E7D32) : AppColors.textLight,
                icon: Icons.bolt_rounded,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _incidentsSection(List<IncidentModel> incidents) {
    if (!_isAvailable) {
      return _StatusBlock(
        title: 'You are off duty',
        message:
            'Go on duty to start receiving emergency calls near you.',
        icon: Icons.pause_circle_outline,
        action: FilledButton.icon(
          onPressed: () => _toggleAvailability(true),
          icon: const Icon(Icons.bolt_rounded, size: 20),
          label: const Text('Go On Duty'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            textStyle:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    final backups = context.watch<IncidentProvider>().backupRequests;

    if (incidents.isEmpty && backups.isEmpty) {
      return const _StatusBlock(
        title: 'All clear nearby',
        message:
            "You're on duty. We'll alert you the moment a new incident comes in.",
        icon: Icons.check_circle_outline,
      );
    }

    if (incidents.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final b in backups) _BackupCard(incident: b)],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final b in backups) _BackupCard(incident: b),
        Row(
          children: [
            const Text('Incoming incidents',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark)),
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('${incidents.length}',
                  style: const TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final inc in incidents)
          IncidentCardWidget(
            incident: inc,
            onAccept: () => _accept(inc),
            currentLat: _position?.latitude,
            currentLng: _position?.longitude,
          ),
      ],
    );
  }

  Widget _dutyToggle() {
    return GestureDetector(
      onTap: () => _toggleAvailability(!_isAvailable),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: _isAvailable
              ? AppColors.accent.withValues(alpha: 0.10)
              : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _isAvailable
                ? AppColors.accent.withValues(alpha: 0.6)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(
              _isAvailable ? Icons.bolt_rounded : Icons.pause_circle_outline,
              color: _isAvailable ? AppColors.accent : AppColors.textMedium,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _isAvailable
                    ? 'Accepting emergency calls'
                    : 'Tap to go on duty',
                style: TextStyle(
                  color:
                      _isAvailable ? AppColors.textDark : AppColors.textMedium,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            Switch(
              value: _isAvailable,
              onChanged: _toggleAvailability,
              activeThumbColor: Colors.white,
              activeTrackColor: AppColors.accent,
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: AppColors.textLight,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer(String name, String roleLabel) {
    return AppDrawer(
      name: name,
      user: context.watch<AuthProvider>().user,
      subtitle: roleLabel,
      statusText: _isAvailable ? 'On Duty' : 'Off Duty',
      statusActive: _isAvailable,
      // "Dashboard" is the screen behind the drawer and Profile is the avatar
      // in the top bar, so neither is repeated here. Everything below has no
      // other way in from this screen.
      children: [
        DrawerTile(
          icon: Icons.history_rounded,
          label: 'Jobs history',
          onTap: () {
            Navigator.pop(context);
            Navigator.pushNamed(context, AppRoutes.incidentHistory);
          },
        ),
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
        DrawerTile(
          icon: Icons.play_circle_rounded,
          label: 'Tutorial',
          onTap: () {
            Navigator.pop(context);
            Navigator.pushNamed(context, AppRoutes.tutorial);
          },
        ),
        DrawerTile(
          icon: Icons.swap_horiz_rounded,
          label: 'Emergency user',
          onTap: () async {
            Navigator.pop(context);
            await context.read<AuthProvider>().switchMode(AppRoles.user);
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
              Navigator.pushNamedAndRemoveUntil(
                  context, AppRoutes.login, (_) => false);
            }
          },
        ),
      ],
    );
  }
}

/// A job already under way, and the way back into it.
class _ActiveJobCard extends StatelessWidget {
  final IncidentModel incident;
  const _ActiveJobCard({required this.incident});

  @override
  Widget build(BuildContext context) {
    final colour = IncidentType.color(incident.type);
    return Material(
      color: colour,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: () => Navigator.pushNamed(context, AppRoutes.activeJob,
            arguments: incident.id),
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(IncidentType.icon(incident.type),
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Job in progress',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text(
                      incident.userName.isEmpty
                          ? IncidentType.label(incident.type)
                          : incident.userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(IncidentStatus.label(incident.status),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Text('Resume',
                    style: TextStyle(
                        color: colour,
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Statistic tile ───────────────────────────────────────────────────────────

class _StatTile extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final IconData icon;
  const _StatTile({
    required this.value,
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 10),
          Text(value,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textMedium)),
        ],
      ),
    );
  }
}

// ── Off-duty / all-clear status block (lives inside the sheet) ────────────────

class _StatusBlock extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;
  final Widget? action;
  const _StatusBlock({
    required this.title,
    required this.message,
    required this.icon,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(
                color: Colors.white, shape: BoxShape.circle),
            child: Icon(icon, size: 42, color: AppColors.primary),
          ),
          const SizedBox(height: 18),
          Text(title,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark)),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: AppColors.textMedium, fontSize: 14, height: 1.5),
          ),
          if (action != null) ...[
            const SizedBox(height: 22),
            action!,
          ],
        ],
      ),
    );
  }
}


/// A crew already on scene needs a second pair of hands.
///
/// Visually distinct from an incoming incident: somebody is already there, so
/// this is not a race and answering it late is not a failure. Showing it as a
/// normal SOS card would make every backup request look like an emergency
/// nobody had answered.
class _BackupCard extends StatefulWidget {
  final IncidentModel incident;
  const _BackupCard({required this.incident});

  @override
  State<_BackupCard> createState() => _BackupCardState();
}

class _BackupCardState extends State<_BackupCard> {
  bool _joining = false;

  Future<void> _join() async {
    setState(() => _joining = true);
    final provider = context.read<IncidentProvider>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final joined = await provider.joinAsBackup(widget.incident.id);
    if (!mounted) return;

    if (!joined) {
      setState(() => _joining = false);
      messenger.showSnackBar(SnackBar(
        content: Text(provider.error ?? 'Could not join that job.'),
      ));
      return;
    }
    nav.pushNamed(AppRoutes.activeJob, arguments: widget.incident.id);
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.incident;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.group_add_rounded,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              const Text('Backup needed',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppColors.primary)),
              const Spacer(),
              Text(IncidentType.label(i.type),
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.textLight)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${i.assignedToName ?? 'A crew'} is already on scene and has asked '
            'for a second crew.',
            style: const TextStyle(fontSize: 14, color: AppColors.textDark),
          ),
          if (i.backupReason != null && i.backupReason!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('"${i.backupReason}"',
                style: const TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: AppColors.textMedium)),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _joining ? null : _join,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(_joining ? 'Joining…' : 'Join as backup'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
