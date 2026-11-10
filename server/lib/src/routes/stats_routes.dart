import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../config.dart';
import '../http_utils.dart';
import '../instagram/instagram_api.dart';
import '../services/services.dart';
import '../services/sync_service.dart';

/// Statistiken, Beiträge, Stories, Kommentare, Wettbewerber, Hashtags.
class StatsRoutes {
  StatsRoutes(this.s, this.sync);

  final Services s;
  final SyncService sync;

  static const _sumMetrics = [
    'reach', 'views', 'total_interactions', 'likes', 'comments', 'shares', 'saves', 'follows', 'unfollows',
  ];

  void addPrivate(Router r) {
    r.get('/api/stats/overview', _overview);
    r.get('/api/accounts/<id>/stats', _accountStats);
    r.get('/api/accounts/<id>/media', _mediaList);
    r.get('/api/accounts/<id>/stories', _stories);
    r.get('/api/media/<id>', _mediaDetail);
    r.get('/api/comments', _comments);
    r.post('/api/comments/<id>/reply', _reply);
    r.post('/api/comments/<id>/hide', _hide);
    r.get('/api/accounts/<id>/competitors', _competitors);
    r.post('/api/accounts/<id>/competitors', _addCompetitor);
    r.delete('/api/competitors/<id>', _removeCompetitor);
    r.get('/api/accounts/<id>/hashtags', _hashtags);
    r.post('/api/accounts/<id>/hashtags', _addHashtag);
    r.delete('/api/hashtags/<id>', _removeHashtag);
  }

  int _days(Request request) {
    final days = int.tryParse(request.url.queryParameters['days'] ?? '7') ?? 7;
    return const [7, 28, 90].contains(days) ? days : 7;
  }

  DateTime get _today {
    final n = s.now();
    return DateTime.utc(n.year, n.month, n.day);
  }

  /// Summen je Kennzahl für einen Zeitraum. Fehlt eine Kennzahl ganz,
  /// taucht sie nicht auf (die App zeigt dann „keine Daten“ statt 0).
  Future<Map<String, int>> _totals(String accountId, DateTime from, DateTime to) async {
    final rows = await s.db.query(
      '''SELECT metric, sum(value)::bigint AS total FROM account_daily_metrics
         WHERE account_id = @a AND date >= @from AND date < @to AND value IS NOT NULL
         GROUP BY metric''',
      {'a': accountId, 'from': from, 'to': to},
    );
    return {for (final r in rows) r['metric'] as String: (r['total'] as num).toInt()};
  }

  Future<Map<String, dynamic>> _summary(Map<String, dynamic> account, int days) async {
    final id = account['id'] as String;
    final to = _today;
    final from = to.subtract(Duration(days: days));
    final prevFrom = from.subtract(Duration(days: days));
    final current = await _totals(id, from, to);
    final previous = await _totals(id, prevFrom, from);
    final followers = await s.db.query(
      'SELECT date, followers_count FROM follower_snapshots WHERE account_id = @a AND date >= @from ORDER BY date',
      {'a': id, 'from': from},
    );
    int? followerDelta;
    if (followers.length >= 2) {
      followerDelta = (followers.last['followers_count'] as int) - (followers.first['followers_count'] as int);
    }
    final fetched = await s.db.one('SELECT max(fetched_at) AS t FROM account_daily_metrics WHERE account_id = @a', {'a': id});
    return {
      'account_id': id,
      'days': days,
      'totals': {for (final m in _sumMetrics) m: current[m]},
      'previous': {for (final m in _sumMetrics) m: previous[m]},
      'followers_count': account['followers_count'],
      'follower_delta': followerDelta,
      'follower_series': [
        for (final f in followers) {'date': (f['date'] as DateTime).toIso8601String(), 'value': f['followers_count']},
      ],
      'fetched_at': (fetched?['t'] as DateTime?)?.toIso8601String() ?? (account['last_synced_at'] as DateTime?)?.toIso8601String(),
      'missing': _missingReasons(account, current),
    };
  }

