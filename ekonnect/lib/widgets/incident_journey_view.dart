import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/constants.dart';
import '../models/incident_event.dart';
import '../models/incident_model.dart';

/// The full story of an emergency: what happened, when, and how long each part
/// took.
///
/// Deliberately one widget for both the patient's history and the admin view.
/// If they diverged, a patient could be shown a different account of their own
/// emergency than the one being audited — which is exactly the sort of gap that
/// destroys trust in a system like this.
class IncidentJourneyView extends StatelessWidget {
  final IncidentModel incident;

  /// Admins see operational metrics; patients see the narrative only.
  final bool showMetrics;

  const IncidentJourneyView({
    super.key,
    required this.incident,
    this.showMetrics = false,
  });

  @override
  Widget build(BuildContext context) {
    final timings = IncidentTimings.from(incident.timeline);
    final events = timings.events;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showMetrics) ...[
          _metrics(timings),
          const SizedBox(height: 18),
        ],
        if (events.isEmpty)
          const Text('No journey recorded for this incident.',
              style: TextStyle(fontSize: 14, color: AppColors.textMedium))
        else
          for (var i = 0; i < events.length; i++)
            _EventRow(
              event: events[i],
              isFirst: i == 0,
              isLast: i == events.length - 1,
              // The gap since the previous step — where the time actually went.
              sincePrevious: i == 0
                  ? null
                  : events[i].at.difference(events[i - 1].at),
            ),
        if (timings.declinedCount > 0) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 16, color: AppColors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${timings.declinedCount} care point'
                    '${timings.declinedCount > 1 ? 's' : ''} could not take '
                    'this patient.',
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textDark),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _metrics(IncidentTimings t) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _metric('Waited for a responder', IncidentTimings.format(t.timeToAccept)),
        _metric('Time to reach patient', IncidentTimings.format(t.timeToReach)),
        _metric('Total response', IncidentTimings.format(t.totalResponseTime)),
        _metric('On scene', IncidentTimings.format(t.timeOnScene)),
        _metric('Whole incident', IncidentTimings.format(t.totalDuration)),
        for (final leg in t.transportLegs)
          _metric(
            'To ${leg.carePoint}',
            leg.arrived == null
                ? 'in transit'
                : IncidentTimings.format(leg.arrived!.difference(leg.departed)),
          ),
      ],
    );
  }

  Widget _metric(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    fontSize: 12.5, color: AppColors.textMedium)),
          ],
        ),
      );
}

class _EventRow extends StatelessWidget {
  final IncidentEvent event;
  final bool isFirst;
  final bool isLast;
  final Duration? sincePrevious;

  const _EventRow({
    required this.event,
    required this.isFirst,
    required this.isLast,
    required this.sincePrevious,
  });

  @override
  Widget build(BuildContext context) {
    final colour = _colourFor(event.type);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Rail
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(top: 3),
                decoration: BoxDecoration(
                  color: colour,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                        color: colour.withValues(alpha: 0.35), blurRadius: 5)
                  ],
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: AppColors.divider,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          event.label,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: colour),
                        ),
                      ),
                      Text(
                        DateFormat('HH:mm').format(event.at),
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textDark),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        DateFormat('d MMM').format(event.at),
                        style: const TextStyle(
                            fontSize: 12.5, color: AppColors.textMedium),
                      ),
                      if (sincePrevious != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          '+${IncidentTimings.format(sincePrevious)}',
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textLight),
                        ),
                      ],
                      if (event.actorName != null) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            event.actorName!,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12.5, color: AppColors.textMedium),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if ((event.note ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        event.note!,
                        style: const TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: AppColors.textDark),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Color _colourFor(String type) {
    switch (type) {
      case IncidentEventType.created:
        return AppColors.accent;
      case IncidentEventType.resolved:
      case IncidentEventType.arrivedAt:
        return AppColors.success;
      case IncidentEventType.cancelled:
      case IncidentEventType.declined:
        return AppColors.emergency;
      default:
        return AppColors.primary;
    }
  }
}
