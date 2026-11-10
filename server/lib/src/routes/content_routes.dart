import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../http_utils.dart';
import '../security.dart';
import '../services/ai_service.dart';
import '../services/publish_service.dart';
import '../services/services.dart';
import '../services/sync_service.dart';
import '../storage.dart';

/// Trends, Ideen, Umsetzungsvorschläge, Kalender und Veröffentlichen.
class ContentRoutes {
  ContentRoutes(this.s, this.sync, this.publisher);

  final Services s;
  final SyncService sync;
  final PublishService publisher;

  static const _formats = {'reel', 'carousel', 'image', 'story'};
  static const _statuses = {'idea', 'in_progress', 'ready', 'published', 'discarded'};

  void addPrivate(Router r) {
    r.get('/api/trends', _trends);
    r.post('/api/trends', _createTrend);
    r.delete('/api/trends/<id>', _deleteTrend);
    r.post('/api/trends/<id>/adopt', _adoptTrend);
    r.get('/api/hashtags/<id>/posts', _hashtagPosts);
    r.post('/api/trend-sources', _createSource);
    r.delete('/api/trend-sources/<id>', _deleteSource);
    r.post('/api/trend-sources/<id>/refresh', _refreshSource);

    r.get('/api/ideas', _ideas);
    r.post('/api/ideas', _createIdea);
    r.patch('/api/ideas/<id>', _updateIdea);
    r.delete('/api/ideas/<id>', _deleteIdea);
    r.post('/api/ideas/<id>/attachments', _addAttachment);
    r.delete('/api/attachments/<id>', _deleteAttachment);
    r.post('/api/ideas/<id>/suggestions', _generateSuggestion);
    r.patch('/api/suggestions/<id>', _updateSuggestion);

    r.post('/api/uploads', _upload);
    r.get('/api/posts', _posts);
    r.post('/api/posts/validate', _validatePost);
    r.post('/api/posts', _createPost);
    r.get('/api/posts/<id>', _post);
    r.patch('/api/posts/<id>', _updatePost);
    r.delete('/api/posts/<id>', _deletePost);
    r.post('/api/posts/<id>/retry', _retryPost);
    r.get('/api/accounts/<id>/publish-limit', _publishLimit);
  }

  // -------------------------------------------------------------------
  // Trends (Spezifikation 4.4 und 7.4)
  // -------------------------------------------------------------------

  Future<Response> _trends(Request request) async {
    final auth = authOf(request);
    final rows = await s.db.query(
      '''SELECT t.*, ts.name AS source_name, ts.type AS source_type,
           COALESCE((SELECT json_agg(tn.niche_id) FROM trend_niches tn WHERE tn.trend_id = t.id), '[]'::json) AS niche_ids,
           u.name AS created_by_name
         FROM trends t JOIN trend_sources ts ON ts.id = t.source_id LEFT JOIN users u ON u.id = t.created_by
         WHERE ts.workspace_id = @w AND t.listed
         ORDER BY COALESCE(t.published_at, t.fetched_at) DESC LIMIT 300''',
      {'w': auth.workspaceId},
    );
    final sources = await s.db.query(
      'SELECT * FROM trend_sources WHERE workspace_id = @w ORDER BY type, name',
      {'w': auth.workspaceId},
    );
    return jsonOk({'trends': rows.map(rowJson).toList(), 'sources': sources.map(rowJson).toList()});
  }

  Future<String> _manualSource(String workspaceId) async {
    final existing = await s.db.one("SELECT id FROM trend_sources WHERE workspace_id = @w AND type = 'manual'", {'w': workspaceId});
    if (existing != null) return existing['id'] as String;
    final row = await s.db.one(
      "INSERT INTO trend_sources (workspace_id, type, name) VALUES (@w, 'manual', 'Eigene Beobachtung') RETURNING id",
      {'w': workspaceId},
    );
    return row!['id'] as String;
  }

