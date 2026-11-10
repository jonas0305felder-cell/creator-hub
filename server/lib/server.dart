import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';

import 'src/http_utils.dart';
import 'src/routes/account_routes.dart';
import 'src/routes/auth_routes.dart';
import 'src/routes/content_routes.dart';
import 'src/routes/stats_routes.dart';
import 'src/security.dart';
import 'src/services/publish_service.dart';
import 'src/services/services.dart';
import 'src/services/sync_service.dart';
import 'src/storage.dart';

export 'src/config.dart';
export 'src/db.dart';
export 'src/scheduler.dart';
export 'src/security.dart';
export 'src/services/ai_service.dart';
export 'src/services/publish_service.dart';
export 'src/services/rss_service.dart';
export 'src/services/services.dart';
export 'src/services/sync_service.dart';
export 'src/storage.dart';
export 'src/instagram/instagram_api.dart';

/// Baut den HTTP-Handler des Servers aus allen Routen zusammen.
Handler buildHandler(Services s, SyncService sync, PublishService publisher) {
  final auth = AuthRoutes(s);
  final accounts = AccountRoutes(s, sync);
  final stats = StatsRoutes(s, sync);
  final content = ContentRoutes(s, sync, publisher);

  // Öffentliche Routen (ohne Anmeldung).
  final public = Router();
  public.get('/api/health', (Request _) => jsonOk({'ok': true}));
  auth.addPublic(public);
  accounts.addPublic(public);
  public.get('/media/<key>', (Request request, String key) => _serveMedia(s.storage, request, key));
  public.get('/oauth-fertig', (Request _) => Response.ok(_oauthDonePage, headers: {'content-type': 'text/html; charset=utf-8'}));

  // Geschützte Routen (mit Sitzungs-Token).
  final private = Router();
  auth.addPrivate(private);
  accounts.addPrivate(private);
  stats.addPrivate(private);
  content.addPrivate(private);
  final privateHandler = const Pipeline().addMiddleware(_authenticate(s)).addHandler(private.call);

  Handler? web;
  if (s.config.webDir.isNotEmpty && Directory(s.config.webDir).existsSync()) {
    web = createStaticHandler(s.config.webDir, defaultDocument: 'index.html');
  }

  Future<Response> root(Request request) async {
    final response = await public.call(request);
    if (response.statusCode != 404) return response;
    if (request.url.path.startsWith('api/')) return privateHandler(request);
    if (web != null) return web(request);
    return Response.notFound('Nicht gefunden');
  }

  return const Pipeline().addMiddleware(_cors()).addMiddleware(_errors()).addHandler(root);
}

/// Wandelt Fehler in JSON-Antworten um; unerwartete Fehler landen im Log,
/// aber nie mit Details bei der App.
Middleware _errors() => (inner) => (request) async {
  try {
    return await inner(request);
  } on ApiError catch (e) {
    return jsonError(e);
  } on HijackException {
    rethrow;
  } catch (e, stack) {
    stderr.writeln('[${request.method} /${request.url.path}] $e\n$stack');
    return jsonError(ApiError(500, 'server_error', 'Auf dem Server ist ein Fehler aufgetreten.'));
  }
};

/// CORS: Die App meldet sich mit einem Bearer-Token an (keine Cookies),
/// daher sind Anfragen von anderen Adressen unkritisch und erlaubt. Das
/// braucht man z. B. für `flutter run -d chrome` während der Entwicklung.
Middleware _cors() {
  const headers = {
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET, POST, PATCH, DELETE, OPTIONS',
    'access-control-allow-headers': 'authorization, content-type',
    'access-control-max-age': '86400',
  };
  return (inner) => (request) async {
    if (request.method == 'OPTIONS') return Response.ok('', headers: headers);
    final response = await inner(request);
    return response.change(headers: headers);
  };
}

Middleware _authenticate(Services s) => (inner) => (request) async {
  final header = request.headers['authorization'] ?? '';
  if (!header.startsWith('Bearer ')) throw ApiError.unauthorized();
  final row = await s.db.one(
    '''SELECT se.user_id, m.workspace_id, m.role FROM sessions se
         JOIN memberships m ON m.user_id = se.user_id
       WHERE se.token_hash = @h AND se.expires_at > @now LIMIT 1''',
    {'h': await Security.sha256Hex(header.substring(7)), 'now': s.now()},
  );
  if (row == null) throw ApiError.unauthorized();
  return inner(
    request.change(
      context: {
        'auth': AuthContext(
          userId: row['user_id'] as String,
          workspaceId: row['workspace_id'] as String,
          role: row['role'] as String,
        ),
      },
    ),
  );
};

/// Liefert eine hochgeladene Datei aus, aber nur mit gültiger Signatur.
Future<Response> _serveMedia(MediaStorage storage, Request request, String key) async {
  final q = request.url.queryParameters;
  if (!await storage.verify(key, q['exp'], q['sig'])) return Response.forbidden('Link ungültig oder abgelaufen.');
  final file = storage.file(key);
  if (file == null) return Response.notFound('Nicht gefunden');
  return Response.ok(
    file.openRead(),
    headers: {
      'content-type': MediaStorage.mimeFor(key),
      'content-length': '${await file.length()}',
      'cache-control': 'private, max-age=3600',
    },
  );
}

/// Seite, auf der der Instagram-Login in der Web-App endet. Sie reicht das
/// Ergebnis an das App-Fenster zurück und schließt sich.
const _oauthDonePage = '''<!DOCTYPE html>
<html lang="de"><head><meta charset="utf-8"><title>Verbindung abgeschlossen</title>
<meta name="viewport" content="width=device-width, initial-scale=1"></head>
<body style="font-family: sans-serif; padding: 24px">
<p>Verbindung abgeschlossen. Dieses Fenster kann geschlossen werden.</p>
<script>
  var data = {'flutter-web-auth-2': window.location.href};
  if (window.opener) { window.opener.postMessage(data, window.location.origin); window.close(); }
  else { try { localStorage.setItem('flutter-web-auth-2', window.location.href); } catch (e) {} window.close(); }
</script>
</body></html>''';
