import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../models/incident_model.dart';
import '../../providers/incident_provider.dart';
import '../../services/firestore_service.dart';
import '../../services/marker_helper.dart';

class IncidentCardScreen extends StatefulWidget {
  final String incidentId;
  const IncidentCardScreen({super.key, required this.incidentId});

  @override
  State<IncidentCardScreen> createState() => _IncidentCardScreenState();
}

class _IncidentCardScreenState extends State<IncidentCardScreen> {
  bool _accepting = false;
  final Map<String, BitmapDescriptor> _markerCache = {};

  Future<BitmapDescriptor> _markerFor(String type) async {
    if (_markerCache.containsKey(type)) return _markerCache[type]!;
    final icon = await MarkerHelper.incidentPin(type);
    _markerCache[type] = icon;
    return icon;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Incident Details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<IncidentModel?>(
        stream: FirestoreService.streamIncident(widget.incidentId),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final incident = snap.data!;
          final color = IncidentType.color(incident.type);
          final alreadyTaken = incident.assignedTo != null;
          final isClosed = incident.isClosed;

          return Column(
            children: [
              // ── Map ─────────────────────────────────────────────
              SizedBox(
                height: 240,
                child: FutureBuilder<BitmapDescriptor>(
                  future: _markerFor(incident.type),
                  builder: (ctx, markerSnap) => GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: LatLng(incident.userLat, incident.userLng),
                      zoom: 15.5,
                    ),
                    zoomControlsEnabled: false,
                    markers: {
                      Marker(
                        markerId: const MarkerId('incident'),
                        position:
                            LatLng(incident.userLat, incident.userLng),
                        icon: markerSnap.data ??
                            BitmapDescriptor.defaultMarkerWithHue(
                                BitmapDescriptor.hueRed),
                        anchor: const Offset(0.5, 0.85),
                        infoWindow: InfoWindow(
                          title: IncidentType.label(incident.type),
                          snippet: incident.userName,
                        ),
                      ),
                    },
                  ),
                ),
              ),

              // ── Details ─────────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Type header row
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(IncidentType.icon(incident.type),
                                color: color, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                IncidentType.label(incident.type),
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(color: color),
                              ),
                              Text(
                                _timeAgo(incident.createdAt),
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textMedium),
                              ),
                            ],
                          ),
                          const Spacer(),
                          // Status badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _statusColor(incident.status)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: _statusColor(incident.status)
                                      .withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              IncidentStatus.label(incident.status),
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: _statusColor(incident.status),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),

                      // Caller info card
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.divider),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              const Icon(Icons.person_pin_circle_outlined,
                                  size: 14,
                                  color: AppColors.textMedium),
                              const SizedBox(width: 6),
                              const Text('Caller Info',
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textMedium,
                                      letterSpacing: 0.5)),
                            ]),
                            const SizedBox(height: 10),
                            _Row(
                              icon: Icons.person_outline,
                              label: incident.userName.isNotEmpty
                                  ? incident.userName
                                  : 'Unknown',
                            ),
                            const SizedBox(height: 8),
                            _Row(
                              icon: Icons.phone_outlined,
                              label: incident.userPhone.isNotEmpty
                                  ? incident.userPhone
                                  : 'No phone on file',
                              highlight: true,
                            ),
                          ],
                        ),
                      ),

                      if (alreadyTaken && incident.assignedToName != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color:
                                    AppColors.primary.withValues(alpha: 0.2)),
                          ),
                          child: Row(children: [
                            const Icon(Icons.verified_user_outlined,
                                size: 16, color: AppColors.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Assigned to ${incident.assignedToName}',
                                style: const TextStyle(
                                    fontSize: 14,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ]),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // ── Accept button ────────────────────────────────────
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: ElevatedButton.icon(
                    onPressed: (alreadyTaken || isClosed || _accepting)
                        ? null
                        : () => _accept(context, incident),
                    icon: _accepting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white))
                        : const Icon(Icons.check_circle_outline, size: 20),
                    label: Text(
                      isClosed
                          ? 'Incident Closed'
                          : alreadyTaken
                              ? 'Already Assigned'
                              : 'Accept Incident',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _accept(BuildContext context, IncidentModel incident) async {
    setState(() => _accepting = true);
    final provider = context.read<IncidentProvider>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final won = await provider.acceptIncident(incident.id);
    if (!context.mounted) return;

    if (!won) {
      // Losing the race is ordinary. Say so and send them back to the list
      // rather than opening a job that belongs to somebody else.
      setState(() => _accepting = false);
      messenger.showSnackBar(SnackBar(
        content: Text(provider.error ?? 'Could not take this call.'),
        backgroundColor: AppColors.textDark,
      ));
      nav.pop();
      return;
    }
    nav.pushReplacementNamed(AppRoutes.activeJob, arguments: incident.id);
  }

  Color _statusColor(String status) {
    switch (status) {
      case IncidentStatus.pending:
        return AppColors.warning;
      case IncidentStatus.assigned:
      case IncidentStatus.enRoute:
        return AppColors.primary;
      case IncidentStatus.arrived:
        return AppColors.info;
      case IncidentStatus.resolved:
        return AppColors.success;
      default:
        return AppColors.textMedium;
    }
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool highlight;

  const _Row({required this.icon, required this.label, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final color = highlight ? AppColors.primary : AppColors.textMedium;
    return Row(children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: highlight ? AppColors.primary : AppColors.textDark,
            fontWeight:
                highlight ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    ]);
  }
}
