import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/app_assets.dart';
import '../../core/constants.dart';
import '../../services/ai_service.dart';
import '../../services/speech_service.dart';

/// What the user ended up with after describing their emergency out loud.
class VoiceReportResult {
  final String type;
  final String? notes;
  const VoiceReportResult(this.type, this.notes);
}

/// Spoken emergency reporting: the caller describes what is happening, the
/// transcript is triaged by AI, and the result pre-fills the SOS.
///
/// Safety stance throughout: the AI is an accelerator, never a gate. Every
/// failure path — no mic, no recognition, no network, unparseable reply, low
/// confidence — still lets the user send an SOS by picking a category by hand.
class VoiceReportSheet extends StatefulWidget {
  const VoiceReportSheet({super.key});

  @override
  State<VoiceReportSheet> createState() => _VoiceReportSheetState();
}

enum _Stage { idle, listening, analysing, result, unavailable }

class _VoiceReportSheetState extends State<VoiceReportSheet>
    with SingleTickerProviderStateMixin {
  final _speech = SpeechService.instance;
  late final AnimationController _pulse;

  _Stage _stage = _Stage.idle;
  String _transcript = '';
  EmergencyAnalysis? _analysis;
  String? _failureNote;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    // Release the mic immediately — never leave it open behind a closed sheet.
    _speech.cancel();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _startListening() async {
    final ready = await _speech.init();
    if (!mounted) return;
    if (!ready) {
      setState(() {
        _stage = _Stage.unavailable;
        _failureNote =
            'Speech recognition is not available on this device. You can still '
            'choose an emergency type yourself.';
      });
      return;
    }

    setState(() {
      _stage = _Stage.listening;
      _transcript = '';
      _analysis = null;
      _failureNote = null;
    });

    await _speech.listen(
      onResult: (text, isFinal) {
        if (!mounted) return;
        setState(() => _transcript = text);
        if (isFinal && text.trim().isNotEmpty) _analyse();
      },
    );
  }

  Future<void> _stopAndAnalyse() async {
    await _speech.stop();
    if (!mounted) return;
    if (_transcript.trim().isEmpty) {
      setState(() => _stage = _Stage.idle);
      return;
    }
    _analyse();
  }

  Future<void> _analyse() async {
    if (_stage == _Stage.analysing) return;
    setState(() => _stage = _Stage.analysing);

    final analysis = await AiService.analyseReport(_transcript);
    if (!mounted) return;

    if (analysis == null) {
      // AI unreachable or unparseable — do not block the emergency.
      setState(() {
        _stage = _Stage.unavailable;
        _failureNote =
            'Could not analyse the description right now. Choose the emergency '
            'type yourself and your words will still be sent to the responder.';
      });
      return;
    }
    setState(() {
      _analysis = analysis;
      _stage = _Stage.result;
    });
  }

  void _confirm(String type) {
    final analysis = _analysis;
    Navigator.pop(
      context,
      VoiceReportResult(
        type,
        analysis != null
            ? analysis.toIncidentNotes()
            : (_transcript.trim().isEmpty
                ? null
                : 'Caller said: "${_transcript.trim()}"'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _header(),
              const SizedBox(height: 18),
              ..._stageBody(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final (title, subtitle) = switch (_stage) {
      _Stage.idle => (
          'Describe your emergency',
          'Tap the microphone and say what is happening. We will work out who to send.'
        ),
      _Stage.listening => (
          'Listening…',
          'Speak naturally. Tap stop when you are done.'
        ),
      _Stage.analysing => ('Analysing…', 'Working out the right responder.'),
      _Stage.result => ('Here is what we understood', 'Check this looks right.'),
      _Stage.unavailable => ('Choose manually', _failureNote ?? ''),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style:
                const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(subtitle,
            style: const TextStyle(
                fontSize: 14, color: AppColors.textMedium, height: 1.35)),
      ],
    );
  }

  List<Widget> _stageBody() {
    switch (_stage) {
      case _Stage.idle:
        return [_micButton(), const SizedBox(height: 14), _call999Hint()];

      case _Stage.listening:
        return [
          _transcriptBox(),
          const SizedBox(height: 16),
          _micButton(listening: true),
          const SizedBox(height: 10),
          _secondaryButton('Stop and analyse', _stopAndAnalyse),
        ];

      case _Stage.analysing:
        return [
          _transcriptBox(),
          const SizedBox(height: 20),
          const Center(
            child: SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 20),
        ];

      case _Stage.result:
        return [_analysisCard(), const SizedBox(height: 16), _resultActions()];

      case _Stage.unavailable:
        return [
          if (_transcript.trim().isNotEmpty) ...[
            _transcriptBox(),
            const SizedBox(height: 16),
          ],
          _manualTypeGrid(),
          const SizedBox(height: 12),
          _secondaryButton('Try voice again', _startListening),
        ];
    }
  }

  Widget _micButton({bool listening = false}) {
    return Center(
      child: GestureDetector(
        onTap: listening ? _stopAndAnalyse : _startListening,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (_, _) {
            final scale = listening ? 1 + (_pulse.value * 0.08) : 1.0;
            return Transform.scale(
              scale: scale,
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: listening ? AppColors.emergency : AppColors.primary,
                  boxShadow: [
                    BoxShadow(
                      color: (listening
                              ? AppColors.emergency
                              : AppColors.primary)
                          .withValues(alpha: listening ? 0.35 : 0.25),
                      blurRadius: listening ? 26 : 16,
                      spreadRadius: listening ? 4 : 0,
                    ),
                  ],
                ),
                child: Icon(
                  listening ? Icons.stop_rounded : Icons.mic_rounded,
                  color: Colors.white,
                  size: 38,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _transcriptBox() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        _transcript.isEmpty ? 'Waiting for you to speak…' : _transcript,
        style: TextStyle(
          fontSize: 15,
          height: 1.4,
          color: _transcript.isEmpty
              ? AppColors.textMedium
              : AppColors.textDark,
          fontStyle: _transcript.isEmpty ? FontStyle.italic : FontStyle.normal,
        ),
      ),
    );
  }

  Widget _analysisCard() {
    final a = _analysis!;
    final color = IncidentType.color(a.type);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(IncidentType.icon(a.type), color: color, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  IncidentType.label(a.type),
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold, color: color),
                ),
              ),
              _severityChip(a.severity),
            ],
          ),
          if (a.summary.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(a.summary,
                style: const TextStyle(
                    fontSize: 14, height: 1.4, color: AppColors.textDark)),
          ],
          if (a.keyFacts.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final fact in a.keyFacts)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('• $fact',
                    style: const TextStyle(
                        fontSize: 14, color: AppColors.textMedium)),
              ),
          ],
          if (a.advice.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline,
                      size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(a.advice,
                        style: const TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: AppColors.textDark)),
                  ),
                ],
              ),
            ),
          ],
          // A low-confidence guess must be visible, not buried — the user is
          // the one who knows what is actually happening.
          if (!a.isConfident) ...[
            const SizedBox(height: 10),
            Text(
              'We are not fully sure from the description. Please confirm the '
              'type below.',
              style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textMedium.withValues(alpha: 0.95)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _severityChip(String severity) {
    final (label, color) = switch (severity) {
      'critical' => ('CRITICAL', AppColors.emergency),
      'moderate' => ('MODERATE', AppColors.textMedium),
      _ => ('URGENT', AppColors.accent),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11.5, fontWeight: FontWeight.bold, color: color)),
    );
  }

  Widget _resultActions() {
    final a = _analysis!;
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.send_rounded, size: 18),
            label: Text('Send ${IncidentType.label(a.type)}'),
            style: ElevatedButton.styleFrom(
              backgroundColor: IncidentType.color(a.type),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => _confirm(a.type),
          ),
        ),
        const SizedBox(height: 10),
        _secondaryButton('Pick a different type', () {
          setState(() => _stage = _Stage.unavailable);
        }),
      ],
    );
  }

  Widget _manualTypeGrid() {
    const types = [
      IncidentType.medical,
      IncidentType.fire,
      IncidentType.flood,
      IncidentType.security,
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final t in types)
          SizedBox(
            width: (MediaQuery.of(context).size.width - 50) / 2,
            child: OutlinedButton.icon(
              icon: Icon(IncidentType.icon(t), size: 18),
              label: Text(IncidentType.label(t),
                  style: const TextStyle(fontSize: 13)),
              style: OutlinedButton.styleFrom(
                foregroundColor: IncidentType.color(t),
                side: BorderSide(
                    color: IncidentType.color(t).withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => _confirm(t),
            ),
          ),
      ],
    );
  }

  Widget _secondaryButton(String label, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(foregroundColor: AppColors.textMedium),
        child: Text(label),
      ),
    );
  }

  Widget _call999Hint() {
    return Text(
      'If this is immediately life-threatening, call 999 as well as sending an SOS.',
      textAlign: TextAlign.center,
      style: TextStyle(
          fontSize: 12.5, color: AppColors.textMedium.withValues(alpha: 0.9)),
    );
  }
}

