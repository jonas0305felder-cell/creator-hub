import 'dart:typed_data';

import 'package:content_hub/models/models.dart';
import 'package:content_hub/services/voice_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

Idea idea({
  String id = 'i1',
  String title = 'Titel',
  String note = '',
  String status = 'idea',
  String? accountId,
  String? format,
  List<String> tags = const [],
  DateTime? planned,
  DateTime? updated,
}) => Idea(
  id: id,
  title: title,
  note: note,
  status: status,
  tags: tags,
  attachments: const [],
  suggestions: const [],
  updatedAt: updated ?? DateTime(2026, 11, 1),
  accountId: accountId,
  format: format,
  plannedFor: planned,
);

void main() {
  group('IdeaFilter', () {
    final ideas = [
      idea(id: 'a', title: 'Herbst-Reel', accountId: 'acc1', format: 'reel', tags: ['herbst'], updated: DateTime(2026, 11, 3)),
      idea(
        id: 'b',
        title: 'Karussell Tipps',
        note: 'fünf Tipps zum Kaffee',
        accountId: 'acc2',
        format: 'carousel',
        planned: DateTime(2026, 11, 20),
      ),
      idea(id: 'c', title: 'Story Umfrage', status: 'ready', planned: DateTime(2026, 11, 12), updated: DateTime(2026, 11, 2)),
    ];

    test('sortiert standardmäßig nach zuletzt bearbeitet', () {
      expect(const IdeaFilter().apply(ideas).map((i) => i.id), ['a', 'c', 'b']);
    });

    test('sortiert nach Termin, Ideen ohne Termin zuletzt', () {
      expect(const IdeaFilter(sortByPlanned: true).apply(ideas).map((i) => i.id), ['c', 'b', 'a']);
    });

    test('filtert nach Account, Format, Status und Tag', () {
      expect(const IdeaFilter(accountId: 'acc2').apply(ideas).map((i) => i.id), ['b']);
      expect(const IdeaFilter(format: 'reel').apply(ideas).map((i) => i.id), ['a']);
      expect(const IdeaFilter(status: 'ready').apply(ideas).map((i) => i.id), ['c']);
      expect(const IdeaFilter(tag: 'herbst').apply(ideas).map((i) => i.id), ['a']);
    });

    test('Volltextsuche findet Wörter in Titel und Notiz, unabhängig von Groß/Klein', () {
      expect(const IdeaFilter(query: 'KAFFEE tipps').apply(ideas).map((i) => i.id), ['b']);
      expect(const IdeaFilter(query: 'gibtsnicht').apply(ideas), isEmpty);
    });

    test('zählt aktive Filter ohne Suche', () {
      expect(const IdeaFilter(query: 'x', format: 'reel', tag: 't').activeCount, 2);
    });
  });

  group('Trend-Frische', () {
    Trend trend(DateTime published) => Trend(
      id: 't',
      title: 'T',
      summary: '',
      reason: '',
      sourceName: 'RSS',
      sourceType: 'rss',
      nicheIds: const [],
      fetchedAt: DateTime(2026, 11, 10),
      publishedAt: published,
    );
    final now = DateTime(2026, 11, 10, 12);

    test('unter 7 Tagen aktuell', () => expect(trend(DateTime(2026, 11, 5)).freshness(now), Freshness.fresh));
    test('7 bis 30 Tage älter', () => expect(trend(DateTime(2026, 10, 20)).freshness(now), Freshness.older));
    test('über 30 Tage veraltet', () => expect(trend(DateTime(2026, 9, 1)).freshness(now), Freshness.stale));
  });

  group('Hilfsfunktionen', () {
    test('percentChange', () {
      expect(percentChange(150, 100), 50);
      expect(percentChange(50, 100), -50);
      expect(percentChange(10, 0), isNull);
      expect(percentChange(null, 10), isNull);
    });

    test('moveToDay behält die Uhrzeit', () {
      expect(moveToDay(DateTime(2026, 11, 3, 18, 30), DateTime(2026, 11, 7)), DateTime(2026, 11, 7, 18, 30));
    });

    test('Account liest Nischen und Hauptnische aus JSON', () {
      final a = Account.fromJson({
        'id': 'a1',
        'username': 'kaffee',
        'account_type': 'creator',
        'connection_status': 'connected',
        'color': '#FF0000',
        'login_type': 'facebook',
        'niches': [
          {'niche_id': 'n1', 'is_primary': false},
          {'niche_id': 'n2', 'is_primary': true},
        ],
      });
      expect(a.nicheIds, ['n1', 'n2']);
      expect(a.primaryNicheId, 'n2');
      expect(a.hasFacebookLogin, isTrue);
      expect(a.canPublish, isTrue);
    });

    test('Suggestion hängt Hashtags an die Caption', () {
      final s = Suggestion.fromJson({
        'id': 's',
        'version': 1,
        'caption_draft': 'Text',
        'hashtags': ['#a', '#b'],
        'hooks': [],
        'outline': [],
      });
      expect(s.captionWithHashtags, 'Text\n\n#a #b');
    });

    test('WAV-Kopf ist 44 Byte lang und nennt die Datenlänge', () {
      final wav = wavFromPcm(Uint8List(100), sampleRate: 16000);
      expect(wav.length, 144);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(ByteData.sublistView(wav).getUint32(40, Endian.little), 100);
    });
  });
}
