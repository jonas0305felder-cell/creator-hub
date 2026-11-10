import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../config.dart';
import '../http_utils.dart';
import '../instagram/instagram_api.dart';
import '../security.dart';
import '../services/services.dart';
import '../services/sync_service.dart';

/// Accounts, Instagram-Verbindung (OAuth) und Nischen.
class AccountRoutes {
  AccountRoutes(this.s, this.sync);

  final Services s;
  final SyncService sync;

  static const _colorPattern = r'^#[0-9A-Fa-f]{6}$';

  void addPublic(Router r) {
    r.get('/api/oauth/callback', _oauthCallback);
  }

  void addPrivate(Router r) {
    r.get('/api/accounts', _list);
    r.post('/api/accounts/manual', _createManual);
    r.patch('/api/accounts/<id>', _update);
    r.delete('/api/accounts/<id>', _delete);
    r.post('/api/accounts/<id>/sync', _sync);
    r.post('/api/oauth/start', _oauthStart);
    r.post('/api/oauth/result', _oauthResult);
    r.get('/api/niches', _niches);
    r.post('/api/niches', _createNiche);
    r.patch('/api/niches/<id>', _updateNiche);
    r.delete('/api/niches/<id>', _deleteNiche);
  }

  // -------------------------------------------------------------------
  // Accounts
  // -------------------------------------------------------------------

  Future<Response> _list(Request request) async {
    final auth = authOf(request);
    final rows = await s.db.query(
      '''SELECT a.*, c.token_expires_at, c.login_type,
           COALESCE((SELECT json_agg(json_build_object('niche_id', an.niche_id, 'is_primary', an.is_primary))
                     FROM account_niches an WHERE an.account_id = a.id), '[]'::json) AS niches
         FROM instagram_accounts a LEFT JOIN instagram_credentials c ON c.account_id = a.id
         WHERE a.workspace_id = @w ORDER BY a.created_at''',
      {'w': auth.workspaceId},
    );
    return jsonOk(rows.map(rowJson).toList());
  }

  Future<void> _checkAccountLimit(String workspaceId) async {
    final row = await s.db.one('SELECT count(*)::int AS n FROM instagram_accounts WHERE workspace_id = @w', {'w': workspaceId});
    if ((row!['n'] as int) >= AppLimits.maxAccounts) {
      throw ApiError(409, 'account_limit', 'Es sind höchstens ${AppLimits.maxAccounts} Accounts je Workspace möglich.');
    }
  }

  /// Manueller Account ohne Statistiken (z. B. privates Konto).
  Future<Response> _createManual(Request request) async {
    final auth = authOf(request)..requireOwner();
    final body = await readJson(request);
    await _checkAccountLimit(auth.workspaceId);
    final username = body.reqString('username', maxLength: 60).replaceFirst('@', '');
    final row = await s.db.one(
      '''INSERT INTO instagram_accounts (workspace_id, username, account_type, color, connection_status)
         VALUES (@w, @u, 'manual', @c, 'manual') RETURNING id''',
      {'w': auth.workspaceId, 'u': username, 'c': _color(body) ?? '#6C4CF1'},
    );
    await _setNiches(row!['id'] as String, auth.workspaceId, body);
    await s.audit(auth.workspaceId, auth.userId, 'account_manual_created', username);
    return jsonOk({'id': row['id']}, status: 201);
  }

  String? _color(Map<String, dynamic> body) {
    final color = body.optString('color');
    if (color != null && !RegExp(_colorPattern).hasMatch(color)) {
      throw ApiError.badRequest('Farbe muss im Format #RRGGBB angegeben werden.');
    }
    return color;
  }

  Future<Response> _update(Request request, String id) async {
    final auth = authOf(request);
    final body = await readJson(request);
    await s.accountInWorkspace(id, auth.workspaceId);
    await s.db.exec(
      '''UPDATE instagram_accounts SET
           color = COALESCE(@color, color), tone = COALESCE(@tone, tone),
           audience_note = COALESCE(@aud, audience_note), language = COALESCE(@lang, language)
         WHERE id = @id''',
      {
        'id': id,
        'color': _color(body),
        'tone': body.optString('tone', maxLength: 1000),
        'aud': body.optString('audience_note', maxLength: 1000),
        'lang': body.optString('language', maxLength: 10),
      },
    );
    if (body.containsKey('niche_ids')) await _setNiches(id, auth.workspaceId, body);
    return jsonOk({'ok': true});
  }