/// Persistent nudge to finish setting up an account.
///
/// Replaces the old blocking profile-setup screen. It stays on the home screen
/// until the details are filled in, but never prevents an SOS — an incomplete
/// profile makes help slower, not impossible.
class ProfilePromptCard extends StatelessWidget {
  final double progress;
  final List<String> missing;
  final VoidCallback onTap;

  const ProfilePromptCard({
    super.key,
    required this.progress,
    required this.missing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (progress * 100).round();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 42,
              height: 42,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 42,
                    height: 42,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 4,
                      backgroundColor: AppColors.accent.withValues(alpha: 0.18),
                      valueColor:
                          const AlwaysStoppedAnimation(AppColors.accent),
                    ),
                  ),
                  Text('$pct%',
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: AppColors.accent)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Finish setting up your profile',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark)),
                  const SizedBox(height: 2),
                  Text(
                    // Naming what is missing is far more actionable than a
                    // generic "incomplete profile" nag.
                    'Still needed: ${missing.take(2).join(', ')}'
                    '${missing.length > 2 ? ' +${missing.length - 2} more' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textMedium),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.accent, size: 22),
          ],
        ),
      ),
    );
  }
}

/// Entry point for [VoiceReportSheet].
///
/// Reads as a slim pill attached beneath the SOS selector rather than a card of
/// its own: this is a second door into the *same* action, not a competing one,
/// so it must stay visually subordinate to the SOS button above it.
class VoiceReportButton extends StatelessWidget {
  final VoidCallback onTap;
  const VoiceReportButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.primarySoft,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            SvgPicture.asset(AppAssets.mic, width: 22, height: 22),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Not sure? Describe it out loud',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: AppColors.primary.withValues(alpha: 0.7), size: 20),
          ],
        ),
      ),
    );
  }
}
