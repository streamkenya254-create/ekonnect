import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../models/incident_model.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../widgets/user_avatar.dart';

/// Who the crew is treating, in full.
///
/// This used to be a bottom sheet, and the card that opened it carried a
/// duplicate of everything on it — the name, a call button, a message button.
/// A crew on scene needs the card to be almost empty and this page to be
/// complete, not the two of them half-overlapping.
class PatientScreen extends StatefulWidget {
  final IncidentModel incident;
  const PatientScreen({super.key, required this.incident});

  @override
  State<PatientScreen> createState() => _PatientScreenState();
}

class _PatientScreenState extends State<PatientScreen> {
  UserModel? _patient;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// The photo and anything else the caller has since filled in lives on their
  /// user document, not on the incident. One read, on a page opened by choice.
  Future<void> _load() async {
    try {
      final u = await FirestoreService.getUser(widget.incident.userId);
      if (mounted) setState(() { _patient = u; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _call() async {
    final number = widget.incident.userPhone.trim();
    if (number.isEmpty) return;
    await launchUrl(Uri(scheme: 'tel', path: number));
  }

  void _message() {
    Navigator.pushNamed(context, AppRoutes.chat, arguments: {
      'incidentId': widget.incident.id,
      'otherName': widget.incident.userName,
      'otherPhone': widget.incident.userPhone,
    });
  }

  @override
  Widget build(BuildContext context) {
    final incident = widget.incident;
    final colour = IncidentType.color(incident.type);
    final name = incident.userName.isNotEmpty
        ? incident.userName
        : 'Unknown patient';
    final phone = incident.userPhone.trim();

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
                          user: _patient,
                          fallbackName: name,
                          size: 112,
                          background: Colors.white.withValues(alpha: 0.18),
                          foreground: Colors.white,
                          ring: Colors.white.withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: AppText.pageTitleOnColor),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(IncidentType.label(incident.type),
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 14,
                                fontWeight: FontWeight.w500)),
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
                  // The two things the card no longer carries.
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
                          onPressed: _message,
                          icon: const Icon(Icons.chat_bubble_outline, size: 19),
                          label: const Text('Message'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  Text('Contact', style: AppText.sectionTitle),
                  const SizedBox(height: 12),
                  _Card(children: [
                    _Row(
                      label: 'Phone',
                      value: phone.isEmpty ? 'Not given' : phone,
                      muted: phone.isEmpty,
                    ),
                    if (_loading)
                      const _Row(label: 'Email', value: 'Loading…', muted: true)
                    else
                      _Row(
                        label: 'Email',
                        value: (_patient?.email ?? '').isEmpty
                            ? 'Not given'
                            : _patient!.email,
                        muted: (_patient?.email ?? '').isEmpty,
                      ),
                  ]),

                  if ((incident.notes ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Text('What was reported', style: AppText.sectionTitle),
                    const SizedBox(height: 12),
                    _Card(children: [
                      Padding(
                        padding: const EdgeInsets.all(18),
                        child: Text(incident.notes!.trim(),
                            style: AppText.body
                                .copyWith(color: AppColors.textDark)),
                      ),
                    ]),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final c in children) ...[
              c,
              if (c != children.last)
                const Divider(height: 1, color: AppColors.divider),
            ],
          ],
        ),
      );
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool muted;
  const _Row({required this.label, required this.value, this.muted = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppText.cardTitle),
            const SizedBox(height: AppSpacing.xs),
            Text(value,
                style: AppText.body.copyWith(
                    color:
                        muted ? AppColors.textLight : AppColors.textMedium)),
          ],
        ),
      );
}
