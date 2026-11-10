import 'dart:convert';

import 'package:content_hub_server/server.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

Config _config({String configId = 'cfg-1'}) => Config(
  port: 0,
  databaseUrl: '',
  publicBaseUrl: 'https://example.test',
  appCallbackUrl: 'https://example.test/oauth-fertig',
  tokenEncryptionKey: '',
  storageDir: '/tmp',
  webDir: '',
  instagramAppId: '',
  instagramAppSecret: '',
  facebookAppId: 'app-1',
  facebookAppSecret: 'secret-1',
  facebookConfigId: configId,
  graphApiVersion: 'v25.0',
  aiApiKey: '',
  aiModel: '',
  enableScheduler: false,
);

void main() {
  group('Meta Unified Login', () {
    test('Anmelde-Link nutzt config_id statt scope', () {
      final api = GraphInstagramApi(_config());
      final url = api.authorizeUrl(loginType: 'facebook', state: 'st', redirectUri: 'https://example.test/api/oauth/callback');
      expect(url.host, 'www.facebook.com');
      expect(url.path, '/dialog/oauth');
      expect(url.queryParameters['config_id'], 'cfg-1');
      expect(url.queryParameters['client_id'], 'app-1');
      expect(url.queryParameters['response_type'], 'code');
      expect(url.queryParameters.containsKey('scope'), isFalse);
    });

    test('Ohne Konfigurations-ID bleibt der bisherige Facebook Login', () {
      final api = GraphInstagramApi(_config(configId: ''));
      final url = api.authorizeUrl(loginType: 'facebook', state: 'st', redirectUri: 'https://example.test/cb');
      expect(url.path, '/v25.0/dialog/oauth');
      expect(url.queryParameters['scope'], isNotEmpty);
    });

    test('Code-Tausch mit einer Anfrage, Accounts ohne Facebook-Seite', () async {
      final calls = <Uri>[];
      final client = MockClient((req) async {
        calls.add(req.url);
        if (req.url.path.endsWith('/oauth/access_token')) {
          return http.Response(jsonEncode({'access_token': 'sys-token'}), 200);
        }
        if (req.url.path.endsWith('/me/assigned_instagram_accounts')) {
          return http.Response(jsonEncode({'data': [{'id': '1784', 'username': 'mein_account'}]}), 200);
        }
        return http.Response('{}', 404);
      });
      final api = GraphInstagramApi(_config(), client);
      final token = await api.exchangeCode(loginType: 'facebook', code: 'c', redirectUri: 'https://example.test/cb');
      expect(token.accessToken, 'sys-token');
      expect(token.expiresAt, isNull);
      expect(calls.single.queryParameters.containsKey('fb_exchange_token'), isFalse);
      final accounts = await api.facebookAccounts('sys-token');
      expect(accounts.single.igUserId, '1784');
      expect(accounts.single.username, 'mein_account');
      expect(accounts.single.pageId, isEmpty);
    });
  });
}
