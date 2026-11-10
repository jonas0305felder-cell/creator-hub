// Integrationstests des Servers gegen eine echte PostgreSQL-Datenbank.
//
// Start:  TEST_DATABASE_URL=postgresql://user:pass@localhost:5432/contenthub_test?sslmode=disable dart test
// Die Testdatenbank wird bei jedem Lauf geleert. Instagram und KI sind
// durch Attrappen ersetzt (siehe fake_instagram.dart).
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:content_hub_server/server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'fake_instagram.dart';

void main() {
  final url = Platform.environment['TEST_DATABASE_URL'];
  if (url == null) {
    test('API-Tests', () {}, skip: 'TEST_DATABASE_URL ist nicht gesetzt.');
    return;
  }

  late Db db;
  late Handler handler;
  late FakeInstagramApi ig;
  late FakeAi ai;
  late Services services;
  late SyncService sync;
  late PublishService publisher;
  late Directory storageDir;

  Future<({int status, dynamic body})> call(
    String method,
    String path, {
    String? token,
    Object? json,
    List<int>? bytes,
    String? contentType,
  }) async {
    final response = await handler(
      Request(
        method,
        Uri.parse('http://localhost$path'),
        headers: {
          if (token != null) 'authorization': 'Bearer $token',
          if (json != null) 'content-type': 'application/json',
          if (contentType != null) 'content-type': contentType,
        },
        body: json != null ? jsonEncode(json) : bytes,
      ),
    );
    final text = await response.readAsString();
    dynamic body;
    try {
      body = jsonDecode(text);
    } catch (_) {
      body = text;
    }
    return (status: response.statusCode, body: body);
  }

  Future<String> register(String email, {String? invite}) async {
    final r = await call('POST', '/api/auth/register', json: {
      'email': email,
      'name': email.split('@').first,
      'password': 'ein-langes-passwort',
      if (invite != null) 'invite_code': invite,
    });
    expect(r.status, 201, reason: '${r.body}');
    return r.body['token'] as String;
  }

  /// Durchläuft den OAuth-Ablauf mit der Instagram-Attrappe.
  Future<String> connect(String token, {String loginType = 'instagram', String code = 'abc'}) async {
    final start = await call('POST', '/api/oauth/start', token: token, json: {'login_type': loginType});
    expect(start.status, 200, reason: '${start.body}');
    final state = Uri.parse(start.body['url'] as String).queryParameters['state'];
    final callback = await handler(Request('GET', Uri.parse('http://localhost/api/oauth/callback?state=$state&code=$code')));
    expect(callback.statusCode, 302);
    final location = Uri.parse(callback.headers['location']!);
    // Der Rücksprung trägt nur einen Einmal-Code, nie das Token.
    expect(location.toString(), isNot(contains('token-')));
    final result = await call('POST', '/api/oauth/result', token: token, json: {'code': location.queryParameters['result']});
    expect(result.status, 200, reason: '${result.body}');
    final id = result.body['account_id'] as String;
    await sync.syncAccount(id);
    return id;
  }

  setUpAll(() async {
    db = Db.connect(url);
    await db.exec('DROP SCHEMA public CASCADE');
    await db.exec('CREATE SCHEMA public');
    await db.migrate();
    storageDir = await Directory.systemTemp.createTemp('contenthub_test');
  });

  tearDownAll(() async {
    await db.close();
    await storageDir.delete(recursive: true);
  });

  setUp(() async {
    final tables = await db.query(
      "SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename <> 'schema_version'",
    );
    await db.exec('TRUNCATE ${tables.map((t) => t['tablename']).join(', ')} CASCADE');
    ig = FakeInstagramApi();
    ai = FakeAi();
    final config = Config.fromEnvironment({
      'INSTAGRAM_APP_ID': 'app',
      'INSTAGRAM_APP_SECRET': 'secret',
      'FACEBOOK_APP_ID': 'fbapp',
      'FACEBOOK_APP_SECRET': 'fbsecret',
      'AI_API_KEY': 'key',
      'TOKEN_ENCRYPTION_KEY': base64Encode(List.filled(32, 7)),
      'PUBLIC_BASE_URL': 'https://server.test',
      'WEB_DIR': '',
    });
    services = Services(
      config: config,
      db: db,
      security: Security(config.tokenEncryptionKey),
      instagram: ig,
      ai: ai,
      rss: RssService(),
      storage: MediaStorage(dir: storageDir.path, baseUrl: config.publicBaseUrl, secret: 'test'),
    );
    sync = SyncService(services);
    publisher = PublishService(services)..statusInterval = Duration.zero;
    handler = buildHandler(services, sync, publisher);
  });

  group('Konto und Team', () {
    test('Registrieren, Anmelden, Profil', () async {
      final token = await register('jonas@example.com');
      final me = await call('GET', '/api/me', token: token);
      expect(me.body['role'], 'owner');
      expect(me.body['user']['email'], 'jonas@example.com');

      final login = await call('POST', '/api/auth/login', json: {'email': 'jonas@example.com', 'password': 'ein-langes-passwort'});
      expect(login.status, 200);
      final wrong = await call('POST', '/api/auth/login', json: {'email': 'jonas@example.com', 'password': 'falsch-falsch'});
      expect(wrong.status, 401);
      final duplicate = await call('POST', '/api/auth/register', json: {'email': 'jonas@example.com', 'name': 'x', 'password': 'ein-langes-passwort'});
      expect(duplicate.status, 409);
    });

    test('ohne Token kein Zugriff, abgemeldetes Token ist ungültig', () async {
      expect((await call('GET', '/api/ideas')).status, 401);
      final token = await register('a@example.com');
      await call('POST', '/api/auth/logout', token: token);
      expect((await call('GET', '/api/me', token: token)).status, 401);
    });

    test('Einladung macht ein Mitglied im selben Workspace; Mitglied darf nicht verbinden', () async {
      final owner = await register('owner@example.com');
      final invite = await call('POST', '/api/team/invites', token: owner);
      expect(invite.status, 201);
      final member = await register('member@example.com', invite: invite.body['code'] as String);
      final me = await call('GET', '/api/me', token: member);
      expect(me.body['role'], 'member');
      final team = await call('GET', '/api/team', token: owner);
      expect((team.body['members'] as List).length, 2);
      // Einladung ist nur einmal gültig.
      final again = await call('POST', '/api/auth/register', json: {
        'email': 'x@example.com', 'name': 'x', 'password': 'ein-langes-passwort', 'invite_code': invite.body['code'],
      });
      expect(again.status, 400);
      // MVP: nur Owner verbindet und trennt.
      expect((await call('POST', '/api/oauth/start', token: member, json: {})).status, 403);
      expect((await call('POST', '/api/team/invites', token: member)).status, 403);
    });

    test('Workspaces sind voneinander getrennt', () async {
      final a = await register('a@example.com');
      final b = await register('b@example.com');
      final idea = await call('POST', '/api/ideas', token: a, json: {'title': 'Geheime Idee'});
      expect((await call('GET', '/api/ideas', token: b)).body, isEmpty);
      expect((await call('PATCH', '/api/ideas/${idea.body['id']}', token: b, json: {'title': 'x'})).status, 404);
      expect((await call('DELETE', '/api/ideas/${idea.body['id']}', token: b)).status, 404);
    });

    test('Konto löschen entfernt den Workspace des letzten Mitglieds', () async {
      final token = await register('a@example.com');
      await call('POST', '/api/ideas', token: token, json: {'title': 'Idee'});
      expect((await call('DELETE', '/api/me', token: token)).status, 200);
      expect(await db.query('SELECT 1 FROM ideas'), isEmpty);
      expect(await db.query('SELECT 1 FROM workspaces'), isEmpty);
    });

    test('Datenexport enthält Ideen, aber keine Tokens', () async {
      final token = await register('a@example.com');
      await connect(token);
      await call('POST', '/api/ideas', token: token, json: {'title': 'Export-Idee'});
      final response = await handler(Request('GET', Uri.parse('http://localhost/api/export'), headers: {'authorization': 'Bearer $token'}));
      final text = await response.readAsString();
      expect(text, contains('Export-Idee'));
      expect(text, isNot(contains('token-abc')));
      expect(text, isNot(contains('encrypted_access_token')));
    });
  });

  group('Accounts verbinden', () {
    test('OAuth-Ablauf legt Account an, Token liegt verschlüsselt vor', () async {
      final token = await register('a@example.com');
      final id = await connect(token);
      final accounts = await call('GET', '/api/accounts', token: token);
      expect(accounts.body, hasLength(1));
      expect(accounts.body[0]['username'], 'testaccount');
      expect(accounts.body[0]['connection_status'], 'connected');
      expect(accounts.body[0]['followers_count'], 250);
      expect(accounts.body[0].toString(), isNot(contains('token-abc')));
      final cred = await db.one('SELECT encrypted_access_token FROM instagram_credentials WHERE account_id = @a', {'a': id});
      expect(cred!['encrypted_access_token'], isNot(contains('token-abc')));
      expect(await services.security.decrypt(cred['encrypted_access_token'] as String), 'token-abc');
    });

    test('state ist nur einmal gültig', () async {
      final token = await register('a@example.com');
      final start = await call('POST', '/api/oauth/start', token: token, json: {});
      final state = Uri.parse(start.body['url'] as String).queryParameters['state'];
      final first = await handler(Request('GET', Uri.parse('http://localhost/api/oauth/callback?state=$state&code=abc')));
      expect(first.statusCode, 302);
      final second = await handler(Request('GET', Uri.parse('http://localhost/api/oauth/callback?state=$state&code=abc')));
      expect(second.statusCode, 403);
    });

    test('abgelehnte Berechtigung wird erklärt', () async {
      final token = await register('a@example.com');
      final start = await call('POST', '/api/oauth/start', token: token, json: {});
      final state = Uri.parse(start.body['url'] as String).queryParameters['state'];
      final cb = await handler(Request('GET', Uri.parse('http://localhost/api/oauth/callback?state=$state&error=access_denied')));
      final code = Uri.parse(cb.headers['location']!).queryParameters['result'];
      final result = await call('POST', '/api/oauth/result', token: token, json: {'code': code});
      expect(result.status, 409);
      expect(result.body['error'], 'permission_denied');
      expect((await call('GET', '/api/accounts', token: token)).body, isEmpty);
    });

    test('Account in anderem Workspace wird nicht still doppelt verbunden', () async {
      final a = await register('a@example.com');
      final b = await register('b@example.com');
      await connect(a);
      final start = await call('POST', '/api/oauth/start', token: b, json: {});
      final state = Uri.parse(start.body['url'] as String).queryParameters['state'];
      final cb = await handler(Request('GET', Uri.parse('http://localhost/api/oauth/callback?state=$state&code=zzz')));
      final result = await call('POST', '/api/oauth/result', token: b, json: {'code': Uri.parse(cb.headers['location']!).queryParameters['result']});
      expect(result.body['error'], 'account_in_other_workspace');
    });

    test('höchstens 10 Accounts; manuelle Accounts ohne Statistik', () async {
      final token = await register('a@example.com');
      for (var i = 0; i < 10; i++) {
        final r = await call('POST', '/api/accounts/manual', token: token, json: {'username': 'manuell$i'});
        expect(r.status, 201);
      }
      expect((await call('POST', '/api/accounts/manual', token: token, json: {'username': 'zuviel'})).status, 409);
      final accounts = await call('GET', '/api/accounts', token: token);
      final stats = await call('GET', '/api/accounts/${accounts.body[0]['id']}/stats', token: token);
      expect(stats.body['missing'][0]['code'], 'manual');
      expect(stats.body['totals']['reach'], isNull);
    });

    test('Trennen löscht Token, Metriken und Medien, Ideen bleiben ohne Account', () async {
      final token = await register('a@example.com');
      final id = await connect(token);
      await call('POST', '/api/ideas', token: token, json: {'title': 'Bleibt', 'account_id': id});
      expect((await call('DELETE', '/api/accounts/$id', token: token)).status, 200);
      expect(await db.query('SELECT 1 FROM instagram_credentials'), isEmpty);
      expect(await db.query('SELECT 1 FROM media'), isEmpty);
      expect(await db.query('SELECT 1 FROM account_daily_metrics'), isEmpty);
      final ideas = await call('GET', '/api/ideas', token: token);
      expect(ideas.body, hasLength(1));
      expect(ideas.body[0]['account_id'], isNull);
    });

    test('abgelaufenes Token setzt „Neu verbinden nötig“ und benachrichtigt', () async {
      final token = await register('a@example.com');
      final id = await connect(token);
      ig.failAuth = true;
      await sync.syncAccount(id);
      final accounts = await call('GET', '/api/accounts', token: token);
      expect(accounts.body[0]['connection_status'], 'disconnected');
      final notes = await call('GET', '/api/notifications', token: token);
      expect((notes.body as List).any((n) => n['kind'] == 'reconnect_required'), isTrue);
    });
  });

  group('Statistiken', () {
    test('Summen, Verlauf, fehlende Werte bleiben fehlend', () async {
      final token = await register('a@example.com');
      final id = await connect(token);
      final stats = await call('GET', '/api/accounts/$id/stats?days=7', token: token);
      expect(stats.status, 200);
      expect(stats.body['totals']['reach'], 7 * 50);
      expect(stats.body['totals']['views'], 7 * 80);
      // Instagram lieferte dafür nichts: null, nicht 0.
      expect(stats.body['totals']['follows'], isNull);
      expect(stats.body['previous']['reach'], 7 * 50);
      expect((stats.body['series']['reach'] as List).length, 7);
      expect(stats.body['fetched_at'], isNotNull);
      expect(stats.body['follower_series'], hasLength(1));
      final stored = await db.one("SELECT value FROM account_daily_metrics WHERE metric = 'profile_links_taps' LIMIT 1");
      expect(stored!['value'], isNull);
    });

    test('Beitragsliste und Detail mit Median-Vergleich', () async {
      final token = await register('a@example.com');
      final id = await connect(token);
      final media = await call('GET', '/api/accounts/$id/media?days=28', token: token);
      expect(media.body, hasLength(2));
      final reel = (media.body as List).firstWhere((m) => m['media_product_type'] == 'reels');
      final detail = await call('GET', '/api/media/${reel['id']}', token: token);
      expect(detail.body['metrics']['reach'], 300);
      expect(detail.body['metrics']['ig_reels_avg_watch_time'], 4200);
      expect(detail.body['medians']['reach'], 200);
    });

    test('Übersicht vergleicht Accounts und nennt den auffälligsten Beitrag', () async {
      final token = await register('a@example.com');
      await connect(token);
      final overview = await call('GET', '/api/stats/overview', token: token);
      expect(overview.body['accounts'], hasLength(1));
      expect(overview.body['standout']['caption'], 'Ein Reel');
    });

    test('Story-Werte werden gesichert', () async {
      final token = await register('a@example.com');
      final id = await connect(token);
      final stories = await call('GET', '/api/accounts/$id/stories', token: token);
      expect(stories.body, hasLength(1));
      expect(stories.body[0]['metrics']['reach'], 33);
      expect(stories.body[0]['last_captured_at'], isNotNull);
      expect(stories.body[0]['is_live'], isTrue);
    });
  });

  group('Kommentare', () {
    test('Eingang, Antworten, Ausblenden', () async {
      final token = await register('a@example.com');
      final id = await connect(token);
      var inbox = await call('GET', '/api/comments?account_id=$id&filter=unanswered', token: token);
      expect(inbox.body, hasLength(1));
      final commentId = inbox.body[0]['id'];
      final notes = await call('GET', '/api/notifications', token: token);
      expect((notes.body as List).any((n) => n['kind'] == 'new_comments'), isTrue);

      final reply = await call('POST', '/api/comments/$commentId/reply', token: token, json: {'message': 'Danke!'});
      expect(reply.status, 200);
      expect(ig.replies, ['c1:Danke!']);
      inbox = await call('GET', '/api/comments?filter=unanswered', token: token);
      expect(inbox.body, isEmpty);
      inbox = await call('GET', '/api/comments', token: token);
      expect(inbox.body[0]['replies'], hasLength(1));

      await call('POST', '/api/comments/$commentId/hide', token: token, json: {'hide': true});
      expect(ig.hidden['c1'], isTrue);
    });

    test('erneuter Sync meldet bekannte Kommentare nicht noch einmal', () async {
      final token = await register('a@example.com');
      final id = await connect(token);
      await sync.syncAccount(id);
      final notes = await call('GET', '/api/notifications', token: token);
      expect((notes.body as List).where((n) => n['kind'] == 'new_comments'), hasLength(1));
    });
  });

  group('Wettbewerber und Hashtags', () {
    test('nur mit Facebook Login', () async {
      final token = await register('a@example.com');
      final id = await connect(token);
      final c = await call('POST', '/api/accounts/$id/competitors', token: token, json: {'username': 'anderer'});
      expect(c.status, 409);
      expect(c.body['error'], 'facebook_login_required');
      final h = await call('POST', '/api/accounts/$id/hashtags', token: token, json: {'hashtag': 'motorrad'});
      expect(h.body['error'], 'facebook_login_required');
    });

    test('Wettbewerber: Snapshot, Grenze 10, unbekannter Account', () async {
      final token = await register('a@example.com');
      final id = await connect(token, loginType: 'facebook');
      for (var i = 0; i < 10; i++) {
        expect((await call('POST', '/api/accounts/$id/competitors', token: token, json: {'username': 'wett$i'})).status, 201);
      }
      expect((await call('POST', '/api/accounts/$id/competitors', token: token, json: {'username': 'wett11'})).body['error'], 'competitor_limit');
      final list = await call('GET', '/api/accounts/$id/competitors', token: token);
      expect(list.body['items'], hasLength(10));
      expect(list.body['items'][0]['snapshots'][0]['followers_count'], 5000);
      expect(list.body['items'][0]['snapshots'][0]['avg_likes'], 150);
    });

    test('unbekannter Wettbewerber wird abgelehnt', () async {
      final token = await register('a@example.com');
      final id = await connect(token, loginType: 'facebook');
      final r = await call('POST', '/api/accounts/$id/competitors', token: token, json: {'username': 'gibtsnicht'});
      expect(r.status, 404);
    });

    test('Hashtag-Kontingent 30 je 7 Tage, Top-Beiträge werden Trends', () async {
      final token = await register('a@example.com');
      final id = await connect(token, loginType: 'facebook');
      final first = await call('POST', '/api/accounts/$id/hashtags', token: token, json: {'hashtag': '#Motorrad'});
      expect(first.status, 201);
      var info = await call('GET', '/api/accounts/$id/hashtags', token: token);
      expect(info.body['remaining'], 29);
      expect(info.body['items'][0]['hashtag'], 'motorrad');

      final trends = await call('GET', '/api/trends', token: token);
      // Nur der Top-Beitrag erscheint automatisch als Trendsignal.
      expect(trends.body['trends'], hasLength(1));
      expect(trends.body['trends'][0]['source_name'], 'Instagram Hashtag-Suche');
      final posts = await call('GET', '/api/hashtags/${first.body['id']}/posts', token: token);
      expect(posts.body, hasLength(2));
      final recent = (posts.body as List).firstWhere((p) => p['listed'] == false);
      await call('POST', '/api/trends/${recent['id']}/adopt', token: token);
      expect((await call('GET', '/api/trends', token: token)).body['trends'], hasLength(2));

      // Entfernen gibt das Kontingent nicht zurück.
      await call('DELETE', '/api/hashtags/${first.body['id']}', token: token);
      info = await call('GET', '/api/accounts/$id/hashtags', token: token);
      expect(info.body['remaining'], 29);
      expect(info.body['items'], isEmpty);

      for (var i = 0; i < 29; i++) {
        expect((await call('POST', '/api/accounts/$id/hashtags', token: token, json: {'hashtag': 'tag$i'})).status, 201);
      }
      final over = await call('POST', '/api/accounts/$id/hashtags', token: token, json: {'hashtag': 'zuviel'});
      expect(over.status, 429);
      expect(over.body['error'], 'hashtag_quota');
      // Wieder aktivieren eines schon gezählten Hashtags kostet nichts.
      expect((await call('POST', '/api/accounts/$id/hashtags', token: token, json: {'hashtag': 'motorrad'})).status, 201);
    });
  });

  group('Trends und Ideen', () {
    test('manueller Trend mit Nische, daraus eine Idee', () async {
      final token = await register('a@example.com');
      final niche = await call('POST', '/api/niches', token: token, json: {'name': 'Motorrad', 'keywords': ['bmw', 'tour']});
      expect(niche.status, 201);
      final trend = await call('POST', '/api/trends', token: token, json: {
        'title': 'Wintertouren', 'reason': 'Mehrere große Accounts posten dazu', 'source_url': 'https://example.com/a', 'niche_ids': [niche.body['id']],
      });
      expect(trend.status, 201);
      final trends = await call('GET', '/api/trends', token: token);
      expect(trends.body['trends'][0]['niche_ids'], [niche.body['id']]);
      expect(trends.body['trends'][0]['source_name'], 'Eigene Beobachtung');
      expect(trends.body['trends'][0]['fetched_at'], isNotNull);

      final idea = await call('POST', '/api/ideas', token: token, json: {
        'title': 'Wintertour-Reel', 'niche_id': niche.body['id'], 'source_trend_id': trend.body['id'],
      });
      expect(idea.status, 201);
      expect(idea.body['status'], 'idea');
      expect(idea.body['source_trend_title'], 'Wintertouren');
    });

    test('Trend ohne Begründung oder mit kaputtem Link wird abgelehnt', () async {
      final token = await register('a@example.com');
      expect((await call('POST', '/api/trends', token: token, json: {'title': 'x'})).status, 400);
      expect((await call('POST', '/api/trends', token: token, json: {'title': 'x', 'reason': 'y', 'source_url': 'javascript:alert(1)'})).status, 400);
    });

    test('Idee bearbeiten, Status, Anhänge', () async {
      final token = await register('a@example.com');
      final idea = await call('POST', '/api/ideas', token: token, json: {'note': 'Nur eine Notiz ohne Titel'});
      expect(idea.body['title'], 'Nur eine Notiz ohne Titel');
      final id = idea.body['id'];
      final updated = await call('PATCH', '/api/ideas/$id', token: token, json: {
        'status': 'in_progress', 'format': 'carousel', 'tags': ['winter'], 'planned_for': '2026-12-01T10:00:00Z',
      });
      expect(updated.body['status'], 'in_progress');
      expect(updated.body['tags'], ['winter']);
      expect(updated.body['title'], 'Nur eine Notiz ohne Titel');
      expect((await call('PATCH', '/api/ideas/$id', token: token, json: {'status': 'quatsch'})).status, 400);

      final link = await call('POST', '/api/ideas/$id/attachments', token: token, json: {'type': 'link', 'url': 'https://example.com/x'});
      expect(link.body['attachments'], hasLength(1));
      final photo = await call('POST', '/api/ideas/$id/attachments', token: token, bytes: [1, 2, 3], contentType: 'image/jpeg');
      expect(photo.status, 201);
      final att = (photo.body['attachments'] as List).firstWhere((a) => a['type'] == 'image');
      // Datei ist nur über den signierten Link abrufbar.
      final uri = Uri.parse(att['url'] as String);
      final ok = await handler(Request('GET', Uri.parse('http://localhost${uri.path}?${uri.query}')));
      expect(ok.statusCode, 200);
      final tampered = await handler(Request('GET', Uri.parse('http://localhost${uri.path}?exp=${uri.queryParameters['exp']}&sig=00')));
      expect(tampered.statusCode, 403);
      final exe = await call('POST', '/api/ideas/$id/attachments', token: token, bytes: [1], contentType: 'application/x-msdownload');
      expect(exe.status, 400);

      final removed = await call('DELETE', '/api/attachments/${att['id']}', token: token);
      expect(removed.body['attachments'], hasLength(1));
      expect(storageDir.listSync(), isEmpty);
    });

    test('Umsetzungsvorschlag: Versionen, Teil neu erzeugen, bearbeiten', () async {
      final token = await register('a@example.com');
      final accountId = await connect(token);
      final idea = await call('POST', '/api/ideas', token: token, json: {'title': 'Reel-Idee', 'account_id': accountId});
      final id = idea.body['id'];

      final v1 = await call('POST', '/api/ideas/$id/suggestions', token: token, json: {});
      expect(v1.status, 201, reason: '${v1.body}');
      expect(v1.body['status'], 'in_progress');
      expect(v1.body['suggestions'], hasLength(1));
      expect(v1.body['suggestions'][0]['hooks'], hasLength(3));
      // Die 5 besten eigenen Beiträge gehen als Kontext mit.
      expect(ai.lastContext!['beste_eigene_beitraege'], hasLength(2));

      final v2 = await call('POST', '/api/ideas/$id/suggestions', token: token, json: {'part': 'hooks'});
      final suggestions = v2.body['suggestions'] as List;
      expect(suggestions, hasLength(2));
      expect(suggestions[0]['version'], 2);
      expect(suggestions[0]['is_selected'], isTrue);
      expect(suggestions[1]['is_selected'], isFalse);
      expect(suggestions[0]['hooks'][0], 'Hook A2');
      // Nur die Hooks sind neu, der Rest bleibt wie in Version 1.
      expect(suggestions[0]['cta'], 'Speichern für später (1)');
      expect(suggestions[0]['caption_draft'], 'Caption 1');

      final edited = await call('PATCH', '/api/suggestions/${suggestions[0]['id']}', token: token, json: {'cta': 'Eigener CTA'});
      expect(edited.body['suggestions'][0]['cta'], 'Eigener CTA');
      final back = await call('PATCH', '/api/suggestions/${suggestions[1]['id']}', token: token, json: {'is_selected': true});
      expect((back.body['suggestions'] as List).firstWhere((s) => s['version'] == 1)['is_selected'], isTrue);
      expect((back.body['suggestions'] as List).firstWhere((s) => s['version'] == 2)['is_selected'], isFalse);
    });
  });

  group('Planen und Veröffentlichen', () {
    Future<Map<String, dynamic>> upload(String token, String mime) async {
      final r = await call('POST', '/api/uploads', token: token, bytes: [1, 2, 3, 4], contentType: mime);
      expect(r.status, 201, reason: '${r.body}');
      return {'key': r.body['key'], 'mime_type': r.body['mime_type']};
    }

    test('Vorab-Prüfung der Formatregeln', () {
      expect(PublishService.validate('post', ['image/jpeg']), isEmpty);
      expect(PublishService.validate('post', ['image/png']), isNotEmpty);
      expect(PublishService.validate('reel', ['video/mp4']), isEmpty);
      expect(PublishService.validate('reel', ['image/jpeg']), isNotEmpty);
      expect(PublishService.validate('carousel', ['image/jpeg']), isNotEmpty);
      expect(PublishService.validate('carousel', List.filled(10, 'image/jpeg')), isEmpty);
      expect(PublishService.validate('carousel', List.filled(11, 'image/jpeg')), isNotEmpty);
      expect(PublishService.validate('carousel', ['image/jpeg', 'video/mp4']), isEmpty);
    });

    test('„Jetzt“ veröffentlicht, verknüpft die Idee und räumt Medien weg', () async {
      final token = await register('a@example.com');
      final accountId = await connect(token);
      final idea = await call('POST', '/api/ideas', token: token, json: {'title': 'Post-Idee', 'account_id': accountId});
      final media = await upload(token, 'image/jpeg');
      final post = await call('POST', '/api/posts', token: token, json: {
        'account_id': accountId, 'idea_id': idea.body['id'], 'format': 'post', 'caption': 'Hallo Welt', 'publish_now': true, 'media': [media],
      });
      expect(post.status, 201, reason: '${post.body}');
      await publisher.publish(post.body['id'] as String); // falls der Hintergrundlauf noch nicht fertig ist
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final after = await call('GET', '/api/posts/${post.body['id']}', token: token);
      expect(after.body['status'], 'published', reason: '${after.body}');
      expect(after.body['published_permalink'], contains('instagram.com'));
      expect(ig.created.single['caption'], 'Hallo Welt');
      expect(ig.created.single['image_url'], startsWith('https://server.test/media/'));
      final ideas = await call('GET', '/api/ideas', token: token);
      expect(ideas.body[0]['status'], 'published');
      expect(ideas.body[0]['published_permalink'], isNotNull);
      expect(storageDir.listSync(), isEmpty);
      expect(ig.publishUsed, 1); // nicht doppelt veröffentlicht
    });

    test('Termin: der Server veröffentlicht erst, wenn er fällig ist', () async {
      final token = await register('a@example.com');
      final accountId = await connect(token);
      final media = [await upload(token, 'image/jpeg'), await upload(token, 'video/mp4')];
      final when = DateTime.now().toUtc().add(const Duration(hours: 2));
      final post = await call('POST', '/api/posts', token: token, json: {
        'account_id': accountId, 'format': 'carousel', 'caption': 'Karussell', 'scheduled_for': when.toIso8601String(), 'media': media,
      });
      expect(post.body['status'], 'scheduled');
      await publisher.publishDue();
      expect(ig.created, isEmpty);

      // Verschieben per Ziehen im Kalender.
      final moved = await call('PATCH', '/api/posts/${post.body['id']}', token: token, json: {
        'scheduled_for': DateTime.now().toUtc().subtract(const Duration(minutes: 1)).toIso8601String(),
      });
      expect(moved.status, 200);
      await publisher.publishDue();
      final after = await call('GET', '/api/posts/${post.body['id']}', token: token);
      expect(after.body['status'], 'published');
      // 2 Kind-Container + 1 Karussell-Container.
      expect(ig.created, hasLength(3));
      expect(ig.created.last['media_type'], 'CAROUSEL');
    });

    test('Fehler: Status „fehlgeschlagen“ mit Grund, Benachrichtigung, Wiederholen', () async {
      final token = await register('a@example.com');
      final accountId = await connect(token);
      final media = await upload(token, 'image/jpeg');
      ig.publishUsed = 50; // Tageslimit erreicht
      final post = await call('POST', '/api/posts', token: token, json: {
        'account_id': accountId, 'format': 'post', 'scheduled_for': DateTime.now().toUtc().add(const Duration(seconds: 1)).toIso8601String(), 'media': [media],
      });
      await publisher.publish(post.body['id'] as String);
      var after = await call('GET', '/api/posts/${post.body['id']}', token: token);
      expect(after.body['status'], 'failed');
      expect(after.body['error_message'], contains('Tageslimit'));
      final notes = await call('GET', '/api/notifications', token: token);
      expect((notes.body as List).any((n) => n['kind'] == 'publish_failed'), isTrue);

      ig.publishUsed = 0;
      expect((await call('POST', '/api/posts/${post.body['id']}/retry', token: token)).status, 200);
      await publisher.publish(post.body['id'] as String);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      after = await call('GET', '/api/posts/${post.body['id']}', token: token);
      expect(after.body['status'], 'published');
    });

    test('ungültige Medien und fehlende Verbindung werden vorab abgelehnt', () async {
      final token = await register('a@example.com');
      final accountId = await connect(token);
      final png = await upload(token, 'image/png');
      final bad = await call('POST', '/api/posts', token: token, json: {'account_id': accountId, 'format': 'post', 'publish_now': true, 'media': [png]});
      expect(bad.status, 400);
      expect(bad.body['message'], contains('JPEG'));
      final check = await call('POST', '/api/posts/validate', token: token, json: {'account_id': accountId, 'format': 'post', 'media': [png]});
      expect(check.body['problems'], isNotEmpty);
      expect(check.body['limit']['remaining'], 50);

      final manual = await call('POST', '/api/accounts/manual', token: token, json: {'username': 'privat'});
      final jpg = await upload(token, 'image/jpeg');
      final noConn = await call('POST', '/api/posts', token: token, json: {'account_id': manual.body['id'], 'format': 'post', 'publish_now': true, 'media': [jpg]});
      expect(noConn.body['error'], 'no_connection');
      // Reine Planung geht auch ohne Verbindung.
      final plan = await call('POST', '/api/posts', token: token, json: {
        'account_id': manual.body['id'], 'format': 'reel', 'plan_only': true, 'scheduled_for': '2026-12-24T09:00:00Z',
      });
      expect(plan.status, 201);
      expect(plan.body['status'], 'draft');
      await publisher.publishDue();
      expect((await call('GET', '/api/posts/${plan.body['id']}', token: token)).body['status'], 'draft');
    });
  });

  group('Hintergrundjobs', () {
    test('ein Takt läuft durch und Jobs laufen nicht doppelt', () async {
      final token = await register('a@example.com');
      await connect(token);
      final scheduler = Scheduler(services, sync, publisher);
      await scheduler.tick();
      final first = await db.one("SELECT last_run_at FROM job_runs WHERE name = 'daily'");
      await scheduler.tick();
      final second = await db.one("SELECT last_run_at FROM job_runs WHERE name = 'daily'");
      expect(second!['last_run_at'], first!['last_run_at']);
    });
  });
}