  /// Manuell erfasste Beobachtung (immer möglich, Spezifikation 7.4).
  Future<Response> _createTrend(Request request) async {
    final auth = authOf(request);
    final body = await readJson(request);
    final nicheIds = body.stringList('niche_ids');
    final source = await _manualSource(auth.workspaceId);
    final row = await s.db.one(
      '''INSERT INTO trends (source_id, external_id, title, summary, reason, source_url, published_at, fetched_at, created_by)
         VALUES (@s, @ext, @t, @sum, @r, @url, @pub, @now, @u) RETURNING id''',
      {
        's': source,
        'ext': Security.randomToken(12),
        't': body.reqString('title', maxLength: 200),
        'sum': body.optString('summary', maxLength: 2000) ?? '',
        'r': body.reqString('reason', maxLength: 2000),
        'url': _url(body.optString('source_url', maxLength: 1000)),
        'pub': body.optDate('published_at') ?? s.now(),
        'now': s.now(),
        'u': auth.userId,
      },
    );
    for (final n in nicheIds) {
      final ok = await s.db.one('SELECT 1 FROM niches WHERE id = @n AND workspace_id = @w', {'n': n, 'w': auth.workspaceId});
      if (ok == null) throw ApiError.notFound('Nische');
      await s.db.exec('INSERT INTO trend_niches (trend_id, niche_id) VALUES (@t, @n)', {'t': row!['id'], 'n': n});
    }
    await s.db.exec('UPDATE trend_sources SET last_success_at = @now WHERE id = @s', {'s': source, 'now': s.now()});
    return jsonOk({'id': row!['id']}, status: 201);
  }

