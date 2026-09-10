import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flutter_svg/flutter_svg.dart';

import '../../core/app_assets.dart';
import '../../core/constants.dart';
import '../../models/incident_model.dart';
import '../../widgets/incident_journey_view.dart';

/// One emergency, in full.
///
/// This was a draggable sheet. A sheet is right for a quick confirmation, but
/// this is the record of someone's emergency — timings, referrals, who came,
/// how it ended — and it is the thing people scroll back through afterwards or
/// show to somebody else. That deserves a page it can be shared to, scrolled
/// properly and backed out of with the system gesture.
class IncidentDetailScreen extends StatelessWidget {
  final IncidentModel incident;
  const IncidentDetailScreen({super.key, required this.incident});

  @override
  Widget build(BuildContext context) {
    final colour = IncidentType.color(incident.type);
    final resolved = incident.status == IncidentStatus.resolved;
    final cancelled = incident.status == IncidentStatus.cancelled;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 230,
            backgroundColor: colour,
            foregroundColor: Colors.white,
            // No bar title: FlexibleSpaceBar keeps it on screen while
            // expanded, so the emergency was named twice at once — small in
            // the bar and large in the hero directly beneath it.
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [colour, colour.withValues(alpha: 0.72)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: -60,
                      right: -40,
                      child: Container(
                        width: 180,
                        height: 180,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.07),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomLeft,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 58),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 58,
                              height: 58,
                              padding: const EdgeInsets.all(9),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: SvgPicture.asset(
                                  AppAssets.forIncident(incident.type),
                                  fit: BoxFit.contain),
                            ),
                            const SizedBox(height: 14),
                            Text(IncidentType.label(incident.type),
                                style: AppText.pageTitleOnColor),
                            const SizedBox(height: 6),
                            Text(
                              DateFormat('EEEE d MMMM · HH:mm')
                                  .format(incident.createdAt),
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // How it ended, before the detail of how it went. Someone
                  // opening an old record wants the outcome first.
                  _Outcome(
                    label: IncidentStatus.label(incident.status),
                    tone: cancelled
                        ? AppColors.textLight
                        : resolved
                            ? AppColors.success
                            : AppColors.accent,
                    icon: cancelled
                        ? Icons.block_rounded
                        : resolved
                            ? Icons.check_circle_rounded
                            : Icons.pending_rounded,
                    who: incident.assignedToName,
                    facility: incident.assignedToFacilityName,
                  ),
                  const SizedBox(height: 22),

                  if ((incident.cancelReason ?? '').isNotEmpty)
                    _Note(
                      icon: Icons.info_outline,
                      label: 'Reason given',
                      text: CancelReasons.label(incident.cancelReason),
                    ),
                  if ((incident.closedReason ?? '').isNotEmpty)
                    _Note(
                      icon: Icons.do_not_disturb_on_outlined,
                      label: 'Closed without resolving',
                      text: incident.closedReason!,
                      tone: AppColors.accent,
                    ),
                  if ((incident.notes ?? '').trim().isNotEmpty)
                    _Note(
                      icon: Icons.notes_rounded,
                      label: 'What was reported',
                      text: incident.notes!,
                    ),

                  const SizedBox(height: 4),
                  Text('How it went', style: AppText.sectionTitle),
                  const SizedBox(height: 14),
                  IncidentJourneyView(incident: incident, showMetrics: true),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The verdict line: what happened to this call, and who answered it.
class _Outcome extends StatelessWidget {
  final String label;
  final Color tone;
  final IconData icon;
  final String? who;
  final String? facility;

  const _Outcome({
    required this.label,
    required this.tone,
    required this.icon,
    this.who,
    this.facility,
  });

  @override
  Widget build(BuildContext context) {
    final answered = (who ?? '').trim();
    final taken = (facility ?? '').trim();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tone.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: tone, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Outcome', style: AppText.fieldLabel),
                    const SizedBox(height: 3),
                    Text(label,
                        style: AppText.cardTitle.copyWith(color: tone)),
                  ],
                ),
              ),
            ],
          ),
          if (answered.isNotEmpty || taken.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(height: 1, color: AppColors.divider),
            const SizedBox(height: 14),
            if (answered.isNotEmpty)
              _line(Icons.person_rounded, 'Answered by', answered),
            if (taken.isNotEmpty) ...[
              if (answered.isNotEmpty) const SizedBox(height: 10),
              _line(Icons.local_hospital_rounded, 'Taken to', taken),
            ],
          ],
        ],
      ),
    );
  }

  Widget _line(IconData icon, String label, String value) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: AppColors.textLight),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppText.meta),
                const SizedBox(height: 2),
                Text(value, style: AppText.bodyStrong),
              ],
            ),
          ),
        ],
      );
}

/// A single framed remark above the timeline.
class _Note extends StatelessWidget {
  final IconData icon;
  final String label;
  final String text;
  final Color? tone;

  const _Note({
    required this.icon,
    required this.label,
    required this.text,
    this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final colour = tone ?? AppColors.textMedium;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colour.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colour),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(),
                    style: AppText.fieldLabel.copyWith(color: colour)),
                const SizedBox(height: 4),
                Text(text,
                    style: AppText.body.copyWith(color: AppColors.textDark)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
