import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../config.dart';
import '../db.dart';
import '../http_utils.dart';
import '../security.dart';
import '../services/services.dart';

/// Anmeldung, Konto, Team und Datenschutz.
class AuthRoutes {
  AuthRoutes(this.s);

  final Services s;

  /// Routen ohne Anmeldung.
  void addPublic(Router r) {
    r.post('/api/auth/register', _register);
    r.post('/api/auth/login', _login);
    r.post('/api/meta/data-deletion', _metaDataDeletion);
    r.get('/api/meta/deletion-status', _metaDeletionStatus);
  }

  /// Routen mit Anmeldung.
  void addPrivate(Router r) {
    r.post('/api/auth/logout', _logout);
    r.get('/api/me', _me);
    r.delete('/api/me', _deleteMe);
    r.get('/api/export', _export);
    r.patch('/api/workspace', _renameWorkspace);
    r.get('/api/team', _team);
    r.post('/api/team/invites', _invite);
    r.delete('/api/team/members/<userId>', _removeMember);
    r.get('/api/notifications', _notifications);
    r.post('/api/notifications/read', _readNotifications);
  }

  Future<Response> _register(Request request) async {
    final body = await readJson(request);
    final email = body.reqString('email', maxLength: 200).toLowerCase();
    final name = body.reqString('name', maxLength: 100);
    final password = body.reqString('password', maxLength: 200);
    final inviteCode = body.optString('invite_code')?.trim().toUpperCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      throw ApiError.badRequest('Bitte eine gültige E-Mail-Adresse angeben.');
    }
    if (password.length < 10) {
      throw ApiError.badRequest('Das Passwort braucht mindestens 10 Zeichen.');
    }
    if (await s.db.one('SELECT 1 FROM users WHERE email = @e', {'e': email}) != null) {
      throw ApiError(409, 'email_taken', 'Für diese E-Mail-Adresse gibt es schon ein Konto.');
    }
    final hash = await Security.hashPassword(password);
    final userId = await s.db.tx((db) async {
      String? workspaceId;
      var role = 'owner';
      if (inviteCode != null && inviteCode.isNotEmpty) {
        final invite = await db.one(
          'SELECT workspace_id FROM invites WHERE code = @c AND used_by IS NULL AND expires_at > @now',
          {'c': inviteCode, 'now': s.now()},
        );
        if (invite == null) {
          throw ApiError(400, 'invite_invalid', 'Der Einladungscode ist ungültig oder abgelaufen.');
        }
        workspaceId = invite['workspace_id'] as String;
        role = 'member';
      }
      final user = await db.one(
        "INSERT INTO users (email, name, auth_provider, password_hash) VALUES (@e, @n, 'email', @h) RETURNING id",
        {'e': email, 'n': name, 'h': hash},
      );
      final id = user!['id'] as String;
      if (workspaceId == null) {
        final ws = await db.one('INSERT INTO workspaces (name) VALUES (@n) RETURNING id', {
          'n': body.optString('workspace_name')?.trim().isNotEmpty == true ? body.optString('workspace_name')!.trim() : 'Workspace von $name',
        });
        workspaceId = ws!['id'] as String;
      } else {
        await db.exec('UPDATE invites SET used_by = @u WHERE code = @c', {'u': id, 'c': inviteCode});
      }
      await db.exec('INSERT INTO memberships (workspace_id, user_id, role) VALUES (@w, @u, @r)', {
        'w': workspaceId,
        'u': id,
        'r': role,
      });
      return id;
    });
    return jsonOk({'token': await _createSession(userId)}, status: 201);
  }

  Future<Response> _login(Request request) async {
    final body = await readJson(request);
    final email = body.reqString('email').toLowerCase();
    final password = body.reqString('password');
    final user = await s.db.one('SELECT id, password_hash FROM users WHERE email = @e', {'e': email});
    final hash = user?['password_hash'] as String?;
    // Auch bei unbekannter E-Mail rechnen, damit die Antwortzeit nichts verrät.
    final ok = await Security.verifyPassword(password, hash ?? r'pbkdf2$210000$AAAAAAAAAAAAAAAAAAAAAA==$AAAA');
    if (user == null || hash == null || !ok) {
      throw ApiError(401, 'login_failed', 'E-Mail oder Passwort stimmt nicht.');
    }
    return jsonOk({'token': await _createSession(user['id'] as String)});
  }

  Future<String> _createSession(String userId) async {
    final token = Security.randomToken();
    await s.db.exec('INSERT INTO sessions (token_hash, user_id, expires_at) VALUES (@h, @u, @e)', {
      'h': await Security.sha256Hex(token),
      'u': userId,
      'e': s.now().add(const Duration(days: AppLimits.sessionDays)),
    });
    return token;
  }

  Future<Response> _logout(Request request) async {
    final token = request.headers['authorization']!.substring(7);
    await s.db.exec('DELETE FROM sessions WHERE token_hash = @h', {'h': await Security.sha256Hex(token)});
    return jsonOk({'ok': true});
  }

  Future<Response> _me(Request request) async {
    final auth = authOf(request);
    final user = await s.db.one('SELECT id, email, name FROM users WHERE id = @u', {'u': auth.userId});
    final ws = await s.db.one('SELECT id, name FROM workspaces WHERE id = @w', {'w': auth.workspaceId});
    return jsonOk({
      'user': user,
      'workspace': ws,
      'role': auth.role,
      // Was auf dem Server eingerichtet ist; die App zeigt sonst Hinweise.
      'server': {
        'instagram_login': s.config.instagramLoginConfigured,
        'facebook_login': s.config.facebookLoginConfigured,
        'ai': s.config.aiConfigured,
      },
    });
  }

  /// Konto löschen. Ist die Person die letzte im Workspace, wird der ganze
  /// Workspace mit allen Daten gelöscht.
  Future<Response> _deleteMe(Request request) async {
    final auth = authOf(request);
    final keys = <String>[];
    await s.db.tx((db) async {
      final others = await db.one(
        'SELECT count(*)::int AS n FROM memberships WHERE workspace_id = @w AND user_id <> @u',
        {'w': auth.workspaceId, 'u': auth.userId},
      );
      final otherCount = others!['n'] as int;
      if (otherCount == 0) {
        keys.addAll(await _storageKeys(db, auth.workspaceId));
        await db.exec('DELETE FROM workspaces WHERE id = @w', {'w': auth.workspaceId});
      } else if (auth.isOwner) {
        final otherOwners = await db.one(
          "SELECT count(*)::int AS n FROM memberships WHERE workspace_id = @w AND user_id <> @u AND role = 'owner'",
          {'w': auth.workspaceId, 'u': auth.userId},
        );
        if (otherOwners!['n'] == 0) {
          // Ältestes Mitglied übernimmt die Owner-Rolle.
          await db.exec(
            '''UPDATE memberships SET role = 'owner' WHERE workspace_id = @w AND user_id = (
                 SELECT m.user_id FROM memberships m JOIN users u ON u.id = m.user_id
                 WHERE m.workspace_id = @w AND m.user_id <> @u ORDER BY u.created_at LIMIT 1)''',
            {'w': auth.workspaceId, 'u': auth.userId},
          );
        }
      }
      await db.exec('DELETE FROM users WHERE id = @u', {'u': auth.userId});
    });
    for (final key in keys) {
      await s.storage.delete(key);
    }
    return jsonOk({'ok': true});
  }

  static Future<List<String>> _storageKeys(Db db, String workspaceId) async {
    final rows = await db.query(
      '''SELECT at.storage_key FROM idea_attachments at JOIN ideas i ON i.id = at.idea_id
         WHERE i.workspace_id = @w AND at.storage_key IS NOT NULL
         UNION ALL
         SELECT pm.storage_key FROM scheduled_post_media pm
           JOIN scheduled_posts p ON p.id = pm.scheduled_post_id
           JOIN instagram_accounts a ON a.id = p.account_id
         WHERE a.workspace_id = @w''',
      {'w': workspaceId},
    );
    return [for (final r in rows) r['storage_key'] as String];
  }

  /// Datenexport (DSGVO): alle Workspace-Daten als JSON, ohne Tokens.
  Future<Response> _export(Request request) async {
    final auth = authOf(request);
    final w = {'w': auth.workspaceId};
    Future<List<Map<String, dynamic>>> q(String sql) async => [for (final r in await s.db.query(sql, w)) rowJson(r)];
    final data = {
      'exported_at': s.now().toIso8601String(),
      'workspace': await q('SELECT * FROM workspaces WHERE id = @w'),
      'members': await q('SELECT u.id, u.email, u.name, m.role FROM users u JOIN memberships m ON m.user_id = u.id WHERE m.workspace_id = @w'),
      'accounts': await q('SELECT * FROM instagram_accounts WHERE workspace_id = @w'),
      'niches': await q('SELECT * FROM niches WHERE workspace_id = @w'),
      'ideas': await q('SELECT * FROM ideas WHERE workspace_id = @w'),
      'suggestions': await q('SELECT cs.* FROM content_suggestions cs JOIN ideas i ON i.id = cs.idea_id WHERE i.workspace_id = @w'),
      'trends': await q('SELECT t.* FROM trends t JOIN trend_sources ts ON ts.id = t.source_id WHERE ts.workspace_id = @w'),
      'scheduled_posts': await q('SELECT p.* FROM scheduled_posts p JOIN instagram_accounts a ON a.id = p.account_id WHERE a.workspace_id = @w'),
      'media': await q('SELECT m.* FROM media m JOIN instagram_accounts a ON a.id = m.account_id WHERE a.workspace_id = @w'),
      'media_metrics': await q('SELECT mm.* FROM media_metrics mm JOIN media m ON m.id = mm.media_id JOIN instagram_accounts a ON a.id = m.account_id WHERE a.workspace_id = @w'),
      'account_daily_metrics': await q('SELECT dm.* FROM account_daily_metrics dm JOIN instagram_accounts a ON a.id = dm.account_id WHERE a.workspace_id = @w'),
      'follower_snapshots': await q('SELECT fs.* FROM follower_snapshots fs JOIN instagram_accounts a ON a.id = fs.account_id WHERE a.workspace_id = @w'),
      'story_metric_snapshots': await q('SELECT ss.* FROM story_metric_snapshots ss JOIN media m ON m.id = ss.media_id JOIN instagram_accounts a ON a.id = m.account_id WHERE a.workspace_id = @w'),
      'competitors': await q('SELECT c.* FROM competitor_accounts c JOIN instagram_accounts a ON a.id = c.account_id WHERE a.workspace_id = @w'),
      'hashtag_watches': await q('SELECT h.* FROM hashtag_watches h JOIN instagram_accounts a ON a.id = h.account_id WHERE a.workspace_id = @w'),
    };
    await s.audit(auth.workspaceId, auth.userId, 'export');
    return Response.ok(
      const JsonEncoder.withIndent('  ').convert(data),
      headers: {
        'content-type': 'application/json; charset=utf-8',
        'content-disposition': 'attachment; filename="content-hub-export.json"',
      },
    );
  }

  Future<Response> _renameWorkspace(Request request) async {
    final auth = authOf(request)..requireOwner();
    final body = await readJson(request);
    await s.db.exec('UPDATE workspaces SET name = @n WHERE id = @w', {
      'n': body.reqString('name', maxLength: 100),
      'w': auth.workspaceId,
    });
    return jsonOk({'ok': true});
  }

  Future<Response> _team(Request request) async {
    final auth = authOf(request);
    final members = await s.db.query(
      '''SELECT u.id, u.name, u.email, m.role FROM memberships m JOIN users u ON u.id = m.user_id
         WHERE m.workspace_id = @w ORDER BY m.role DESC, u.name''',
      {'w': auth.workspaceId},
    );
    final invites = auth.isOwner
        ? await s.db.query(
            'SELECT code, expires_at FROM invites WHERE workspace_id = @w AND used_by IS NULL AND expires_at > @now ORDER BY expires_at',
            {'w': auth.workspaceId, 'now': s.now()},
          )
        : <Map<String, dynamic>>[];
    return jsonOk({'members': members, 'invites': invites.map(rowJson).toList()});
  }

  /// Erzeugt einen Einladungscode. Annahme: Der Code wird von Hand
  /// weitergegeben; E-Mail-Versand bräuchte einen Mail-Dienst.
  Future<Response> _invite(Request request) async {
    final auth = authOf(request)..requireOwner();
    final code = Security.inviteCode();
    final expires = s.now().add(const Duration(days: AppLimits.inviteDays));
    await s.db.exec('INSERT INTO invites (code, workspace_id, created_by, expires_at) VALUES (@c, @w, @u, @e)', {
      'c': code,
      'w': auth.workspaceId,
      'u': auth.userId,
      'e': expires,
    });
    await s.audit(auth.workspaceId, auth.userId, 'invite_created');
    return jsonOk({'code': code, 'expires_at': expires}, status: 201);
  }

  Future<Response> _removeMember(Request request, String userId) async {
    final auth = authOf(request)..requireOwner();
    if (userId == auth.userId) throw ApiError.badRequest('Du kannst dich nicht selbst entfernen.');
    final row = await s.db.one(
      'DELETE FROM memberships WHERE workspace_id = @w AND user_id = @u RETURNING user_id',
      {'w': auth.workspaceId, 'u': userId},
    );
    if (row == null) throw ApiError.notFound('Mitglied');
    // Ohne Workspace hat das Konto keinen Zweck mehr (ein Workspace je Person).
    await s.db.exec('DELETE FROM users WHERE id = @u', {'u': userId});
    await s.audit(auth.workspaceId, auth.userId, 'member_removed', userId);
    return jsonOk({'ok': true});
  }

  Future<Response> _notifications(Request request) async {
    final auth = authOf(request);
    final rows = await s.db.query(
      'SELECT * FROM notifications WHERE workspace_id = @w ORDER BY created_at DESC LIMIT 50',
      {'w': auth.workspaceId},
    );
    return jsonOk(rows.map(rowJson).toList());
  }

  Future<Response> _readNotifications(Request request) async {
    final auth = authOf(request);
    await s.db.exec('UPDATE notifications SET read_at = @now WHERE workspace_id = @w AND read_at IS NULL', {
      'w': auth.workspaceId,
      'now': s.now(),
    });
    return jsonOk({'ok': true});
  }

  // -------------------------------------------------------------------
  // Data-Deletion-Callback für Meta (Spezifikation 7.5 und 7.6)
  // -------------------------------------------------------------------

  Future<Response> _metaDataDeletion(Request request) async {
    final form = Uri.splitQueryString(await request.readAsString());
    final signed = form['signed_request'];
    if (signed == null || !signed.contains('.')) throw ApiError.badRequest('signed_request fehlt.');
    final parts = signed.split('.');
    List<int> b64(String v) => base64Url.decode(base64Url.normalize(v));
    final payloadBytes = utf8.encode(parts[1]);
    var valid = false;
    for (final secret in [s.config.instagramAppSecret, s.config.facebookAppSecret]) {
      if (secret.isEmpty) continue;
      final expected = await Security.hmacBytes(secret, payloadBytes);
      final given = b64(parts[0]);
      if (expected.length == given.length) {
        var diff = 0;
        for (var i = 0; i < expected.length; i++) {
          diff |= expected[i] ^ given[i];
        }
        if (diff == 0) valid = true;
      }
    }
    if (!valid) throw ApiError.forbidden('Signatur ungültig.');
    final payload = jsonDecode(utf8.decode(b64(parts[1]))) as Map<String, dynamic>;
    final igUserId = payload['user_id']?.toString();
    final code = Security.randomToken(12);
    if (igUserId != null) {
      // Gleiche Löschung wie „Trennen und Daten löschen“.
      await s.db.exec('DELETE FROM instagram_accounts WHERE ig_user_id = @id', {'id': igUserId});
    }
    await s.db.exec("INSERT INTO deletion_requests (confirmation_code, ig_user_id, status) VALUES (@c, @id, 'completed')", {
      'c': code,
      'id': igUserId,
    });
    return jsonOk({
      'url': '${s.config.publicBaseUrl}/api/meta/deletion-status?code=$code',
      'confirmation_code': code,
    });
  }

  Future<Response> _metaDeletionStatus(Request request) async {
    final code = request.url.queryParameters['code'] ?? '';
    final row = await s.db.one('SELECT status, created_at FROM deletion_requests WHERE confirmation_code = @c', {'c': code});
    if (row == null) throw ApiError.notFound('Löschanfrage');
    return jsonOk(rowJson(row));
  }
}