  /// Begründungen, warum Werte fehlen (Spezifikation 3 und 4.3).
  List<Map<String, String>> _missingReasons(Map<String, dynamic> account, Map<String, int> totals) {
    final reasons = <Map<String, String>>[];
    final followers = account['followers_count'] as int?;
    if (account['account_type'] == 'manual') {
      reasons.add({'code': 'manual', 'text': 'Manuell geführter Account: Instagram liefert dafür keine Statistiken.'});
      return reasons;
    }
    if (account['connection_status'] == 'disconnected') {
      reasons.add({'code': 'disconnected', 'text': 'Die Verbindung ist getrennt. Neu verbinden, um aktuelle Daten zu laden.'});
    }
    if (account['last_synced_at'] == null) {
      reasons.add({'code': 'not_synced', 'text': 'Daten wurden noch nicht synchronisiert.'});
    } else if (totals.isEmpty) {
      reasons.add({
        'code': 'no_data',
        'text': 'Instagram hat für diesen Zeitraum keine Werte geliefert (fehlende Berechtigung oder noch keine Daten; Insights sind bis zu 48 Stunden verzögert).',
      });
    }
    if (followers != null && followers < 100) {
      reasons.add({'code': 'under_100', 'text': 'Follows, Unfollows und Demografie gibt es erst ab 100 Followern.'});
    }
    if (account['last_sync_error'] != null) {
      reasons.add({'code': 'sync_error', 'text': 'Letzter Abruf fehlgeschlagen: ${account['last_sync_error']}'});
    }
    return reasons;
  }

  /// Vergleich aller Accounts nebeneinander (Heute-Seite und „Alle Accounts“).
  Future<Response> _overview(Request request) async {
    final auth = authOf(request);
    final days = _days(request);
    final accounts = await s.db.query('SELECT * FROM instagram_accounts WHERE workspace_id = @w ORDER BY created_at', {
      'w': auth.workspaceId,
    });
    final summaries = [for (final a in accounts) await _summary(a, days)];
    // Auffälligster Beitrag der Woche: höchste Reichweite im Verhältnis zum
    // Median des jeweiligen Accounts.
    final standout = await s.db.one(
      '''WITH med AS (
           SELECT m.account_id, percentile_cont(0.5) WITHIN GROUP (ORDER BY mm.value) AS median
           FROM media m JOIN media_metrics mm ON mm.media_id = m.id AND mm.metric = 'reach'
           WHERE m.media_product_type <> 'story' AND mm.value IS NOT NULL GROUP BY m.account_id)
         SELECT m.id, m.account_id, m.caption, m.thumbnail_url, m.permalink, m.media_product_type, m.posted_at,
                mm.value AS reach, med.median
         FROM media m
           JOIN instagram_accounts a ON a.id = m.account_id
           JOIN media_metrics mm ON mm.media_id = m.id AND mm.metric = 'reach'
           JOIN med ON med.account_id = m.account_id
         WHERE a.workspace_id = @w AND m.media_product_type <> 'story' AND m.posted_at > @since
           AND mm.value IS NOT NULL AND med.median > 0
         ORDER BY mm.value / med.median DESC LIMIT 1''',
      {'w': auth.workspaceId, 'since': s.now().subtract(const Duration(days: 7))},
    );
    final unanswered = await s.db.query(
      '''SELECT m.account_id, count(*)::int AS n FROM comments c
           JOIN media m ON m.id = c.media_id JOIN instagram_accounts a ON a.id = m.account_id
         WHERE a.workspace_id = @w AND c.parent_comment_id IS NULL AND NOT c.is_own
           AND c.replied_at IS NULL AND NOT c.is_hidden
         GROUP BY m.account_id''',
      {'w': auth.workspaceId},
    );
    return jsonOk({
      'days': days,
      'accounts': summaries,
      'standout': standout == null ? null : rowJson(standout),
      'unanswered_comments': {for (final u in unanswered) u['account_id'] as String: u['n']},
    });
  }

