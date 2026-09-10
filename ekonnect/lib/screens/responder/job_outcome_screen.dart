import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../models/incident_model.dart';
import '../../providers/incident_provider.dart';
import '../../services/firestore_service.dart';

/// What happens when a crew is on scene and the job is not simply done.
///
/// Lifted off the active job screen, which had four tiles competing with the
/// map, the patient card, the navigation controls and Resolve. A crew standing
/// over a patient should see one clear question at a time, not a control panel.
///
/// Two acts, in one place because they are one thought:
///   1. choose the outcome;
///   2. for the two that summon someone else, wait with the patient until they
///      arrive — rather than dropping the crew back on a home screen and
///      leaving nobody watching.
enum _Phase { choosing, awaitingBackup, awaitingHandover, done }

class JobOutcomeScreen extends StatefulWidget {
  final IncidentModel incident;

  /// Opens the referral sheet on the parent, which owns the map and the
  /// origin coordinates the search needs.
  final Future<void> Function() onRefer;

  const JobOutcomeScreen({
    super.key,
    required this.incident,
    required this.onRefer,
  });

  @override
  State<JobOutcomeScreen> createState() => _JobOutcomeScreenState();
}

class _JobOutcomeScreenState extends State<JobOutcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  _Phase _phase = _Phase.choosing;

  StreamSubscription? _watch;
  IncidentModel? _live;
  DateTime? _waitingSince;
  Timer? _tick;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _watch?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  /// Watches the incident directly rather than through the provider: handing a
  /// call on releases this responder, so the provider's active incident is
  /// gone by the time we need to know whether anyone picked it up.
  void _startWatching(_Phase phase) {
    setState(() {
      _phase = phase;
      _waitingSince = DateTime.now();
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _watch = FirestoreService.streamIncident(widget.incident.id).listen((i) {
      if (!mounted || i == null) return;
      setState(() => _live = i);

      final answered = phase == _Phase.awaitingBackup
          ? i.assignees.length > 1
          : i.assignedTo != null;
      if (answered) {
        _tick?.cancel();
        setState(() => _phase = _Phase.done);
      }
    });
  }

  String get _elapsed {
    final from = _waitingSince;
    if (from == null) return '';
    final s = DateTime.now().difference(from).inSeconds;
    return s < 60 ? '${s}s' : '${s ~/ 60}m ${(s % 60).toString().padLeft(2, '0')}s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        title: Text(
          _phase == _Phase.choosing ? 'What happens next?' : 'Getting more help',
          style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 17, color: AppColors.textDark),
        ),
        // No way out mid-wait except the explicit action below: an accidental
        // back-swipe should not silently abandon a summoned crew.
        automaticallyImplyLeading: _phase == _Phase.choosing,
      ),
      body: switch (_phase) {
        _Phase.choosing => _chooser(),
        _Phase.done => _arrived(),
        _ => _waiting(),
      },
    );
  }

  // ── Act one: the choice ──────────────────────────────────────────────────

  Widget _chooser() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 18, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'You are on scene with ${widget.incident.userName}. '
                  'Pick what this job needs — nothing is closed until you say so.',
                  style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.textMedium),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _Option(
          icon: Icons.local_hospital_rounded,
          colour: AppColors.accent,
          title: 'Refer to a care point',
          body: 'The patient needs a hospital or clinic. Search nearby '
              'facilities and record where you are taking them.',
          onTap: () async {
            await widget.onRefer();
            if (mounted) Navigator.pop(context);
          },
        ),
        _Option(
          icon: Icons.group_add_rounded,
          colour: AppColors.primary,
          title: 'Request backup',
          body: 'You stay on the job and a second crew joins you. For more '
              'casualties than you can carry, or a lift you cannot manage alone.',
          busy: _busy == 'backup',
          onTap: () => _reasonThen(
            title: 'Request backup',
            hint: 'Two casualties, need another stretcher',
            confirm: 'Request backup',
            tag: 'backup',
            act: (r) async {
              await context.read<IncidentProvider>().requestBackup(r);
              _startWatching(_Phase.awaitingBackup);
            },
          ),
        ),
        _Option(
          icon: Icons.campaign_rounded,
          colour: AppColors.warning,
          title: 'Hand to another team',
          body: 'A different crew is better placed than you. The call goes '
              'back out — you stay with the patient until someone takes it.',
          busy: _busy == 'handover',
          onTap: () => _reasonThen(
            title: 'Hand to another team',
            hint: 'Fire incident, we are a medical crew',
            confirm: 'Hand it on',
            tag: 'handover',
            danger: true,
            act: (r) async {
              await context.read<IncidentProvider>().rebroadcast(r);
              _startWatching(_Phase.awaitingHandover);
            },
          ),
        ),
        _Option(
          icon: Icons.do_not_disturb_on_outlined,
          colour: AppColors.emergency,
          title: 'Close — not resolved',
          body: 'You attended but the job could not be finished. Recorded as '
              'care not delivered, not as a false alarm.',
          busy: _busy == 'close',
          onTap: () => _reasonThen(
            title: 'Close without resolving',
            hint: 'No ambulance available for transport',
            confirm: 'Close unresolved',
            tag: 'close',
            danger: true,
            act: (r) async {
              final nav = Navigator.of(context);
              final provider = context.read<IncidentProvider>();
              // The incident this screen was opened with — the provider's own
              // copy is not guaranteed to be there.
              final closed = await provider.closeUnresolved(r,
                  incident: widget.incident);
              if (!mounted) return;
              if (!closed) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(provider.error ?? 'Could not close this job.'),
                  backgroundColor: AppColors.emergency,
                ));
                return;
              }
              nav.pushNamedAndRemoveUntil(AppRoutes.responderHome, (_) => false);
            },
          ),
        ),
      ],
    );
  }

  // ── Act two: waiting, in the shape of the patient's own waiting screen ───

  Widget _waiting() {
    final backup = _phase == _Phase.awaitingBackup;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
      child: Column(
        children: [
          const Spacer(),
          _Radar(pulse: _pulse, icon: backup ? Icons.group_add_rounded : Icons.campaign_rounded),
          const SizedBox(height: 32),
          Text(
            backup ? 'Looking for a second crew' : 'Looking for another team',
            style: const TextStyle(
                fontSize: 21, fontWeight: FontWeight.bold, color: AppColors.textDark),
          ),
          const SizedBox(height: 10),
          Text(
            backup
                ? 'Nearby crews have been alerted. Stay with the patient — '
                    'this job is still yours.'
                : 'The call is back on the network. Stay with the patient '
                    'until another crew accepts it.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.textMedium),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: AppColors.divider),
            ),
            child: Text('Waiting $_elapsed',
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textMedium)),
          ),
          const Spacer(),
          if (!backup)
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.accent),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Do not leave until another crew accepts, or the patient '
                      'is left with nobody.',
                      style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.textMedium),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              backup ? 'Back to the job' : 'Back to the job while I wait',
              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _arrived() {
    final backup = _phase == _Phase.done && _live != null && _live!.assignees.length > 1;
    final who = backup
        ? (_live!.assignees.lastWhere((a) => a['primary'] != true,
            orElse: () => {'name': 'Another crew'})['name'] as String?)
        : _live?.assignedToName;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded, size: 46, color: AppColors.primary),
          ),
          const SizedBox(height: 26),
          Text(
            '${who ?? 'A crew'} has taken it',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 21, fontWeight: FontWeight.bold, color: AppColors.textDark),
          ),
          const SizedBox(height: 10),
          Text(
            backup
                ? 'They are on their way to join you. The job stays yours.'
                : 'They now own this call. You are free to stand down.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.textMedium),
          ),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                if (backup) {
                  Navigator.pop(context);
                } else {
                  Navigator.pushNamedAndRemoveUntil(
                      context, AppRoutes.responderHome, (_) => false);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(backup ? 'Back to the job' : 'Done'),
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared reason prompt ─────────────────────────────────────────────────

  Future<void> _reasonThen({
    required String title,
    required String hint,
    required String confirm,
    required String tag,
    required Future<void> Function(String reason) act,
    bool danger = false,
  }) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 2,
          decoration: InputDecoration(
            hintText: hint,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Back')),
          ElevatedButton(
            onPressed: () {
              final v = controller.text.trim();
              if (v.isEmpty) return;
              Navigator.pop(ctx, v);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: danger ? AppColors.emergency : AppColors.primary),
            child: Text(confirm),
          ),
        ],
      ),
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = tag);
    try {
      await act(reason);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }
}