  /// Setzt die Nischen eines Accounts; genau eine ist die Hauptnische.
  Future<void> _setNiches(String accountId, String workspaceId, Map<String, dynamic> body) async {
    final ids = body.stringList('niche_ids').toSet().toList();
    var primary = body.optString('primary_niche_id');
    if (ids.isNotEmpty && (primary == null || !ids.contains(primary))) primary = ids.first;
    await s.db.tx((db) async {
      await db.exec('DELETE FROM account_niches WHERE account_id = @a', {'a': accountId});
      for (final nicheId in ids) {
        final ok = await db.one('SELECT 1 FROM niches WHERE id = @n AND workspace_id = @w', {'n': nicheId, 'w': workspaceId});
        if (ok == null) throw ApiError.notFound('Nische');
        await db.exec('INSERT INTO account_niches (account_id, niche_id, is_primary) VALUES (@a, @n, @p)', {
          'a': accountId,
          'n': nicheId,
          'p': nicheId == primary,
        });
      }
    });
  }

  /// „Trennen und Daten löschen“: Token, Metriken und Medien verschwinden
  /// (per Kaskade). Ideen bleiben erhalten, außer `delete_ideas=true`.
  Future<Response> _delete(Request request, String id) async {
    final auth = authOf(request)..requireOwner();
    final account = await s.accountInWorkspace(id, auth.workspaceId);
    final deleteIdeas = request.url.queryParameters['delete_ideas'] == 'true';
    final keys = <String>[];
    await s.db.tx((db) async {
      final media = await db.query(
        'SELECT pm.storage_key FROM scheduled_post_media pm JOIN scheduled_posts p ON p.id = pm.scheduled_post_id WHERE p.account_id = @a',
        {'a': id},
      );
      keys.addAll([for (final m in media) m['storage_key'] as String]);
      if (deleteIdeas) {
        final att = await db.query(
          'SELECT at.storage_key FROM idea_attachments at JOIN ideas i ON i.id = at.idea_id WHERE i.account_id = @a AND at.storage_key IS NOT NULL',
          {'a': id},
        );
        keys.addAll([for (final a in att) a['storage_key'] as String]);
        await db.exec('DELETE FROM ideas WHERE account_id = @a', {'a': id});
      }
      await db.exec('DELETE FROM instagram_accounts WHERE id = @a', {'a': id});
    });
    for (final key in keys) {
      await s.storage.delete(key);
    }
    await s.audit(auth.workspaceId, auth.userId, 'account_disconnected', account['username'] as String);
    return jsonOk({'ok': true});
  }

  Future<Response> _sync(Request request, String id) async {
    final auth = authOf(request);
    final account = await s.accountInWorkspace(id, auth.workspaceId);
    if (account['account_type'] == 'manual') {
      throw ApiError(409, 'manual_account', 'Manuelle Accounts haben keine Statistiken.');
    }
    await sync.syncAccount(id);
    final after = await s.accountInWorkspace(id, auth.workspaceId);
    return jsonOk(rowJson(after));
  }

  // -------------------------------------------------------------------
  // OAuth (Spezifikation 4.1 und 7.2)
  // -------------------------------------------------------------------

  String get _redirectUri => '${s.config.publicBaseUrl}/api/oauth/callback';

  /// Schritt 1: App fragt die Autorisierungs-URL an und öffnet sie im
  /// System-Browser. `state` bindet den Ablauf an die App-Sitzung.
  Future<Response> _oauthStart(Request request) async {
    final auth = authOf(request)..requireOwner();
    final body = await readJson(request);
    final loginType = body.oneOf('login_type', {'instagram', 'facebook'}) ?? 'instagram';
    final configured = loginType == 'facebook' ? s.config.facebookLoginConfigured : s.config.instagramLoginConfigured;
    if (!configured) {
      throw ApiError.notConfigured(loginType == 'facebook' ? 'Facebook Login (Meta-App)' : 'Instagram Login (Meta-App)');
    }
    if (s.config.tokenEncryptionKey.isEmpty) throw ApiError.notConfigured('Die Token-Verschlüsselung');
    final accountId = body.optString('account_id');
    if (accountId != null) {
      await s.accountInWorkspace(accountId, auth.workspaceId);
    } else {
      await _checkAccountLimit(auth.workspaceId);
    }
    final state = Security.randomToken();
    await s.db.exec(
      'INSERT INTO oauth_states (state, user_id, workspace_id, login_type, account_id) VALUES (@s, @u, @w, @l, @a)',
      {'s': state, 'u': auth.userId, 'w': auth.workspaceId, 'l': loginType, 'a': accountId},
    );
    final url = s.instagram.authorizeUrl(loginType: loginType, state: state, redirectUri: _redirectUri);
    return jsonOk({'url': url.toString(), 'callback': s.config.appCallbackUrl});
  }