  Future<Response> _accountStats(Request request, String id) async {
    final auth = authOf(request);
    final account = await s.accountInWorkspace(id, auth.workspaceId);
    final days = _days(request);
    final summary = await _summary(account, days);
    final from = _today.subtract(Duration(days: days));
    final rows = await s.db.query(
      '''SELECT date, metric, value FROM account_daily_metrics
         WHERE account_id = @a AND date >= @from AND metric IN ('reach','views','total_interactions')
         ORDER BY date''',
      {'a': id, 'from': from},
    );
    final series = <String, List<Map<String, dynamic>>>{'reach': [], 'views': [], 'total_interactions': []};
    for (final r in rows) {
      series[r['metric'] as String]!.add({'date': (r['date'] as DateTime).toIso8601String(), 'value': r['value']});
    }
    return jsonOk({...summary, 'series': series});
  }

  static const _mediaSelect = '''
    SELECT m.*, COALESCE((SELECT json_object_agg(mm.metric, mm.value) FROM media_metrics mm WHERE mm.media_id = m.id), '{}'::json) AS metrics,
           (SELECT max(mm.fetched_at) FROM media_metrics mm WHERE mm.media_id = m.id) AS fetched_at
    FROM media m''';

  Future<Response> _mediaList(Request request, String id) async {
    final auth = authOf(request);
    await s.accountInWorkspace(id, auth.workspaceId);
    final days = _days(request);
    final rows = await s.db.query(
      '''$_mediaSelect WHERE m.account_id = @a AND m.media_product_type <> 'story' AND m.posted_at >= @from
         ORDER BY m.posted_at DESC LIMIT 200''',
      {'a': id, 'from': s.now().subtract(Duration(days: days))},
    );
    return jsonOk(rows.map(rowJson).toList());
  }

  /// Gesicherte Story-Werte mit Uhrzeit der letzten Sicherung (4.7).
  Future<Response> _stories(Request request, String id) async {
    final auth = authOf(request);
    await s.accountInWorkspace(id, auth.workspaceId);
    final rows = await s.db.query(
      '''SELECT m.id, m.thumbnail_url, m.permalink, m.posted_at, m.media_type,
           (SELECT max(captured_at) FROM story_metric_snapshots ss WHERE ss.media_id = m.id) AS last_captured_at,
           (SELECT count(DISTINCT captured_at)::int FROM story_metric_snapshots ss WHERE ss.media_id = m.id) AS snapshot_count,
           COALESCE((SELECT json_object_agg(mm.metric, mm.value) FROM media_metrics mm WHERE mm.media_id = m.id), '{}'::json) AS metrics
         FROM media m WHERE m.account_id = @a AND m.media_product_type = 'story'
         ORDER BY m.posted_at DESC LIMIT 100''',
      {'a': id},
    );
    final now = s.now();
    return jsonOk([
      for (final r in rows)
        {
          ...rowJson(r),
          'is_live': r['posted_at'] != null && now.difference(r['posted_at'] as DateTime) < const Duration(hours: 24),
          // Nicht rechtzeitig gesichert: abgelaufen, aber letzte Sicherung
          // fehlt oder liegt mehr als 5 Stunden vor dem Ablauf.
          'saved_in_time': r['posted_at'] == null ||
              now.difference(r['posted_at'] as DateTime) < const Duration(hours: 24) ||
              (r['last_captured_at'] != null &&
                  (r['posted_at'] as DateTime).add(const Duration(hours: 24)).difference(r['last_captured_at'] as DateTime) <=
                      const Duration(hours: 5)),
        },
    ]);
  }

