import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AiService {
  static const _keyIndexPref = 'groq_key_index';
  static const _model = 'llama-3.3-70b-versatile';
  static const _apiHost = 'https://api.groq.com/openai/v1/chat/completions';

  static const _apiKeys = [
    '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',
    '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',
    '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',
    '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',
    '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',
    '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',
  ];

  static const _systemPrompt = '''
You are an emergency response assistant for eKonnect, an emergency app used in Kenya and East Africa.
Your role is to:
1. Help users identify the right type of emergency (Medical, Fire, Flood, Security)
2. Provide calm, clear first-aid guidance while waiting for responders
3. Help users stay safe during emergencies
4. Answer questions about using the eKonnect app

Emergency numbers in Kenya:
- Police: 999 or 112
- Ambulance: 999 or 0800 723 000
- Fire: 999
- AAR Healthcare: +254 20 286 6000

Keep responses short, clear and calm. Always remind users to press the SOS button if they have not already done so.
If someone is in immediate danger, prioritize telling them to call 999 immediately.
''';

  static Future<int> _currentKeyIndex() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyIndexPref) ?? 0;
  }

  static Future<void> _saveKeyIndex(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyIndexPref, index);
  }

  static Future<String> chat(List<Map<String, String>> history) async {
    final content = await _complete(
      systemPrompt: _systemPrompt,
      messages: history,
      temperature: 0.7,
      maxTokens: 1000,
    );
    return content ??
        'All AI services are currently busy. Please try again in a moment, or call 999 for emergencies.';
  }

  /// Turns a spoken emergency report into structured dispatch data.
  ///
  /// Returns null if every key fails — callers must fall back to letting the
  /// user pick a category by hand rather than blocking the SOS. An emergency
  /// call must never depend on an AI service being reachable.
  static Future<EmergencyAnalysis?> analyseReport(String transcript) async {
    if (transcript.trim().isEmpty) return null;

    final raw = await _complete(
      systemPrompt: _triagePrompt,
      messages: [
        {'role': 'user', 'content': transcript}
      ],
      // Near-deterministic: this is a classification, not a conversation.
      temperature: 0.1,
      maxTokens: 500,
      jsonMode: true,
    );
    if (raw == null) return null;
    return EmergencyAnalysis.tryParse(raw, transcript);
  }

  /// Orders candidate care points by clinical suitability for [need].
  ///
  /// Returns `[{id, reason}]` best-first. An empty list means "no opinion" —
  /// callers must then fall back to nearest-first rather than showing nothing.
  static Future<List<Map<String, dynamic>>> rankCarePoints({
    required String need,
    required String incidentType,
    required List<Map<String, dynamic>> candidates,
  }) async {
    if (candidates.isEmpty) return const [];

    final raw = await _complete(
      systemPrompt: _referralPrompt,
      messages: [
        {
          'role': 'user',
          'content': jsonEncode({
            'emergencyType': incidentType,
            'need': need,
            'candidates': candidates,
          }),
        }
      ],
      temperature: 0.1,
      maxTokens: 700,
      jsonMode: true,
    );
    if (raw == null) return const [];

    try {
      final start = raw.indexOf('{');
      final end = raw.lastIndexOf('}');
      if (start == -1 || end <= start) return const [];
      final map =
          jsonDecode(raw.substring(start, end + 1)) as Map<String, dynamic>;
      final ranked = map['ranked'] as List? ?? const [];
      return ranked
          .map((e) => {
                'id': (e as Map)['id']?.toString() ?? '',
                'reason': e['reason']?.toString() ?? '',
              })
          .where((e) => (e['id'] as String).isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static const _referralPrompt = '''
You help an emergency responder choose where to take or refer a patient in Kenya.

You receive the emergency type, what the responder needs, and a list of nearby
care points with their declared services, description and distance.

Respond with ONLY JSON:
{"ranked":[{"id":"<candidate id>","reason":"<max 12 words, why this one>"}]}

Rules:
- Order best first. Include only candidates that could plausibly help.
- Clinical capability outweighs distance, but do not send someone far away for
  something the nearest place can clearly handle.
- Judge on the declared services and description. Never assume a capability
  that is not stated.
- If a candidate has no service information, rank it lower and say so.
- Keep reasons concrete: "Has ICU and trauma surgery", not "Looks suitable".
''';

  static const _triagePrompt = '''
You are the triage engine for eKonnect, an emergency dispatch app in Kenya.
You will receive a transcript of someone describing an emergency out loud. The
transcript may be messy, panicked, incomplete, or contain speech-recognition
errors. Infer intent charitably.

Respond with ONLY a JSON object, no markdown, matching exactly:
{
  "type": "medical" | "fire" | "flood" | "security",
  "severity": "critical" | "urgent" | "moderate",
  "summary": "one sentence a dispatcher can read at a glance",
  "keyFacts": ["short factual bullets: who, what, where, how many"],
  "advice": "one or two short actions the caller should take right now",
  "confidence": 0.0
}

Rules:
- "type" MUST be one of the four values. If genuinely unclear, choose the one
  that would send the most useful responder, and lower "confidence".
- "critical" means life is in immediate danger (not breathing, heavy bleeding,
  trapped, active violence, fire with people inside).
- "confidence" is 0.0-1.0 reflecting how clear the transcript was.
- Never invent details that are not in the transcript. If location or casualty
  count is not stated, leave it out rather than guessing.
- "advice" must be safe for an untrained bystander.
''';

  /// Shared Groq call with key rotation. Returns the message content, or null
  /// if every key was exhausted.
  static Future<String?> _complete({
    required String systemPrompt,
    required List<Map<String, String>> messages,
    required double temperature,
    required int maxTokens,
    bool jsonMode = false,
  }) async {
    final startIndex = await _currentKeyIndex();

    for (int i = 0; i < _apiKeys.length; i++) {
      final index = (startIndex + i) % _apiKeys.length;
      final key = _apiKeys[index];

      try {
        final response = await http
            .post(
              Uri.parse(_apiHost),
              headers: {
                'Authorization': 'Bearer $key',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'model': _model,
                'max_tokens': maxTokens,
                'temperature': temperature,
                if (jsonMode)
                  'response_format': {'type': 'json_object'},
                'messages': [
                  {'role': 'system', 'content': systemPrompt},
                  ...messages,
                ],
              }),
            )
            .timeout(const Duration(seconds: 20));

        if (response.statusCode == 200) {
          await _saveKeyIndex(index); // next call starts on a known-good key
          final data = jsonDecode(response.body);
          return data['choices'][0]['message']['content'] as String;
        }

        // Rate limited or unauthorised — rotate to the next key.
        if (response.statusCode == 429 || response.statusCode == 401) continue;
        return null;
      } catch (_) {
        continue; // network error or timeout — try the next key
      }
    }
    return null;
  }
}

/// Structured triage produced from a spoken report.
class EmergencyAnalysis {
  final String type; // an IncidentType code
  final String severity; // critical | urgent | moderate
  final String summary;
  final List<String> keyFacts;
  final String advice;
  final double confidence;
  final String transcript;

  const EmergencyAnalysis({
    required this.type,
    required this.severity,
    required this.summary,
    required this.keyFacts,
    required this.advice,
    required this.confidence,
    required this.transcript,
  });

  /// Below this the UI asks the user to confirm the category rather than
  /// silently trusting the model with an emergency dispatch decision.
  bool get isConfident => confidence >= 0.6;

  bool get isCritical => severity == 'critical';

  /// Parses the model's JSON defensively — a malformed reply must degrade to
  /// null so the caller can fall back to manual selection.
  static EmergencyAnalysis? tryParse(String raw, String transcript) {
    try {
      // Models occasionally wrap JSON in prose or code fences despite the
      // instruction, so slice to the outermost object before decoding.
      final start = raw.indexOf('{');
      final end = raw.lastIndexOf('}');
      if (start == -1 || end <= start) return null;

      final map = jsonDecode(raw.substring(start, end + 1))
          as Map<String, dynamic>;

      final type = (map['type'] as String?)?.toLowerCase().trim();
      if (type == null || !_validTypes.contains(type)) return null;

      final severity = (map['severity'] as String?)?.toLowerCase().trim();

      return EmergencyAnalysis(
        type: type,
        severity: _validSeverities.contains(severity) ? severity! : 'urgent',
        summary: (map['summary'] as String?)?.trim() ?? '',
        keyFacts: (map['keyFacts'] as List?)
                ?.map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
                .toList() ??
            const [],
        advice: (map['advice'] as String?)?.trim() ?? '',
        confidence:
            (map['confidence'] as num?)?.toDouble().clamp(0.0, 1.0) ?? 0.5,
        transcript: transcript,
      );
    } catch (_) {
      return null;
    }
  }

  static const _validTypes = {'medical', 'fire', 'flood', 'security'};
  static const _validSeverities = {'critical', 'urgent', 'moderate'};

  /// Packed into the incident's `notes` so the responder sees the caller's own
  /// words alongside the triage, not just the model's interpretation.
  String toIncidentNotes() {
    final buffer = StringBuffer()
      ..writeln('AI triage — ${severity.toUpperCase()}')
      ..writeln(summary);
    if (keyFacts.isNotEmpty) {
      buffer.writeln();
      for (final fact in keyFacts) {
        buffer.writeln('• $fact');
      }
    }
    buffer
      ..writeln()
      ..writeln('Caller said: "$transcript"');
    return buffer.toString().trim();
  }
}
