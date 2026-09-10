import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/constants.dart';
import '../models/incident_model.dart';
import '../services/location_service.dart';

class IncidentCardWidget extends StatelessWidget {
  final IncidentModel incident;
  final VoidCallback onAccept;
  final double? currentLat;
  final double? currentLng;

  const IncidentCardWidget({
    super.key,
    required this.incident,
    required this.onAccept,
    this.currentLat,
    this.currentLng,
  });

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  Color _urgencyColor(DateTime dt) {
    final mins = DateTime.now().difference(dt).inMinutes;
    if (mins < 3) return AppColors.emergency;
    if (mins < 10) return AppColors.warning;
    return AppColors.success;
  }

  String _urgencyLabel(DateTime dt) {
    final mins = DateTime.now().difference(dt).inMinutes;
    if (mins < 3) return 'URGENT';
    if (mins < 10) return 'ACTIVE';
    return 'WAITING';
  }

  @override
  Widget build(BuildContext context) {
    final color = IncidentType.color(incident.type);
    final distance = (currentLat != null && currentLng != null)
        ? LocationService.distanceInKm(
            currentLat!, currentLng!, incident.userLat, incident.userLng)
        : null;
    final urgency = _urgencyColor(incident.createdAt);
    final urgencyLabel = _urgencyLabel(incident.createdAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border(left: BorderSide(color: color, width: 5)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: icon + type + urgency + distance
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(IncidentType.icon(incident.type),
                      color: color, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        IncidentType.label(incident.type),
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: color),
                      ),
                      Text(
                        DateFormat('HH:mm').format(incident.createdAt),
                        style: const TextStyle(
                            color: AppColors.textLight, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                // Urgency badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: urgency.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: urgency.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    urgencyLabel,
                    style: TextStyle(
                        color: urgency,
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Info row: user + time
            Row(
              children: [
                const Icon(Icons.person_outline,
                    size: 14, color: AppColors.textMedium),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    incident.userName.isNotEmpty
                        ? incident.userName
                        : 'Unknown',
                    style: const TextStyle(
                        color: AppColors.textMedium, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.access_time,
                    size: 14, color: AppColors.textMedium),
                const SizedBox(width: 4),
                Text(
                  _timeAgo(incident.createdAt),
                  style: const TextStyle(
                      color: AppColors.textMedium, fontSize: 14),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Bottom row: distance + accept button
            Row(
              children: [
                if (distance != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.navigation_outlined,
                            size: 13, color: color),
                        const SizedBox(width: 4),
                        Text(
                          '${distance.toStringAsFixed(1)} km away',
                          style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onAccept,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Accept',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 42),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