  Future<Response> _mediaDetail(Request request, String id) async {
    final auth = authOf(request);
    final row = await s.db.one(
      '''$_mediaSelect JOIN instagram_accounts a ON a.id = m.account_id
         WHERE m.id = @id AND a.workspace_id = @w''',
      {'id': id, 'w': auth.workspaceId},
    );
    if (row == null) throw ApiError.notFound('Beitrag');
    final medians = await s.db.query(
      '''SELECT mm.metric, percentile_cont(0.5) WITHIN GROUP (ORDER BY mm.value) AS median, count(*)::int AS n
         FROM media m JOIN media_metrics mm ON mm.media_id = m.id
         WHERE m.account_id = @a AND m.media_product_type <> 'story' AND mm.value IS NOT NULL
         GROUP BY mm.metric''',
      {'a': row['account_id']},
    );
    final comments = await s.db.query(
      'SELECT * FROM comments WHERE media_id = @m ORDER BY created_at DESC LIMIT 100',
      {'m': id},
    );
    final snapshots = await s.db.query(
      'SELECT captured_at, metric, value FROM story_metric_snapshots WHERE media_id = @m ORDER BY captured_at',
      {'m': id},
    );
    return jsonOk({
      ...rowJson(row),
      'medians': {for (final m in medians) m['metric'] as String: m['median']},
      'median_sample': medians.isEmpty ? 0 : medians.map((m) => m['n'] as int).reduce((a, b) => a > b ? a : b),
      'comments': comments.map(rowJson).toList(),
      'story_snapshots': snapshots.map(rowJson).toList(),
    });
  }

  // -------------------------------------------------------------------
  // Kommentare (Spezifikation 4.8)
  // -------------------------------------------------------------------

  Future<Response> _comments(Request request) async {
    final auth = authOf(request);
    final q = request.url.queryParameters;
    final rows = await s.db.query(
      '''SELECT c.*, m.account_id, m.caption AS media_caption, m.thumbnail_url AS media_thumbnail, m.permalink AS media_permalink,
           COALESCE((SELECT json_agg(json_build_object('id', r.id, 'author_username', r.author_username, 'text', r.text,
                       'created_at', r.created_at, 'is_own', r.is_own) ORDER BY r.created_at)
                     FROM comments r WHERE r.parent_comment_id = c.ig_comment_id), '[]'::json) AS replies
         FROM comments c JOIN media m ON m.id = c.media_id JOIN instagram_accounts a ON a.id = m.account_id
         WHERE a.workspace_id = @w AND c.parent_comment_id IS NULL AND NOT c.is_own
           AND (@acc::text IS NULL OR m.account_id::text = @acc::text)
           AND (@only::boolean IS NOT TRUE OR (c.replied_at IS NULL AND NOT c.is_hidden))
         ORDER BY c.created_at DESC LIMIT 200''',
      {'w': auth.workspaceId, 'acc': q['account_id'], 'only': q['filter'] == 'unanswered'},
    );
    return jsonOk(rows.map(rowJson).toList());
  }

  Future<Map<String, dynamic>> _comment(String id, String workspaceId) async {
    final row = await s.db.one(
      '''SELECT c.*, m.account_id FROM comments c JOIN media m ON m.id = c.media_id
           JOIN instagram_accounts a ON a.id = m.account_id
         WHERE c.id = @id AND a.workspace_id = @w''',
      {'id': id, 'w': workspaceId},
    );
    if (row == null) throw ApiError.notFound('Kommentar');
    return row;
  }

  /// Antwort wird immer von einer Person ausgelöst, nie automatisch.
  Future<Response> _reply(Request request, String id) async {
    final auth = authOf(request);
    final body = await readJson(request);
    final message = body.reqString('message', maxLength: 2200);
    final comment = await _comment(id, auth.workspaceId);
    try {
      final access = await s.access(comment['account_id'] as String);
      final replyId = await s.instagram.replyToComment(access, comment['ig_comment_id'] as String, message);
      final account = await s.db.one('SELECT username FROM instagram_accounts WHERE id = @a', {'a': comment['account_id']});
      await s.db.exec(
        '''INSERT INTO comments (media_id, ig_comment_id, parent_comment_id, author_username, text, created_at, is_own, fetched_at)
           VALUES (@m, @id, @p, @u, @t, @now, true, @now) ON CONFLICT (ig_comment_id) DO NOTHING''',
        {
          'm': comment['media_id'],
          'id': replyId,
          'p': comment['ig_comment_id'],
          'u': account?['username'] ?? '',
          't': message,
          'now': s.now(),
        },
      );
      await s.db.exec('UPDATE comments SET replied_by_user_id = @u, replied_at = @now WHERE id = @id', {
        'id': id,
        'u': auth.userId,
        'now': s.now(),
      });
      await s.audit(auth.workspaceId, auth.userId, 'comment_replied', id);
    } on InstagramApiException catch (e) {
      throw s.instagramError(e);
    }
    return jsonOk({'ok': true});
  }

