import 'package:speech_to_text/speech_to_text.dart';

/// Thin wrapper over on-device speech recognition for spoken emergency reports.
///
/// Deliberately keeps no UI state: callers drive it and render the partial
/// transcript, so the mic can be released the instant a screen is disposed.
class SpeechService {
  SpeechService._();
  static final instance = SpeechService._();

  final SpeechToText _speech = SpeechToText();
  bool _available = false;

  bool get isListening => _speech.isListening;

  /// Initialises the recogniser and requests the mic permission.
  /// Returns false when speech recognition is unavailable on this device —
  /// callers must then fall back to typing or manual category selection.
  Future<bool> init({void Function(String status)? onStatus}) async {
    if (_available) return true;
    _available = await _speech.initialize(
      onStatus: (s) => onStatus?.call(s),
      onError: (e) => onStatus?.call('error: ${e.errorMsg}'),
      // A panicked caller may pause mid-sentence; don't treat that as done.
      finalTimeout: const Duration(seconds: 4),
    );
    return _available;
  }

  /// Streams partial transcripts to [onResult]; [onDone] fires with the final
  /// text when recognition stops (by silence, timeout, or [stop]).
  Future<void> listen({
    required void Function(String text, bool isFinal) onResult,
    Duration maxDuration = const Duration(seconds: 45),
  }) async {
    if (!_available) return;
    await _speech.listen(
      onResult: (r) => onResult(r.recognizedWords, r.finalResult),
      listenOptions: SpeechListenOptions(
        listenFor: maxDuration,
        // Emergencies are described in bursts with pauses between them, so
        // allow a long silence before auto-stopping.
        pauseFor: const Duration(seconds: 6),
        localeId: 'en_KE',
        partialResults: true,
        cancelOnError: false,
        listenMode: ListenMode.dictation,
      ),
    );
  }

  Future<void> stop() => _speech.stop();

  Future<void> cancel() => _speech.cancel();
}
