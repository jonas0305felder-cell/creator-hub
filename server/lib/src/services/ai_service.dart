import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';

/// Ein erzeugter Umsetzungsvorschlag (Spezifikation 4.5).
class GeneratedSuggestion {
  GeneratedSuggestion({
    required this.format,
    required this.formatReason,
    required this.hooks,
    required this.outline,
    required this.cta,
    required this.captionDraft,
    required this.hashtags,
    required this.model,
  });

  final String format;
  final String formatReason;
  final List<String> hooks;
  final List<String> outline;
  final String cta;
  final String captionDraft;
  final List<String> hashtags;
  final String model;

  Map<String, dynamic> toJson() => {
    'format': format,
    'format_reason': formatReason,
    'hooks': hooks,
    'outline': outline,
    'cta': cta,
    'caption_draft': captionDraft,
    'hashtags': hashtags,
  };
}

class AiException implements Exception {
  AiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Erzeugt Umsetzungsvorschläge mit einem Sprachmodell.
abstract class AiService {
  /// [part] = null erzeugt den ganzen Vorschlag, sonst nur einen Teil
  /// (`format`, `hooks`, `outline`, `cta`, `caption`, `hashtags`).
  Future<GeneratedSuggestion> generate(Map<String, dynamic> context, {String? part});
}

/// Umsetzung mit der Claude API (Anthropic), per HTTP.
///
/// Annahme: Anthropic als KI-Anbieter (Spezifikation A5 lässt den Anbieter
/// offen). Vor dem Betrieb AV-Vertrag, Datenstandort und Kosten prüfen
/// (Spezifikation Abschnitt 8, Punkt 7).
class ClaudeAiService implements AiService {
  ClaudeAiService(this._config, [http.Client? client]) : _http = client ?? http.Client();

  final Config _config;
  final http.Client _http;

  static const _formats = ['reel', 'carousel', 'image', 'story'];

  static const _schema = {
    'type': 'object',
    'additionalProperties': false,
    'required': ['format', 'format_reason', 'hooks', 'outline', 'cta', 'caption_draft', 'hashtags'],
    'properties': {
      'format': {'type': 'string', 'enum': _formats},
      'format_reason': {'type': 'string'},
      'hooks': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'outline': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'cta': {'type': 'string'},
      'caption_draft': {'type': 'string'},
      'hashtags': {
        'type': 'array',
        'items': {'type': 'string'},
      },
    },
  };

  static const _system = '''
Du hilfst Social-Media-Teams, aus einer Content-Idee einen umsetzbaren Instagram-Beitrag zu machen.
Antworte auf Deutsch, außer die Account-Sprache ist eine andere; dann in der Account-Sprache.
Liefere:
- format: eines von reel, carousel, image, story, passend zu Idee, Nische und den besten eigenen Beiträgen
- format_reason: ein bis zwei Sätze Begründung
- hooks: genau 3 alternative Hooks (erste Sekunde bzw. erste Zeile), je höchstens 120 Zeichen
- outline: Gliederung als Szenen (Reel/Story) oder Slides (Karussell) bzw. Bildidee und Textaufbau (Einzelbild), 3 bis 10 Punkte
- cta: ein klarer Call-to-Action
- caption_draft: Caption-Entwurf in der Tonalität des Accounts, wichtigste Aussage in den ersten 125 Zeichen
- hashtags: höchstens 5 passende Hashtags ohne Leerzeichen, jeweils mit #
Erfinde keine Fakten, Zahlen, Studien oder Zitate. Wo eine Tatsache nötig wäre, markiere sie mit [prüfen].
Nutze verknüpfte Trends nur so, wie sie im Kontext beschrieben sind.''';

  @override
  Future<GeneratedSuggestion> generate(Map<String, dynamic> context, {String? part}) async {
    if (!_config.aiConfigured) throw AiException('KI-Zugang ist auf dem Server nicht eingerichtet.');
    final instruction = part == null
        ? 'Erstelle einen vollständigen Umsetzungsvorschlag.'
        : 'Erstelle einen neuen Vorschlag. Wichtig ist nur der Teil „$part“, er soll sich deutlich vom bisherigen unterscheiden; die übrigen Felder dürfen dem bisherigen Vorschlag entsprechen.';

    final response = await _http
        .post(
          Uri.parse('https://api.anthropic.com/v1/messages'),
          headers: {
            'content-type': 'application/json',
            'x-api-key': _config.aiApiKey,
            'anthropic-version': '2026-10-21',
            // Bei einer Ablehnung durch Sicherheitsfilter springt automatisch
            // ein Ausweichmodell ein.
            'anthropic-beta': 'server-side-fallback-2026-07-01',
          },
          body: jsonEncode({
            'model': _config.aiModel,
            'max_tokens': 16000,
            'fallbacks': 'default',
            'output_config': {
              'effort': 'medium',
              'format': {'type': 'json_schema', 'schema': _schema},
            },
            'system': _system,
            'messages': [
              {
                'role': 'user',
                'content': '$instruction\n\nKontext (JSON):\n${jsonEncode(context)}',
              },
            ],
          }),
        )
        .timeout(const Duration(minutes: 3));

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw AiException('Unerwartete Antwort des KI-Dienstes (${response.statusCode}).');
    }
    if (response.statusCode == 429) throw AiException('KI-Dienst ist ausgelastet. Bitte gleich erneut versuchen.');
    if (response.statusCode >= 400) {
      final message = (json['error'] as Map?)?['message'] ?? 'Fehler ${response.statusCode}';
      throw AiException('KI-Dienst meldet: $message');
    }
    final stop = json['stop_reason'];
    if (stop == 'refusal') throw AiException('Der KI-Dienst hat diese Anfrage abgelehnt.');
    if (stop == 'max_tokens') throw AiException('Der Vorschlag wurde zu lang. Bitte erneut erzeugen.');

    final text = [
      for (final block in (json['content'] as List? ?? const []))
        if ((block as Map)['type'] == 'text') block['text'] as String,
    ].join();
    return parse(text, model: (json['model'] ?? _config.aiModel).toString());
  }

  /// Wandelt die JSON-Antwort in einen Vorschlag um (auch für Tests).
  static GeneratedSuggestion parse(String text, {required String model}) {
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      throw AiException('Der KI-Vorschlag konnte nicht gelesen werden.');
    }
    List<String> list(String key) => [for (final v in (data[key] as List? ?? const [])) v.toString()];
    final format = data['format'].toString();
    return GeneratedSuggestion(
      format: _formats.contains(format) ? format : 'reel',
      formatReason: (data['format_reason'] ?? '').toString(),
      hooks: list('hooks').take(3).toList(),
      outline: list('outline'),
      cta: (data['cta'] ?? '').toString(),
      captionDraft: (data['caption_draft'] ?? '').toString(),
      hashtags: list('hashtags')
          .map((h) => h.startsWith('#') ? h : '#$h')
          .map((h) => h.replaceAll(' ', ''))
          .take(5)
          .toList(),
      model: model,
    );
  }
}
