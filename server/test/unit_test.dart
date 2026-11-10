import 'dart:convert';

import 'package:content_hub_server/server.dart';
import 'package:test/test.dart';

void main() {
  group('Security', () {
    test('Passwort-Hash prüft richtig und falsch', () async {
      final hash = await Security.hashPassword('geheimes-passwort');
      expect(hash, isNot(contains('geheimes-passwort')));
      expect(await Security.verifyPassword('geheimes-passwort', hash), isTrue);
      expect(await Security.verifyPassword('anderes-passwort', hash), isFalse);
      expect(await Security.verifyPassword('x', 'kaputt'), isFalse);
    });

    test('Token-Verschlüsselung ist umkehrbar und nicht lesbar', () async {
      final security = Security(base64Encode(List.generate(32, (i) => i)));
      final encrypted = await security.encrypt('IGQVJ-token');
      expect(encrypted, isNot(contains('IGQVJ')));
      expect(await security.decrypt(encrypted), 'IGQVJ-token');
      // Jede Verschlüsselung nutzt eine neue Nonce.
      expect(await security.encrypt('IGQVJ-token'), isNot(encrypted));
    });

    test('ohne Schlüssel wird nichts gespeichert', () {
      expect(() => Security('').encrypt('x'), throwsStateError);
      expect(() => Security(base64Encode([1, 2, 3])), throwsArgumentError);
    });
  });

  group('RSS', () {
    test('liest RSS 2.0', () {
      final items = RssService.parse('''<?xml version="1.0"?><rss><channel>
        <item><title>BMW zeigt neue GS</title><link>https://example.com/gs</link><guid>gs-1</guid>
          <description>&lt;p&gt;Die neue &lt;b&gt;GS&lt;/b&gt; ist da.&lt;/p&gt;</description>
          <pubDate>Tue, 10 Nov 2026 06:00:00 +0100</pubDate></item>
        <item><title></title></item></channel></rss>''');
      expect(items, hasLength(1));
      expect(items.first.id, 'gs-1');
      expect(items.first.summary, 'Die neue GS ist da.');
      expect(items.first.publishedAt, DateTime.utc(2026, 11, 10, 5));
    });

    test('liest Atom', () {
      final items = RssService.parse('''<feed xmlns="http://www.w3.org/2005/Atom">
        <entry><title>Foto-Trend</title><id>urn:1</id><link rel="alternate" href="https://example.com/1"/>
          <updated>2026-11-09T12:00:00Z</updated><summary>Kurz</summary></entry></feed>''');
      expect(items.single.link, 'https://example.com/1');
      expect(items.single.publishedAt, DateTime.utc(2026, 11, 9, 12));
    });

    test('kaputter Feed wirft einen Fehler statt leerer Liste', () {
      expect(() => RssService.parse('<html><body>kein feed'), throwsException);
    });
  });

  group('KI-Antwort', () {
    test('wird auf 3 Hooks und 5 Hashtags begrenzt', () {
      final s = ClaudeAiService.parse(
        jsonEncode({
          'format': 'carousel',
          'format_reason': 'x',
          'hooks': ['a', 'b', 'c', 'd'],
          'outline': ['1', '2'],
          'cta': 'c',
          'caption_draft': 'cap',
          'hashtags': ['eins', '#zwei', 'drei vier', '4', '5', '6'],
        }),
        model: 'm',
      );
      expect(s.hooks, hasLength(3));
      expect(s.hashtags, ['#eins', '#zwei', '#dreivier', '#4', '#5']);
      expect(s.format, 'carousel');
    });

    test('unlesbare Antwort wird als Fehler gemeldet', () {
      expect(() => ClaudeAiService.parse('kein json', model: 'm'), throwsA(isA<AiException>()));
    });
  });

  group('Medien-Links', () {
    test('Signatur gilt nur für Schlüssel und Ablaufzeit', () async {
      final storage = MediaStorage(dir: '/tmp/unbenutzt', baseUrl: 'https://s.test', secret: 'k');
      final url = Uri.parse(await storage.signedUrl('abc.jpg', DateTime.now().add(const Duration(minutes: 5))));
      final q = url.queryParameters;
      expect(await storage.verify('abc.jpg', q['exp'], q['sig']), isTrue);
      expect(await storage.verify('xyz.jpg', q['exp'], q['sig']), isFalse);
      final old = Uri.parse(await storage.signedUrl('abc.jpg', DateTime.now().subtract(const Duration(minutes: 5))));
      expect(await storage.verify('abc.jpg', old.queryParameters['exp'], old.queryParameters['sig']), isFalse);
      expect(storage.file('../etc/passwd'), isNull);
    });
  });
}
