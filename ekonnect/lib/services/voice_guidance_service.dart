import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Spoken turn-by-turn guidance for in-app navigation.
///
/// A responder driving to an emergency cannot safely read a banner, so every
/// manoeuvre is announced. The hard part is *when* to speak: repeating the same
/// instruction on every GPS tick is worse than silence, so this class tracks
/// what has already been said and only speaks on a genuine change.
class VoiceGuidanceService {
  VoiceGuidanceService._();
  static final instance = VoiceGuidanceService._();

  static const _mutedPref = 'nav_voice_muted';

  final FlutterTts _tts = FlutterTts();
  bool _ready = false;
  bool _muted = false;

  /// The last thing spoken, so identical prompts are not repeated.
  String? _lastSpoken;

  /// Which distance band each instruction has already been announced in.
  /// Keyed by instruction text; value is the band index (see [_bandFor]).
  final Map<String, int> _announcedBands = {};

  bool get isMuted => _muted;

  Future<void> init() async {
    if (_ready) return;
    final prefs = await SharedPreferences.getInstance();
    _muted = prefs.getBool(_mutedPref) ?? false;

    await _tts.setLanguage('en-US');
    // Slightly slower than default: navigation prompts are heard once, often
    // over road noise, and a missed word means a missed turn.
    await _tts.setSpeechRate(0.48);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    await _tts.awaitSpeakCompletion(true);
    _ready = true;
  }

  Future<void> setMuted(bool value) async {
    _muted = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_mutedPref, value);
    if (value) await _tts.stop();
  }

  Future<bool> toggleMute() async {
    await setMuted(!_muted);
    return _muted;
  }

  /// Speaks [text] unless muted or identical to the previous utterance.
  /// Pass [force] for prompts that must always be heard (arrival, rerouting).
  Future<void> say(String text, {bool force = false}) async {
    if (_muted || text.trim().isEmpty) return;
    if (!_ready) await init();
    if (!force && text == _lastSpoken) return;
    _lastSpoken = text;
    await _tts.stop(); // cut off a stale prompt rather than queue behind it
    await _tts.speak(text);
  }

  /// Announces a manoeuvre, re-announcing as the driver closes on it.
  ///
  /// Real navigation apps prompt several times per turn — far out, close, and
  /// at the turn — because a single announcement is easy to miss. [_bandFor]
  /// converts the remaining distance into a band so each band speaks once.
  Future<void> announceStep({
    required String instruction,
    required int metresToStep,
  }) async {
    if (_muted) return;

    final band = _bandFor(metresToStep);
    if (_announcedBands[instruction] == band) return;
    _announcedBands[instruction] = band;

    await say(_phraseFor(instruction, metresToStep, band), force: true);
  }

  /// 0 = at the turn, 1 = close, 2 = approaching, 3 = far.
  int _bandFor(int metres) {
    if (metres <= 40) return 0;
    if (metres <= 150) return 1;
    if (metres <= 400) return 2;
    return 3;
  }

  String _phraseFor(String instruction, int metres, int band) {
    switch (band) {
      case 0:
        return 'Now, $instruction';
      case 1:
        return 'In ${_round(metres)} metres, $instruction';
      case 2:
        return 'In ${_round(metres)} metres, $instruction';
      default:
        return metres >= 1000
            ? 'Continue for ${(metres / 1000).toStringAsFixed(1)} kilometres, then $instruction'
            : 'In ${_round(metres)} metres, $instruction';
    }
  }

  /// Spoken distances should be round numbers — "in 340 metres" sounds robotic
  /// and implies precision GPS does not have.
  int _round(int metres) {
    if (metres < 50) return 50;
    if (metres < 100) return (metres / 10).round() * 10;
    return (metres / 50).round() * 50;
  }

  Future<void> announceStart({
    required String distanceText,
    required String durationText,
    String? patientName,
  }) async {
    final who = patientName == null || patientName.isEmpty
        ? 'the patient'
        : patientName;
    await say(
      'Starting navigation to $who. $distanceText, about $durationText.',
      force: true,
    );
  }

  Future<void> announceRerouted() => say('Route updated.', force: true);

  Future<void> announceArrival() =>
      say('You have arrived at the patient location.', force: true);

  /// Clears per-trip memory so a new job starts announcing from scratch.
  Future<void> reset() async {
    _lastSpoken = null;
    _announcedBands.clear();
    await _tts.stop();
  }

  Future<void> stop() => _tts.stop();
}
