import 'dart:convert';

import 'package:content_hub/main.dart';
import 'package:content_hub/services/api_client.dart';
import 'package:content_hub/services/session_store.dart';
import 'package:content_hub/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Kleiner Ersatz-Server mit festen Antworten.
MockClient fakeServer({bool failIdeas = false, List<Map<String, dynamic>> ideas = const []}) => MockClient((request) async {
  http.Response json(Object body, [int status = 200]) =>
      http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});
  if (request.headers['authorization'] != 'Bearer test-token' && !request.url.path.startsWith('/api/auth')) {
    return json({'error': 'unauthorized', 'message': 'Bitte anmelden.'}, 401);
  }
  return switch (request.url.path) {
    '/api/auth/login' => json({'token': 'test-token'}),
    '/api/me' => json({
      'user': {'id': 'u1', 'email': 'test@example.com', 'name': 'Test'},
      'workspace': {'id': 'w1', 'name': 'Workspace'},
      'role': 'owner',
      'server': {'instagram_login': false, 'facebook_login': false, 'ai': false},
    }),
    '/api/accounts' => json([
      {'id': 'a1', 'username': 'kaffee', 'account_type': 'manual', 'connection_status': 'manual', 'color': '#0EA5E9', 'niches': []},
    ]),
    '/api/niches' => json([]),
    '/api/ideas' => failIdeas ? json({'error': 'server_error', 'message': 'Kaputt'}, 500) : json(ideas),
    '/api/team' => json({'members': [], 'invites': []}),
    '/api/notifications' => json([]),
    '/api/stats/overview' => json({'accounts': [], 'warnings': [], 'unanswered_comments': {}}),
    '/api/trends' => json({'trends': [], 'sources': []}),
    _ => json({'error': 'not_found', 'message': 'Nicht gefunden'}, 404),
  };
});

Future<AppState> pumpApp(WidgetTester tester, MockClient client, {String? token}) async {
  await initializeDateFormatting('de');
  final state = AppState(
    api: ApiClient(client: client, baseUrl: 'http://test'),
    store: MemorySessionStore()..token = token,
  );
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ContentHubApp(state: state));
  await state.start();
  await tester.pumpAndSettle();
  return state;
}

void main() {
  testWidgets('ohne Sitzung erscheint die Anmeldung', (tester) async {
    await pumpApp(tester, fakeServer());
    expect(find.text('Anmelden'), findsWidgets);
  });

  testWidgets('Anmelden führt zur Heute-Seite', (tester) async {
    await pumpApp(tester, fakeServer());
    await tester.enterText(find.byType(TextField).at(0), 'test@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'geheim123');
    await tester.tap(find.widgetWithText(FilledButton, 'Anmelden'));
    await tester.pumpAndSettle();
    expect(find.text('Heute'), findsWidgets);
  });

  testWidgets('Planen zeigt leeren Zustand ohne Ideen', (tester) async {
    await pumpApp(tester, fakeServer(), token: 'test-token');
    await tester.tap(find.text('Planen').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Noch keine Ideen'), findsOneWidget);
  });

  testWidgets('Ideen erscheinen und lassen sich durchsuchen', (tester) async {
    final ideas = [
      {'id': 'i1', 'title': 'Herbst-Reel', 'note': '', 'status': 'idea', 'tags': [], 'updated_at': '2026-11-09T10:00:00Z'},
      {'id': 'i2', 'title': 'Kaffee-Tipps', 'note': '', 'status': 'ready', 'tags': [], 'updated_at': '2026-11-08T10:00:00Z'},
    ];
    await pumpApp(tester, fakeServer(ideas: ideas), token: 'test-token');
    await tester.tap(find.text('Planen').last);
    await tester.pumpAndSettle();
    expect(find.text('Herbst-Reel'), findsOneWidget);
    expect(find.text('Kaffee-Tipps'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Ideen durchsuchen'), 'kaffee');
    await tester.pumpAndSettle();
    expect(find.text('Herbst-Reel'), findsNothing);
    expect(find.text('Kaffee-Tipps'), findsOneWidget);
  });

  testWidgets('Serverfehler beim Start zeigt Fehlerzustand mit Wiederholen', (tester) async {
    await pumpApp(tester, fakeServer(failIdeas: true), token: 'test-token');
    expect(find.text('Kaputt'), findsOneWidget);
    expect(find.text('Erneut versuchen'), findsOneWidget);
  });
}
