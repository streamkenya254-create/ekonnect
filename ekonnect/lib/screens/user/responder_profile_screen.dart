import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../models/incident_model.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../widgets/user_avatar.dart';

/// Who is coming, in full.
///
/// The waiting screen's job is the map and the ETA. Everything else about the
/// crew — licence, vehicle, organisation, how to reach them — lives here, so
/// the card on that screen can shrink to a face and stop covering the map the
/// patient is watching.
class ResponderProfileScreen extends StatefulWidget {
  final IncidentModel incident;
  const ResponderProfileScreen({super.key, required this.incident});

  @override
  State<ResponderProfileScreen> createState() => _ResponderProfileScreenState();
}

class _ResponderProfileScreenState extends State<ResponderProfileScreen> {
  UserModel? _responder;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.incident.assignedTo;
    if (id == null) return;
    try {
      final u = await FirestoreService.getUser(id);
      if (mounted) setState(() => _responder = u);
    } catch (_) {/* the incident already carries enough to be useful */}
  }

  Future<void> _call() async {
    final number = (widget.incident.assignedToPhone ?? '').trim();
    if (number.isEmpty) return;
    await launchUrl(Uri(scheme: 'tel', path: number));
  }

  void _chat() {
    Navigator.pushNamed(context, AppRoutes.chat, arguments: {
      'incidentId': widget.incident.id,
      'otherName': widget.incident.assignedToName ?? 'Responder',
      'otherPhone': widget.incident.assignedToPhone ?? '',
    });
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.incident;
    final colour = IncidentType.color(i.type);
    final name = i.assignedToName ?? 'Responder';
    final phone = (i.assignedToPhone ?? '').trim();

    final facts = <(String, String)>[
      if ((i.assignedToRole ?? '').isNotEmpty)
        ('Role', AppRoles.displayLabel(i.assignedToRole!)),
      if ((i.assignedToSpecialization ?? '').isNotEmpty)
        ('Specialisation', i.assignedToSpecialization!),
      if ((i.assignedToLicenseNumber ?? '').isNotEmpty)
        ('Licence', i.assignedToLicenseNumber!),
      if ((i.assignedToVehicleNumber ?? '').isNotEmpty)
        ('Vehicle', i.assignedToVehicleNumber!),
      if ((i.assignedToFacilityName ?? '').isNotEmpty)
        ('Care Point', i.assignedToFacilityName!),
      ('Phone', phone.isEmpty ? 'Not given' : phone),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 300,
            backgroundColor: colour,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [colour, colour.withValues(alpha: 0.72)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 30),
                        UserAvatar(
                          user: _responder,
                          fallbackName: name,
                          size: 112,
                          background: Colors.white.withValues(alpha: 0.18),
                          foreground: Colors.white,
                          ring: Colors.white.withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: AppText.pageTitleOnColor),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          i.assignedToRole != null
                              ? AppRoles.displayLabel(i.assignedToRole!)
                              : 'Emergency responder',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 14,
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: phone.isEmpty ? null : _call,
                          icon: const Icon(Icons.call_rounded, size: 20),
                          label: const Text('Call'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _chat,
                          icon: const Icon(Icons.chat_bubble_outline, size: 19),
                          label: const Text('Chat'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Credentials', style: AppText.sectionTitle),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final f in facts) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(f.$1, style: AppText.cardTitle),
                                const SizedBox(height: AppSpacing.xs),
                                Text(f.$2, style: AppText.body),
                              ],
                            ),
                          ),
                          if (f != facts.last)
                            const Divider(
                                height: 1, color: AppColors.divider),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