  /// Schritt 2: Instagram leitet hierher zurück. Der Server tauscht den Code
  /// gegen ein langlebiges Token, speichert es verschlüsselt und öffnet die
  /// App mit einem einmaligen Ergebnis-Code, nie mit dem Token.
  Future<Response> _oauthCallback(Request request) async {
    final q = request.url.queryParameters;
    final stateRow = await s.db.one(
      'DELETE FROM oauth_states WHERE state = @s AND created_at > @t RETURNING *',
      {'s': q['state'] ?? '', 't': s.now().subtract(const Duration(minutes: 30))},
    );
    if (stateRow == null) {
      return Response.forbidden('Diese Anmeldung ist abgelaufen. Bitte in der App erneut starten.');
    }
    final userId = stateRow['user_id'] as String;
    final workspaceId = stateRow['workspace_id'] as String;
    final loginType = stateRow['login_type'] as String;
    String? accountId;
    String? error;
    try {
      if (q['error'] != null || q['code'] == null) {
        throw ApiError(400, 'permission_denied', 'Die Berechtigungen wurden nicht bestätigt.');
      }
      final token = await s.instagram.exchangeCode(loginType: loginType, code: q['code']!, redirectUri: _redirectUri);
      String igUserId;
      String? pageId;
      if (loginType == 'facebook') {
        final linked = await s.instagram.facebookAccounts(token.accessToken);
        if (linked.isEmpty) {
          throw ApiError(409, 'no_facebook_page', s.config.unifiedLogin
              ? 'Es wurde kein freigegebener Instagram-Account gefunden. Wähle bei der Meta-Anmeldung einen Instagram-Account aus.'
              : 'Es wurde kein Instagram-Account gefunden, der mit einer Facebook-Seite verknüpft ist.');
        }
        // Annahme: Sind mehrere Seiten verknüpft, wird beim Neu-Verbinden der
        // passende Account gewählt, sonst der erste noch nicht verbundene.
        FacebookLinkedAccount? chosen;
        final existingId = stateRow['account_id'] as String?;
        if (existingId != null) {
          final existing = await s.db.one('SELECT ig_user_id, username FROM instagram_accounts WHERE id = @id', {'id': existingId});
          chosen = linked.where((l) => l.igUserId == existing?['ig_user_id'] || l.username == existing?['username']).firstOrNull;
        }
        if (chosen == null) {
          for (final l in linked) {
            final taken = await s.db.one('SELECT 1 FROM instagram_accounts WHERE ig_user_id = @id', {'id': l.igUserId});
            if (taken == null) {
              chosen = l;
              break;
            }
          }
        }
        chosen ??= linked.first;
        igUserId = chosen.igUserId;
        pageId = chosen.pageId.isEmpty ? null : chosen.pageId;
      } else {
        igUserId = token.igUserId ?? '';
      }
      final access = IgAccess(loginType: loginType, token: token.accessToken, igUserId: igUserId);
      final profile = await s.instagram.profile(access);
      // Instagram Login liefert die für Insights nötige ID im Feld user_id.
      igUserId = (profile['user_id'] ?? profile['id'] ?? igUserId).toString();
      final type = (profile['account_type'] ?? 'business').toString().toLowerCase();
      final accountType = type.contains('creator') ? 'creator' : 'business';

      accountId = await s.db.tx((db) async {
        final existing = await db.one('SELECT id, workspace_id FROM instagram_accounts WHERE ig_user_id = @ig', {'ig': igUserId});
        String id;
        if (existing != null) {
          if (existing['workspace_id'] != workspaceId) {
            // Keine stille Doppelverbindung (Spezifikation 4.1).
            throw ApiError(409, 'account_in_other_workspace', 'Dieser Account ist bereits in einem anderen Workspace verbunden.');
          }
          id = existing['id'] as String;
        } else if (stateRow['account_id'] != null) {
          // Ein manueller Account wird zu einem verbundenen.
          id = stateRow['account_id'] as String;
        } else {
          final row = await db.one(
            '''INSERT INTO instagram_accounts (workspace_id, ig_user_id, username, account_type, color, connection_status)
               VALUES (@w, @ig, @u, @t, @c, 'connected') RETURNING id''',
            {
              'w': workspaceId,
              'ig': igUserId,
              'u': (profile['username'] ?? '').toString(),
              't': accountType,
              'c': '#6C4CF1',
            },
          );
          id = row!['id'] as String;
        }
        await db.exec(
          '''UPDATE instagram_accounts SET ig_user_id = @ig, username = @u, account_type = @t,
               profile_picture_url = @pic, connection_status = 'connected', last_sync_error = NULL
             WHERE id = @id''',
          {
            'id': id,
            'ig': igUserId,
            'u': (profile['username'] ?? '').toString(),
            't': accountType,
            'pic': profile['profile_picture_url'],
          },
        );
        await db.exec(
          '''INSERT INTO instagram_credentials (account_id, encrypted_access_token, token_expires_at, granted_scopes, login_type, facebook_page_id, last_refreshed_at)
             VALUES (@a, @t, @e, @s, @l, @p, @now)
             ON CONFLICT (account_id) DO UPDATE SET encrypted_access_token = @t, token_expires_at = @e,
               granted_scopes = @s, login_type = @l, facebook_page_id = @p, last_refreshed_at = @now''',
          {
            'a': id,
            't': await s.security.encrypt(token.accessToken),
            'e': token.expiresAt,
            's': token.scopes,
            'l': loginType,
            'p': pageId,
            'now': s.now(),
          },
        );
        return id;
      });
      await s.audit(workspaceId, userId, 'account_connected', profile['username']?.toString());
      // Erste Synchronisation im Hintergrund.
      unawaited(sync.syncAccount(accountId!));
    } on ApiError catch (e) {
      error = e.code;
    } on InstagramApiException catch (e) {
      error = e.isPermissionError ? 'permission_denied' : 'instagram_error';
    } catch (_) {
      error = 'server_error';
    }
    final resultCode = Security.randomToken(24);
    await s.db.exec('INSERT INTO oauth_results (code, user_id, account_id, error) VALUES (@c, @u, @a, @e)', {
      'c': resultCode,
      'u': userId,
      'a': accountId,
      'e': error,
    });
    final target = Uri.parse(s.config.appCallbackUrl);
    return Response.found(target.replace(queryParameters: {...target.queryParameters, 'result': resultCode}));
  }