  Future<Response> _hide(Request request, String id) async {
    final auth = authOf(request);
    final body = await readJson(request);
    final hide = body['hide'] != false;
    final comment = await _comment(id, auth.workspaceId);
    try {
      final access = await s.access(comment['account_id'] as String);
      await s.instagram.hideComment(access, comment['ig_comment_id'] as String, hide);
      await s.db.exec('UPDATE comments SET is_hidden = @h WHERE id = @id', {'id': id, 'h': hide});
      await s.audit(auth.workspaceId, auth.userId, hide ? 'comment_hidden' : 'comment_unhidden', id);
    } on InstagramApiException catch (e) {
      throw s.instagramError(e);
    }
    return jsonOk({'ok': true});
  }

  // -------------------------------------------------------------------
  // Wettbewerber (Spezifikation 4.9)
  // -------------------------------------------------------------------

  Future<Response> _competitors(Request request, String id) async {
    final auth = authOf(request);
    await s.accountInWorkspace(id, auth.workspaceId);
    final rows = await s.db.query(
      '''SELECT c.id, c.username, c.last_error,
           COALESCE((SELECT json_agg(json_build_object('date', cs.date, 'followers_count', cs.followers_count,
                       'media_count', cs.media_count, 'avg_likes', cs.avg_likes, 'avg_comments', cs.avg_comments,
                       'fetched_at', cs.fetched_at) ORDER BY cs.date)
                     FROM competitor_snapshots cs WHERE cs.competitor_id = c.id AND cs.date > @from), '[]'::json) AS snapshots
         FROM competitor_accounts c WHERE c.account_id = @a ORDER BY c.username''',
      {'a': id, 'from': _today.subtract(const Duration(days: 90))},
    );
    return jsonOk({'max': AppLimits.maxCompetitorsPerAccount, 'items': rows});
  }

  Future<Response> _addCompetitor(Request request, String id) async {
    final auth = authOf(request);
    final body = await readJson(request);
    await s.accountInWorkspace(id, auth.workspaceId);
    final username = body.reqString('username', maxLength: 60).replaceFirst('@', '').toLowerCase();
    if (!RegExp(r'^[a-z0-9._]+$').hasMatch(username)) throw ApiError.badRequest('Ungültiger Benutzername.');
    final access = await s.facebookAccess(id);
    final count = await s.db.one('SELECT count(*)::int AS n FROM competitor_accounts WHERE account_id = @a', {'a': id});
    if ((count!['n'] as int) >= AppLimits.maxCompetitorsPerAccount) {
      throw ApiError(409, 'competitor_limit', 'Je Account sind höchstens ${AppLimits.maxCompetitorsPerAccount} Wettbewerber möglich.');
    }
    try {
      // Prüft, ob der Account existiert und professionell ist.
      await s.instagram.businessDiscovery(access, username);
    } on InstagramApiException catch (e) {
      if (e.isAuthError || e.isPermissionError || e.isLimitError) throw s.instagramError(e);
      throw ApiError(404, 'competitor_not_found', '@$username wurde nicht gefunden oder ist kein professioneller Account.');
    }
    final row = await s.db.one(
      '''INSERT INTO competitor_accounts (account_id, username, added_by) VALUES (@a, @u, @by)
         ON CONFLICT (account_id, username) DO NOTHING RETURNING id''',
      {'a': id, 'u': username, 'by': auth.userId},
    );
    if (row == null) throw ApiError(409, 'competitor_exists', '@$username wird bereits beobachtet.');
    await sync.snapshotCompetitor(row['id'] as String);
    return jsonOk({'id': row['id']}, status: 201);
  }

