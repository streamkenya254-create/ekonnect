import 'package:flutter/material.dart';

import '../../core/constants.dart';

/// What the user chose in [CancelReasonSheet].
///
/// The sheet only returns this on explicit confirm, so a null result always
/// means "keep the emergency active".
class CancelOutcome {
  final String reason;
  final String? note;
  const CancelOutcome(this.reason, this.note);
}

/// Asks why the user is cancelling before the SOS is ended.
///
/// Two steps on purpose — pick a reason, then confirm. On a live emergency a
/// single stray tap must never be enough to stand a responder down. It also
/// replaces the old standalone "I'm OK" button: that is now one reason among
/// several, so there is a single way to end an SOS rather than two.
class CancelReasonSheet extends StatefulWidget {
  final bool hasResponder;
  const CancelReasonSheet({super.key, required this.hasResponder});

  @override
  State<CancelReasonSheet> createState() => _CancelReasonSheetState();
}

class _CancelReasonSheetState extends State<CancelReasonSheet> {
  String? _selected;
  final _noteCtrl = TextEditingController();

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  bool get _needsNote => _selected == CancelReasons.other;

  /// "Another reason" is only useful with the detail, so require it.
  bool get _canSubmit =>
      _selected != null && (!_needsNote || _noteCtrl.text.trim().isNotEmpty);

  void _submit() {
    Navigator.pop(
      context,
      CancelOutcome(_selected!, _needsNote ? _noteCtrl.text.trim() : null),
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
              const Text(
                'Why are you cancelling?',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                widget.hasResponder
                    ? 'A responder is already on the way. Telling us why frees '
                        'them up for other calls.'
                    : 'This helps us understand what happened and improve '
                        'response times.',
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textMedium, height: 1.35),
              ),
              const SizedBox(height: 16),
              for (final option in CancelReasons.options)
                _ReasonTile(
                  option: option,
                  selected: _selected == option.code,
                  onTap: () => setState(() => _selected = option.code),
                ),
              if (_needsNote) ...[
                const SizedBox(height: 4),
                TextField(
                  controller: _noteCtrl,
                  autofocus: true,
                  maxLength: 140,
                  minLines: 2,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Briefly, what happened?',
                    filled: true,
                    fillColor: AppColors.surfaceAlt,
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        foregroundColor: AppColors.textDark,
                        side: const BorderSide(color: AppColors.divider),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Keep Active'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _canSubmit ? _submit : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.emergency,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppColors.divider,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Cancel SOS'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReasonTile extends StatelessWidget {
  final CancelReasonOption option;
  final bool selected;
  final VoidCallback onTap;

  const _ReasonTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.primarySoft : AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Icon(
                option.icon,
                size: 20,
                color: selected ? AppColors.primary : AppColors.textMedium,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.label,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color:
                            selected ? AppColors.primary : AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      option.hint,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textMedium,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
                color: selected ? AppColors.primary : AppColors.divider,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