  /// Schritt 3: App löst den Ergebnis-Code ein (einmalig, 10 Minuten gültig).
  Future<Response> _oauthResult(Request request) async {
    final auth = authOf(request);
    final body = await readJson(request);
    final row = await s.db.one(
      'DELETE FROM oauth_results WHERE code = @c AND user_id = @u AND created_at > @t RETURNING account_id, error',
      {'c': body.reqString('code'), 'u': auth.userId, 't': s.now().subtract(const Duration(minutes: 10))},
    );
    if (row == null) throw ApiError(400, 'result_invalid', 'Das Ergebnis der Anmeldung ist abgelaufen. Bitte erneut verbinden.');
    if (row['error'] != null) {
      final code = row['error'] as String;
      throw ApiError(409, code, switch (code) {
        'permission_denied' => 'Die Berechtigungen wurden nicht bestätigt. Ohne sie fehlen Statistiken, Veröffentlichen oder Kommentare.',
        'account_in_other_workspace' => 'Dieser Account ist bereits in einem anderen Workspace verbunden.',
        'no_facebook_page' => 'Es wurde kein Instagram-Account gefunden, der mit einer Facebook-Seite verknüpft ist.',
        _ => 'Die Verbindung zu Instagram ist fehlgeschlagen. Bitte erneut versuchen.',
      });
    }
    return jsonOk({'account_id': row['account_id']});
  }

  // -------------------------------------------------------------------
  // Nischen
  // -------------------------------------------------------------------

  Future<Response> _niches(Request request) async {
    final auth = authOf(request);
    return jsonOk(await s.db.query('SELECT * FROM niches WHERE workspace_id = @w ORDER BY name', {'w': auth.workspaceId}));
  }

  Future<Response> _createNiche(Request request) async {
    final auth = authOf(request);
    final body = await readJson(request);
    final row = await s.db.one(
      '''INSERT INTO niches (workspace_id, name, keywords, language, region)
         VALUES (@w, @n, @k::jsonb, @l, @r) RETURNING *''',
      {
        'w': auth.workspaceId,
        'n': body.reqString('name', maxLength: 80),
        'k': jsonEncode(body.stringList('keywords')),
        'l': body.optString('language') ?? 'de',
        'r': body.optString('region') ?? 'DE',
      },
    );
    return jsonOk(row, status: 201);
  }

  Future<Response> _updateNiche(Request request, String id) async {
    final auth = authOf(request);
    final body = await readJson(request);
    final row = await s.db.one(
      '''UPDATE niches SET name = COALESCE(@n, name),
           keywords = COALESCE(@k::jsonb, keywords),
           language = COALESCE(@l, language), region = COALESCE(@r, region)
         WHERE id = @id AND workspace_id = @w RETURNING *''',
      {
        'id': id,
        'w': auth.workspaceId,
        'n': body.optString('name', maxLength: 80),
        'k': body.containsKey('keywords') ? jsonEncode(body.stringList('keywords')) : null,
        'l': body.optString('language'),
        'r': body.optString('region'),
      },
    );
    if (row == null) throw ApiError.notFound('Nische');
    return jsonOk(row);
  }

  Future<Response> _deleteNiche(Request request, String id) async {
    final auth = authOf(request);
    final row = await s.db.one('DELETE FROM niches WHERE id = @id AND workspace_id = @w RETURNING id', {
      'id': id,
      'w': auth.workspaceId,
    });
    if (row == null) throw ApiError.notFound('Nische');
    return jsonOk({'ok': true});
  }
}