  Future<Response> _removeCompetitor(Request request, String id) async {
    final auth = authOf(request);
    final row = await s.db.one(
      '''DELETE FROM competitor_accounts c USING instagram_accounts a
         WHERE c.id = @id AND a.id = c.account_id AND a.workspace_id = @w RETURNING c.id''',
      {'id': id, 'w': auth.workspaceId},
    );
    if (row == null) throw ApiError.notFound('Wettbewerber');
    return jsonOk({'ok': true});
  }

  // -------------------------------------------------------------------
  // Beobachtete Hashtags (Spezifikation 4.9)
  // -------------------------------------------------------------------

  /// Im 7-Tage-Fenster abgefragte Hashtags zählen aufs Kontingent, auch
  /// wenn sie inzwischen entfernt wurden.
  Future<int> _hashtagsUsed(String accountId) async {
    final row = await s.db.one(
      'SELECT count(*)::int AS n FROM hashtag_watches WHERE account_id = @a AND first_queried_at > @t',
      {'a': accountId, 't': s.now().subtract(const Duration(days: AppLimits.hashtagWindowDays))},
    );
    return row!['n'] as int;
  }

  Future<Response> _hashtags(Request request, String id) async {
    final auth = authOf(request);
    await s.accountInWorkspace(id, auth.workspaceId);
    final rows = await s.db.query(
      'SELECT id, hashtag, first_queried_at FROM hashtag_watches WHERE account_id = @a AND active ORDER BY hashtag',
      {'a': id},
    );
    final used = await _hashtagsUsed(id);
    return jsonOk({
      'quota': AppLimits.hashtagQuota,
      'used': used,
      'remaining': AppLimits.hashtagQuota - used,
      'items': rows.map(rowJson).toList(),
    });
  }

  Future<Response> _addHashtag(Request request, String id) async {
    final auth = authOf(request);
    final body = await readJson(request);
    await s.accountInWorkspace(id, auth.workspaceId);
    final tag = body.reqString('hashtag', maxLength: 100).replaceAll('#', '').toLowerCase();
    if (tag.contains(RegExp(r'\s'))) throw ApiError.badRequest('Hashtags dürfen keine Leerzeichen enthalten.');
    final access = await s.facebookAccess(id);
    final existing = await s.db.one('SELECT id, active FROM hashtag_watches WHERE account_id = @a AND hashtag = @h', {'a': id, 'h': tag});
    String watchId;
    if (existing != null) {
      if (existing['active'] == true) throw ApiError(409, 'hashtag_exists', '#$tag wird bereits beobachtet.');
      watchId = existing['id'] as String;
      await s.db.exec('UPDATE hashtag_watches SET active = true WHERE id = @id', {'id': watchId});
    } else {
      if (await _hashtagsUsed(id) >= AppLimits.hashtagQuota) {
        throw ApiError(429, 'hashtag_quota', 'Das Kontingent von ${AppLimits.hashtagQuota} Hashtags in 7 Tagen ist für diesen Account aufgebraucht.');
      }
      String igId;
      try {
        igId = await s.instagram.hashtagId(access, tag);
      } on InstagramApiException catch (e) {
        throw s.instagramError(e);
      }
      final row = await s.db.one(
        'INSERT INTO hashtag_watches (account_id, hashtag, ig_hashtag_id, first_queried_at) VALUES (@a, @h, @ig, @now) RETURNING id',
        {'a': id, 'h': tag, 'ig': igId, 'now': s.now()},
      );
      watchId = row!['id'] as String;
    }
    await sync.refreshHashtag(watchId);
    return jsonOk({'id': watchId}, status: 201);
  }

  Future<Response> _removeHashtag(Request request, String id) async {
    final auth = authOf(request);
    final row = await s.db.one(
      '''UPDATE hashtag_watches h SET active = false FROM instagram_accounts a
         WHERE h.id = @id AND a.id = h.account_id AND a.workspace_id = @w RETURNING h.id''',
      {'id': id, 'w': auth.workspaceId},
    );
    if (row == null) throw ApiError.notFound('Hashtag');
    return jsonOk({'ok': true});
  }
}