  static String? _url(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http')) || uri.host.isEmpty) {
      throw ApiError.badRequest('Bitte einen vollständigen Link angeben (https://…).');
    }
    return uri.toString();
  }

  Future<Response> _deleteTrend(Request request, String id) async {
    final auth = authOf(request);
    final row = await s.db.one(
      '''DELETE FROM trends t USING trend_sources ts
         WHERE t.id = @id AND ts.id = t.source_id AND ts.workspace_id = @w RETURNING t.id''',
      {'id': id, 'w': auth.workspaceId},
    );
    if (row == null) throw ApiError.notFound('Trend');
    return jsonOk({'ok': true});
  }

  /// „Als Trend übernehmen“ für einen aktuellen Hashtag-Beitrag.
  Future<Response> _adoptTrend(Request request, String id) async {
    final auth = authOf(request);
    final row = await s.db.one(
      '''UPDATE trends t SET listed = true FROM trend_sources ts
         WHERE t.id = @id AND ts.id = t.source_id AND ts.workspace_id = @w RETURNING t.id''',
      {'id': id, 'w': auth.workspaceId},
    );
    if (row == null) throw ApiError.notFound('Beitrag');
    return jsonOk({'ok': true});
  }

  /// Top- und aktuelle Beiträge eines beobachteten Hashtags.
  Future<Response> _hashtagPosts(Request request, String id) async {
    final auth = authOf(request);
    final watch = await s.db.one(
      '''SELECT h.hashtag FROM hashtag_watches h JOIN instagram_accounts a ON a.id = h.account_id
         WHERE h.id = @id AND a.workspace_id = @w''',
      {'id': id, 'w': auth.workspaceId},
    );
    if (watch == null) throw ApiError.notFound('Hashtag');
    final rows = await s.db.query(
      '''SELECT t.id, t.title, t.summary, t.reason, t.source_url, t.published_at, t.fetched_at, t.signal_value, t.signal_unit, t.listed
         FROM trends t JOIN trend_sources ts ON ts.id = t.source_id
         WHERE ts.workspace_id = @w AND ts.type = 'hashtag' AND t.external_id LIKE @p
         ORDER BY t.listed DESC, t.signal_value DESC NULLS LAST LIMIT 50''',
      {'w': auth.workspaceId, 'p': '${watch['hashtag']}:%'},
    );
    return jsonOk(rows.map(rowJson).toList());
  }

  /// RSS-Feed als Trendquelle einer Nische anlegen.
  Future<Response> _createSource(Request request) async {
    final auth = authOf(request);
    final body = await readJson(request);
    final nicheId = body.reqString('niche_id');
    final ok = await s.db.one('SELECT 1 FROM niches WHERE id = @n AND workspace_id = @w', {'n': nicheId, 'w': auth.workspaceId});
    if (ok == null) throw ApiError.notFound('Nische');
    final url = _url(body.reqString('url', maxLength: 1000))!;
    final row = await s.db.one(
      "INSERT INTO trend_sources (workspace_id, type, name, url, niche_id) VALUES (@w, 'rss', @n, @u, @niche) RETURNING id",
      {'w': auth.workspaceId, 'n': body.reqString('name', maxLength: 100), 'u': url, 'niche': nicheId},
    );
    await sync.refreshRssSource(row!['id'] as String);
    return jsonOk({'id': row['id']}, status: 201);
  }

  Future<Response> _deleteSource(Request request, String id) async {
    final auth = authOf(request);
    final row = await s.db.one(
      "DELETE FROM trend_sources WHERE id = @id AND workspace_id = @w AND type = 'rss' RETURNING id",
      {'id': id, 'w': auth.workspaceId},
    );
    if (row == null) throw ApiError.notFound('Quelle');
    return jsonOk({'ok': true});
  }

  Future<Response> _refreshSource(Request request, String id) async {
    final auth = authOf(request);
    final row = await s.db.one("SELECT id FROM trend_sources WHERE id = @id AND workspace_id = @w AND type = 'rss'", {
      'id': id,
      'w': auth.workspaceId,
    });
    if (row == null) throw ApiError.notFound('Quelle');
    await sync.refreshRssSource(id);
    return jsonOk({'ok': true});
  }

  // -------------------------------------------------------------------
  // Ideen (Spezifikation 4.5)
  // -------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> _loadIdeas(String workspaceId, [String? id]) async {
    final rows = await s.db.query(
      '''SELECT i.*, au.name AS assignee_name,
           t.title AS source_trend_title, sm.caption AS source_media_caption, pm.permalink AS published_permalink,
           COALESCE((SELECT json_agg(json_build_object('id', a.id, 'type', a.type, 'storage_key', a.storage_key, 'url', a.url) ORDER BY a.created_at)
                     FROM idea_attachments a WHERE a.idea_id = i.id), '[]'::json) AS attachments,
           COALESCE((SELECT json_agg(json_build_object('id', cs.id, 'version', cs.version, 'format', cs.format,
                       'format_reason', cs.format_reason, 'hooks', cs.hooks, 'outline', cs.outline, 'cta', cs.cta,
                       'caption_draft', cs.caption_draft, 'hashtags', cs.hashtags, 'model', cs.model,
                       'created_at', cs.created_at, 'is_selected', cs.is_selected) ORDER BY cs.version DESC)
                     FROM content_suggestions cs WHERE cs.idea_id = i.id), '[]'::json) AS suggestions
         FROM ideas i
           LEFT JOIN users au ON au.id = i.assignee_id
           LEFT JOIN trends t ON t.id = i.source_trend_id
           LEFT JOIN media sm ON sm.id = i.source_media_id
           LEFT JOIN media pm ON pm.id = i.published_media_id
         WHERE i.workspace_id = @w AND (@id::text IS NULL OR i.id::text = @id::text)
         ORDER BY i.updated_at DESC''',
      {'w': workspaceId, 'id': id},
    );
    final expires = s.now().add(const Duration(hours: 6));
    final result = <Map<String, dynamic>>[];
    for (final row in rows) {
      final json = rowJson(row);
      final attachments = <Map<String, dynamic>>[];
      for (final a in (row['attachments'] as List)) {
        final att = Map<String, dynamic>.from(a as Map);
        final key = att.remove('storage_key') as String?;
        // Dateien sind nur über zeitlich begrenzte, signierte Links abrufbar.
        if (key != null) att['url'] = await s.storage.signedUrl(key, expires);
        attachments.add(att);
      }
      json['attachments'] = attachments;
      result.add(json);
    }
    return result;
  }

  Future<Response> _ideas(Request request) async => jsonOk(await _loadIdeas(authOf(request).workspaceId));

  Future<void> _checkRefs(String workspaceId, Map<String, dynamic> body) async {
    Future<void> check(String key, String sql, String what) async {
      final value = body[key];
      if (value == null) return;
      if (await s.db.one(sql, {'id': value, 'w': workspaceId}) == null) throw ApiError.notFound(what);
    }

    await check('account_id', 'SELECT 1 FROM instagram_accounts WHERE id = @id AND workspace_id = @w', 'Account');
    await check('niche_id', 'SELECT 1 FROM niches WHERE id = @id AND workspace_id = @w', 'Nische');
    await check('assignee_id', 'SELECT 1 FROM memberships WHERE user_id = @id AND workspace_id = @w', 'Mitglied');
    await check(
      'source_trend_id',
      'SELECT 1 FROM trends t JOIN trend_sources ts ON ts.id = t.source_id WHERE t.id = @id AND ts.workspace_id = @w',
      'Trend',
    );
    await check(
      'source_media_id',
      'SELECT 1 FROM media m JOIN instagram_accounts a ON a.id = m.account_id WHERE m.id = @id AND a.workspace_id = @w',
      'Beitrag',
    );
  }

  Future<Response> _createIdea(Request request) async {
    final auth = authOf(request);
    final body = await readJson(request);
    final title = (body.optString('title', maxLength: 200) ?? '').trim();
    final note = (body.optString('note') ?? '').trim();
    if (title.isEmpty && note.isEmpty) throw ApiError.badRequest('Bitte Titel oder Notiz eingeben.');
    await _checkRefs(auth.workspaceId, body);
    final row = await s.db.one(
      '''INSERT INTO ideas (workspace_id, account_id, niche_id, title, note, format, status, tags, planned_for,
           assignee_id, source_trend_id, source_media_id, created_by)
         VALUES (@w, @a, @n, @t, @note, @f, 'idea', @tags::jsonb, @p, @as, @st, @sm, @u) RETURNING id''',
      {
        'w': auth.workspaceId,
        'a': body['account_id'],
        'n': body['niche_id'],
        // Ohne Titel dient der Anfang der Notiz als Titel.
        't': title.isNotEmpty ? title : (note.length > 60 ? '${note.substring(0, 57)}…' : note),
        'note': note,
        'f': body.oneOf('format', _formats),
        'tags': jsonEncode(body.stringList('tags')),
        'p': body.optDate('planned_for'),
        'as': body['assignee_id'],
        'st': body['source_trend_id'],
        'sm': body['source_media_id'],
        'u': auth.userId,
      },
    );
    return jsonOk((await _loadIdeas(auth.workspaceId, row!['id'] as String)).first, status: 201);
  }

  Future<Response> _updateIdea(Request request, String id) async {
    final auth = authOf(request);
    final body = await readJson(request);
    final existing = await s.db.one('SELECT * FROM ideas WHERE id = @id AND workspace_id = @w', {'id': id, 'w': auth.workspaceId});
    if (existing == null) throw ApiError.notFound('Idee');
    await _checkRefs(auth.workspaceId, body);
    // Nur übergebene Felder ändern; `null` löscht ein optionales Feld.
    T pick<T>(String key, T Function() parse) => body.containsKey(key) ? parse() : existing[key] as T;
    await s.db.exec(
      '''UPDATE ideas SET account_id = @a, niche_id = @n, title = @t, note = @note, format = @f, status = @s,
           tags = @tags::jsonb, planned_for = @p, assignee_id = @as, updated_at = @now
         WHERE id = @id''',
      {
        'id': id,
        'a': pick<String?>('account_id', () => body['account_id'] as String?),
        'n': pick<String?>('niche_id', () => body['niche_id'] as String?),
        't': pick<String>('title', () => body.reqString('title', maxLength: 200)),
        'note': pick<String>('note', () => body.optString('note') ?? ''),
        'f': pick<String?>('format', () => body.oneOf('format', _formats)),
        's': pick<String>('status', () => body.oneOf('status', _statuses) ?? 'idea'),
        'tags': body.containsKey('tags') ? jsonEncode(body.stringList('tags')) : jsonEncode(existing['tags']),
        'p': pick<DateTime?>('planned_for', () => body.optDate('planned_for')),
        'as': pick<String?>('assignee_id', () => body['assignee_id'] as String?),
        'now': s.now(),
      },
    );
    return jsonOk((await _loadIdeas(auth.workspaceId, id)).first);
  }

  Future<Response> _deleteIdea(Request request, String id) async {
    final auth = authOf(request);
    final keys = await s.db.query(
      '''SELECT a.storage_key FROM idea_attachments a JOIN ideas i ON i.id = a.idea_id
         WHERE i.id = @id AND i.workspace_id = @w AND a.storage_key IS NOT NULL''',
      {'id': id, 'w': auth.workspaceId},
    );
    final row = await s.db.one('DELETE FROM ideas WHERE id = @id AND workspace_id = @w RETURNING id', {'id': id, 'w': auth.workspaceId});
    if (row == null) throw ApiError.notFound('Idee');
    for (final k in keys) {
      await s.storage.delete(k['storage_key'] as String);
    }
    return jsonOk({'ok': true});
  }

  /// Anhang: Datei (Foto, Sprachnotiz) als Rohdaten mit Content-Type oder
  /// Link als JSON `{ "type": "link", "url": "…" }`.
  Future<Response> _addAttachment(Request request, String id) async {
    final auth = authOf(request);
    final idea = await s.db.one('SELECT id FROM ideas WHERE id = @id AND workspace_id = @w', {'id': id, 'w': auth.workspaceId});
    if (idea == null) throw ApiError.notFound('Idee');
    final mime = (request.headers['content-type'] ?? '').split(';').first.trim().toLowerCase();
    if (mime == 'application/json') {
      final body = await readJson(request);
      final url = _url(body.reqString('url', maxLength: 1000));
      await s.db.exec("INSERT INTO idea_attachments (idea_id, type, url) VALUES (@i, 'link', @u)", {'i': id, 'u': url});
    } else {
      final type = mime.startsWith('image/') ? 'image' : mime.startsWith('audio/') ? 'audio' : null;
      if (type == null || !MediaStorage.allowedTypes.containsKey(mime)) {
        throw ApiError.badRequest('Dieser Dateityp wird als Anhang nicht unterstützt.');
      }
      final key = await _store(request, mime, maxBytes: 25 * 1024 * 1024);
      await s.db.exec('INSERT INTO idea_attachments (idea_id, type, storage_key) VALUES (@i, @t, @k)', {'i': id, 't': type, 'k': key});
    }
    await s.db.exec('UPDATE ideas SET updated_at = @now WHERE id = @id', {'id': id, 'now': s.now()});
    return jsonOk((await _loadIdeas(auth.workspaceId, id)).first, status: 201);
  }

  Future<String> _store(Request request, String mime, {required int maxBytes}) async {
    final bytes = <int>[];
    await for (final chunk in request.read()) {
      bytes.addAll(chunk);
      if (bytes.length > maxBytes) throw ApiError(413, 'too_large', 'Die Datei ist zu groß.');
    }
    if (bytes.isEmpty) throw ApiError.badRequest('Die Datei ist leer.');
    return s.storage.save(bytes, mime);
  }

  Future<Response> _deleteAttachment(Request request, String id) async {
    final auth = authOf(request);
    final row = await s.db.one(
      '''DELETE FROM idea_attachments a USING ideas i
         WHERE a.id = @id AND i.id = a.idea_id AND i.workspace_id = @w RETURNING a.storage_key, a.idea_id''',
      {'id': id, 'w': auth.workspaceId},
    );
    if (row == null) throw ApiError.notFound('Anhang');
    if (row['storage_key'] != null) await s.storage.delete(row['storage_key'] as String);
    return jsonOk((await _loadIdeas(auth.workspaceId, row['idea_id'] as String)).first);
  }

  // -------------------------------------------------------------------
  // Umsetzungsvorschlag (KI)
  // -------------------------------------------------------------------

  static const _parts = {'format', 'hooks', 'outline', 'cta', 'caption', 'hashtags'};

  Future<Response> _generateSuggestion(Request request, String id) async {
    final auth = authOf(request);
    final body = await readJson(request);
    final part = body.oneOf('part', _parts);
    if (!s.config.aiConfigured) throw ApiError.notConfigured('Der KI-Zugang für Umsetzungsvorschläge');
    final idea = await s.db.one('SELECT * FROM ideas WHERE id = @id AND workspace_id = @w', {'id': id, 'w': auth.workspaceId});
    if (idea == null) throw ApiError.notFound('Idee');
    final previous = await s.db.one(
      'SELECT * FROM content_suggestions WHERE idea_id = @i ORDER BY is_selected DESC, version DESC LIMIT 1',
      {'i': id},
    );
    if (part != null && previous == null) throw ApiError.badRequest('Es gibt noch keinen Vorschlag, der angepasst werden könnte.');

    // Kontext laut Spezifikation 4.5: Idee, Nische, Account-Profil,
    // verknüpfter Trend und die 5 besten eigenen Beiträge.
    final account = idea['account_id'] == null
        ? null
        : await s.db.one('SELECT username, tone, audience_note, language FROM instagram_accounts WHERE id = @a', {'a': idea['account_id']});
    final niche = idea['niche_id'] == null
        ? null
        : await s.db.one('SELECT name, keywords, language, region FROM niches WHERE id = @n', {'n': idea['niche_id']});
    final trend = idea['source_trend_id'] == null
        ? null
        : await s.db.one(
            '''SELECT t.title, t.summary, t.reason, t.source_url, t.published_at, ts.name AS source
               FROM trends t JOIN trend_sources ts ON ts.id = t.source_id WHERE t.id = @t''',
            {'t': idea['source_trend_id']},
          );
    final top = idea['account_id'] == null
        ? <Map<String, dynamic>>[]
        : await s.db.query(
            '''SELECT m.caption, m.media_type, m.media_product_type, mm.value AS reach
               FROM media m JOIN media_metrics mm ON mm.media_id = m.id AND mm.metric = 'reach'
               WHERE m.account_id = @a AND m.media_product_type <> 'story' AND mm.value IS NOT NULL
               ORDER BY mm.value DESC LIMIT 5''',
            {'a': idea['account_id']},
          );
    final context = {
      'idee': {
        'titel': idea['title'],
        'notiz': idea['note'],
        'wunschformat': idea['format'],
        'tags': idea['tags'],
      },
      'nische': niche,
      'account': account,
      'verknuepfter_trend': trend == null ? null : rowJson(trend),
      'beste_eigene_beitraege': top,
      if (part != null)
        'bisheriger_vorschlag': {
          'format': previous!['format'],
          'format_reason': previous['format_reason'],
          'hooks': previous['hooks'],
          'outline': previous['outline'],
          'cta': previous['cta'],
          'caption_draft': previous['caption_draft'],
          'hashtags': previous['hashtags'],
        },
    };

    final GeneratedSuggestion generated;
    try {
      generated = await s.ai.generate(context, part: part);
    } on AiException catch (e) {
      throw ApiError(502, 'ai_error', e.message);
    } on TimeoutException {
      throw ApiError(504, 'ai_timeout', 'Der KI-Dienst antwortet nicht rechtzeitig. Bitte erneut versuchen.');
    }

    // Beim Neu-Erzeugen eines Teils bleibt der Rest des Vorschlags unverändert.
    bool keep(String p) => part != null && part != p;
    final values = {
      'format': keep('format') ? previous!['format'] : generated.format,
      'reason': keep('format') ? previous!['format_reason'] : generated.formatReason,
      'hooks': jsonEncode(keep('hooks') ? previous!['hooks'] : generated.hooks),
      'outline': jsonEncode(keep('outline') ? previous!['outline'] : generated.outline),
      'cta': keep('cta') ? previous!['cta'] : generated.cta,
      'caption': keep('caption') ? previous!['caption_draft'] : generated.captionDraft,
      'hashtags': jsonEncode(keep('hashtags') ? previous!['hashtags'] : generated.hashtags),
    };
    await s.db.tx((db) async {
      final max = await db.one('SELECT COALESCE(max(version), 0)::int AS v FROM content_suggestions WHERE idea_id = @i', {'i': id});
      await db.exec('UPDATE content_suggestions SET is_selected = false WHERE idea_id = @i', {'i': id});
      await db.exec(
        '''INSERT INTO content_suggestions (idea_id, version, format, format_reason, hooks, outline, cta, caption_draft,
             hashtags, model, prompt_context_hash, created_by, is_selected)
           VALUES (@i, @v, @format, @reason, @hooks::jsonb, @outline::jsonb, @cta, @caption, @hashtags::jsonb,
             @model, @hash, @u, true)''',
        {
          ...values,
          'i': id,
          'v': (max!['v'] as int) + 1,
          'model': generated.model,
          'hash': await Security.sha256Hex(jsonEncode(context, toEncodable: (o) => o.toString())),
          'u': auth.userId,
        },
      );
      await db.exec(
        "UPDATE ideas SET updated_at = @now, status = CASE WHEN status = 'idea' THEN 'in_progress' ELSE status END WHERE id = @i",
        {'i': id, 'now': s.now()},
      );
    });
    return jsonOk((await _loadIdeas(auth.workspaceId, id)).first, status: 201);
  }

  /// Vorschlag von Hand bearbeiten oder eine ältere Version auswählen.
  Future<Response> _updateSuggestion(Request request, String id) async {
    final auth = authOf(request);
    final body = await readJson(request);
    final existing = await s.db.one(
      '''SELECT cs.* FROM content_suggestions cs JOIN ideas i ON i.id = cs.idea_id
         WHERE cs.id = @id AND i.workspace_id = @w''',
      {'id': id, 'w': auth.workspaceId},
    );
    if (existing == null) throw ApiError.notFound('Vorschlag');
    final ideaId = existing['idea_id'] as String;
    await s.db.tx((db) async {
      if (body['is_selected'] == true) {
        await db.exec('UPDATE content_suggestions SET is_selected = (id = @id) WHERE idea_id = @i', {'id': id, 'i': ideaId});
      }
      await db.exec(
        '''UPDATE content_suggestions SET format = @format, format_reason = @reason, hooks = @hooks::jsonb,
             outline = @outline::jsonb, cta = @cta, caption_draft = @caption, hashtags = @hashtags::jsonb
           WHERE id = @id''',
        {
          'id': id,
          'format': body.containsKey('format') ? body.oneOf('format', _formats) : existing['format'],
          'reason': body.optString('format_reason') ?? existing['format_reason'],
          'hooks': jsonEncode(body.containsKey('hooks') ? body.stringList('hooks') : existing['hooks']),
          'outline': jsonEncode(body.containsKey('outline') ? body.stringList('outline') : existing['outline']),
          'cta': body.optString('cta') ?? existing['cta'],
          'caption': body.optString('caption_draft') ?? existing['caption_draft'],
          'hashtags': jsonEncode(body.containsKey('hashtags') ? body.stringList('hashtags').take(5).toList() : existing['hashtags']),
        },
      );
      await db.exec('UPDATE ideas SET updated_at = @now WHERE id = @i', {'i': ideaId, 'now': s.now()});
    });
    return jsonOk((await _loadIdeas(auth.workspaceId, ideaId)).first);
  }

  // -------------------------------------------------------------------
  // Kalender und Veröffentlichen (Spezifikation 4.6)
  // -------------------------------------------------------------------

  /// Lädt ein Medium (Bild oder Video) für einen Beitrag hoch.
  Future<Response> _upload(Request request) async {
    authOf(request);
    final mime = (request.headers['content-type'] ?? '').split(';').first.trim().toLowerCase();
    if (!(mime.startsWith('image/') || mime.startsWith('video/')) || !MediaStorage.allowedTypes.containsKey(mime)) {
      throw ApiError.badRequest('Erlaubt sind Bilder (JPEG, PNG, WebP, HEIC) und Videos (MP4, MOV).');
    }
    final key = await _store(request, mime, maxBytes: MediaStorage.maxBytes);
    return jsonOk({'key': key, 'mime_type': mime}, status: 201);
  }

  static const _postSelect = '''
    SELECT p.*, i.title AS idea_title,
      COALESCE((SELECT json_agg(json_build_object('position', pm.position, 'mime_type', pm.mime_type) ORDER BY pm.position)
                FROM scheduled_post_media pm WHERE pm.scheduled_post_id = p.id), '[]'::json) AS media
    FROM scheduled_posts p JOIN instagram_accounts a ON a.id = p.account_id LEFT JOIN ideas i ON i.id = p.idea_id''';

  Future<Response> _posts(Request request) async {
    final auth = authOf(request);
    final rows = await s.db.query('$_postSelect WHERE a.workspace_id = @w ORDER BY p.scheduled_for', {'w': auth.workspaceId});
    return jsonOk(rows.map(rowJson).toList());
  }

  Future<Map<String, dynamic>> _loadPost(String id, String workspaceId) async {
    final row = await s.db.one('$_postSelect WHERE p.id = @id AND a.workspace_id = @w', {'id': id, 'w': workspaceId});
    if (row == null) throw ApiError.notFound('Kalendereintrag');
    return row;
  }

  Future<Response> _post(Request request, String id) async =>
      jsonOk(rowJson(await _loadPost(id, authOf(request).workspaceId)));

  List<Map<String, dynamic>> _mediaOf(Map<String, dynamic> body) {
    final media = body['media'];
    if (media == null) return [];
    if (media is! List) throw ApiError.badRequest('Feld „media“ muss eine Liste sein.');
    return [for (final m in media) Map<String, dynamic>.from(m as Map)];
  }

  /// Vorab-Prüfung von Format und Limit, ohne etwas anzulegen.
  Future<Response> _validatePost(Request request) async {
    final auth = authOf(request);
    final body = await readJson(request);
    final accountId = body.reqString('account_id');
    await s.accountInWorkspace(accountId, auth.workspaceId);
    final format = body.oneOf('format', {'post', 'reel', 'carousel'}) ?? 'post';
    final problems = PublishService.validate(format, [for (final m in _mediaOf(body)) m['mime_type'].toString()]);
    return jsonOk({'problems': problems, 'limit': await publisher.limit(accountId)});
  }

  Future<Response> _createPost(Request request) async {
    final auth = authOf(request);
    final body = await readJson(request);
    final accountId = body.reqString('account_id');
    final account = await s.accountInWorkspace(accountId, auth.workspaceId);
    final format = body.oneOf('format', {'post', 'reel', 'carousel'}) ?? 'post';
    final planOnly = body['plan_only'] == true;
    final now = body['publish_now'] == true;
    final media = _mediaOf(body);
    final when = now ? s.now() : body.optDate('scheduled_for');
    if (when == null) throw ApiError.badRequest('Bitte einen Termin wählen.');
    if (!now && !planOnly && when.isBefore(s.now().subtract(const Duration(minutes: 1)))) {
      throw ApiError.badRequest('Der Termin liegt in der Vergangenheit.');
    }
    if (body['idea_id'] != null) {
      final idea = await s.db.one('SELECT 1 FROM ideas WHERE id = @i AND workspace_id = @w', {'i': body['idea_id'], 'w': auth.workspaceId});
      if (idea == null) throw ApiError.notFound('Idee');
    }
    if (!planOnly) {
      // Veröffentlichen braucht einen verbundenen Account und gültige Medien.
      if (account['account_type'] == 'manual' || account['connection_status'] == 'disconnected') {
        throw ApiError(409, 'no_connection', 'Dieser Account ist nicht mit Instagram verbunden. Der Termin kann nur als reine Planung gespeichert werden.');
      }
      final problems = PublishService.validate(format, [for (final m in media) m['mime_type'].toString()]);
      if (problems.isNotEmpty) throw ApiError(400, 'invalid_media', problems.join(' '));
      for (final m in media) {
        if (s.storage.file(m['key'].toString()) == null) throw ApiError.badRequest('Ein hochgeladenes Medium fehlt. Bitte erneut auswählen.');
      }
    }
    final id = await s.db.tx((db) async {
      final row = await db.one(
        '''INSERT INTO scheduled_posts (account_id, idea_id, suggestion_id, format, caption, scheduled_for, status, created_by)
           VALUES (@a, @i, @sg, @f, @c, @when, @status, @u) RETURNING id''',
        {
          'a': accountId,
          'i': body['idea_id'],
          'sg': body['suggestion_id'],
          'f': format,
          'c': body.optString('caption', maxLength: 2200) ?? '',
          'when': when,
          'status': planOnly ? 'draft' : 'scheduled',
          'u': auth.userId,
        },
      );
      if (!planOnly) {
        for (var i = 0; i < media.length; i++) {
          await db.exec(
            'INSERT INTO scheduled_post_media (scheduled_post_id, position, storage_key, mime_type) VALUES (@p, @pos, @k, @m)',
            {'p': row!['id'], 'pos': i, 'k': media[i]['key'].toString(), 'm': media[i]['mime_type'].toString()},
          );
        }
      }
      return row!['id'] as String;
    });
    await s.audit(auth.workspaceId, auth.userId, now ? 'post_publish_now' : 'post_scheduled', id);
    // „Jetzt“ läuft im Hintergrund (Reels brauchen Verarbeitungszeit); die
    // App fragt den Status ab.
    if (now) unawaited(publisher.publish(id));
    return jsonOk(rowJson(await _loadPost(id, auth.workspaceId)), status: 201);
  }

  /// Termin verschieben (Ziehen im Kalender) oder Caption ändern.
  Future<Response> _updatePost(Request request, String id) async {
    final auth = authOf(request);
    final body = await readJson(request);
    final post = await _loadPost(id, auth.workspaceId);
    if (!const {'draft', 'scheduled', 'failed'}.contains(post['status'])) {
      throw ApiError(409, 'not_editable', 'Dieser Eintrag kann nicht mehr geändert werden.');
    }
    await s.db.exec(
      'UPDATE scheduled_posts SET scheduled_for = COALESCE(@when, scheduled_for), caption = COALESCE(@c, caption) WHERE id = @id',
      {'id': id, 'when': body.optDate('scheduled_for'), 'c': body.optString('caption', maxLength: 2200)},
    );
    return jsonOk(rowJson(await _loadPost(id, auth.workspaceId)));
  }

  Future<Response> _deletePost(Request request, String id) async {
    final auth = authOf(request);
    final post = await _loadPost(id, auth.workspaceId);
    if (post['status'] == 'publishing') throw ApiError(409, 'not_editable', 'Dieser Eintrag wird gerade veröffentlicht.');
    final media = await s.db.query('SELECT storage_key FROM scheduled_post_media WHERE scheduled_post_id = @p', {'p': id});
    await s.db.exec('DELETE FROM scheduled_posts WHERE id = @id', {'id': id});
    for (final m in media) {
      await s.storage.delete(m['storage_key'] as String);
    }
    return jsonOk({'ok': true});
  }

  Future<Response> _retryPost(Request request, String id) async {
    final auth = authOf(request);
    final post = await _loadPost(id, auth.workspaceId);
    if (post['status'] != 'failed') throw ApiError(409, 'not_failed', 'Nur fehlgeschlagene Einträge können wiederholt werden.');
    unawaited(publisher.publish(id));
    return jsonOk({'ok': true});
  }

  Future<Response> _publishLimit(Request request, String id) async {
    final auth = authOf(request);
    await s.accountInWorkspace(id, auth.workspaceId);
    return jsonOk(await publisher.limit(id));
  }
}