/// One outcome, stated plainly with its consequence.
class _Option extends StatelessWidget {
  final IconData icon;
  final Color colour;
  final String title;
  final String body;
  final VoidCallback onTap;
  final bool busy;

  const _Option({
    required this.icon,
    required this.colour,
    required this.title,
    required this.body,
    required this.onTap,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: busy ? null : onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colour.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: busy
                      ? Padding(
                          padding: const EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: colour),
                        )
                      : Icon(icon, color: colour, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textDark)),
                      const SizedBox(height: 4),
                      Text(body,
                          style: const TextStyle(
                              fontSize: 13,
                              height: 1.45,
                              color: AppColors.textMedium)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textLight, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The same expanding rings the patient sees while waiting for a responder —
/// deliberately, so "someone is being looked for" reads identically on both
/// sides of the network.
class _Radar extends StatelessWidget {
  final AnimationController pulse;
  final IconData icon;
  const _Radar({required this.pulse, required this.icon});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      height: 190,
      child: AnimatedBuilder(
        animation: pulse,
        builder: (_, _) => Stack(
          alignment: Alignment.center,
          children: [
            for (var i = 0; i < 3; i++)
              _ring((pulse.value + i / 3) % 1.0),
            Container(
              width: 78,
              height: 78,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 34),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ring(double t) {
    return Container(
      width: 78 + (190 - 78) * t,
      height: 78 + (190 - 78) * t,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.primary.withValues(alpha: (1 - t) * 0.45),
          width: 2,
        ),
      ),
    );
  }
}
