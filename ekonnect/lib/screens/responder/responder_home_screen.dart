import 'package:flutter/material.dart';
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
import '../../providers/incident_provider.dart';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import '../../services/marker_helper.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/incident_card_widget.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final user = context.read<AuthProvider>().user;
      setState(() => _isAvailable = user?.isAvailable ?? false);

      final active = context.read<IncidentProvider>().activeIncident;
      if (active != null && active.isActive) {
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
                      fontSize: 13, height: 1.4, color: AppColors.textDark),
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
                          fontSize: 13, color: AppColors.textMedium)),
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
    await provider.acceptIncident(incident.id);
    if (!mounted) return;
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
    final roleIcon =
        isAmbulance ? Icons.local_shipping_rounded : Icons.medical_services_rounded;
    final roleAsset = AppAssets.forRole(user?.role ?? AppRoles.ambulance);
    final firstName = user?.name.split(' ').first ?? 'Responder';

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.primaryDark,
      drawer: _buildDrawer(user?.name ?? 'Responder', roleLabel, roleIcon),
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
                        padding: EdgeInsets.fromLTRB(20, topInset, 20, 32),
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
                              Container(
                                width: 58,
                                height: 58,
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceAlt,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                padding: const EdgeInsets.all(9),
                                child: SvgPicture.asset(roleAsset,
                                    fit: BoxFit.contain),
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
                                    Text('$roleLabel · Responder mode',
                                        style: const TextStyle(
                                            fontSize: 13,
                                            color: AppColors.textMedium)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),

                          // Duty toggle.
                          _dutyToggle(),
                          const SizedBox(height: 22),

                          // Statistics.
                          const Text('Overview',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textMedium,
                                  letterSpacing: 0.3)),
                          const SizedBox(height: 12),
                          _statsRow(incidents.length),
                          const SizedBox(height: 22),

                          // Incoming incidents / status.
                          _incidentsSection(incidents),
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
            const Spacer(),
            _dutyPill(),
            const Spacer(),
            _circleBtn(
              icon: Icons.person_outline_rounded,
              onTap: () => Navigator.pushNamed(context, AppRoutes.profile),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleBtn({required IconData icon, required VoidCallback onTap}) {
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
        child: Icon(icon, color: AppColors.textDark, size: 22),
      ),
    );
  }

  // Duty status pill in the top bar — tap to go on / off duty.
  Widget _dutyPill() {
    return GestureDetector(
      onTap: () => _toggleAvailability(!_isAvailable),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: _isAvailable ? AppColors.accent : AppColors.textDark,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
                color: (_isAvailable ? AppColors.accent : Colors.black)
                    .withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(_isAvailable ? 'On Duty' : 'Off Duty',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
          ],
        ),
      ),
    );
  }

  // ── Live map with incoming-incident pins + a floating stat badge ───────────
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

        // Floating badge below the top bar — live incoming count.
        Positioned(
          top: 72,
          left: 16,
          child: SafeArea(
            bottom: false,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: incidents.isEmpty ? AppColors.textDark : AppColors.accent,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 8),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                      incidents.isEmpty
                          ? Icons.check_circle_rounded
                          : Icons.warning_amber_rounded,
                      color: Colors.white,
                      size: 14),
                  const SizedBox(width: 5),
                  Text(
                    incidents.isEmpty
                        ? 'No incidents nearby'
                        : '${incidents.length} incoming near you',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
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

    if (incidents.isEmpty) {
      return const _StatusBlock(
        title: 'All clear nearby',
        message:
            "You're on duty. We'll alert you the moment a new incident comes in.",
        icon: Icons.check_circle_outline,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                      fontSize: 13)),
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
                  fontSize: 13.5,
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

  Widget _buildDrawer(String name, String roleLabel, IconData roleIcon) {
    return AppDrawer(
      name: name,
      subtitle: roleLabel,
      subtitleIcon: roleIcon,
      statusText: _isAvailable ? 'On Duty' : 'Off Duty',
      statusActive: _isAvailable,
      children: [
        DrawerTile(
          icon: Icons.dashboard_rounded,
          label: 'Dashboard',
          onTap: () => Navigator.pop(context),
        ),
        DrawerTile(
          icon: Icons.history_rounded,
          label: 'History',
          onTap: () {
            Navigator.pop(context);
            Navigator.pushNamed(context, AppRoutes.incidentHistory);
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
        DrawerTile(
          icon: Icons.play_circle_rounded,
          label: 'Tutorial',
          onTap: () {
            Navigator.pop(context);
            Navigator.pushNamed(context, AppRoutes.tutorial);
          },
        ),
        DrawerTile(
          icon: Icons.emergency_rounded,
          label: 'User',
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
                  fontSize: 12, color: AppColors.textMedium)),
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
                color: AppColors.textMedium, fontSize: 13, height: 1.5),
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
