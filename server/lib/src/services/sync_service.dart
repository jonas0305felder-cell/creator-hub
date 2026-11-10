import 'dart:convert';

import '../config.dart';
import '../instagram/instagram_api.dart';
import 'services.dart';

/// Holt Profile, Beiträge, Insights, Stories, Kommentare, Wettbewerber,
/// Hashtags und RSS-Trends (Spezifikation 4.3, 4.7, 4.8, 4.9, 7.4).
class SyncService {
  SyncService(this.s);

  final Services s;

  /// Höchstzahl Tage, die beim ersten Sync rückwirkend geholt werden.
  static const backfillDays = 30;

  /// Für wie viele der letzten Beiträge Kommentare geholt werden.
  static const commentMediaCount = 10;

  // ---------------------------------------------------------------------
  // Account-Sync (täglich und auf Knopfdruck)
  // ---------------------------------------------------------------------

  Future<void> syncAccount(String accountId) async {
    final account = await s.db.one('SELECT * FROM instagram_accounts WHERE id = @id', {'id': accountId});
    if (account == null || account['account_type'] == 'manual') return;
    final workspaceId = account['workspace_id'] as String;
    try {
      await s.db.exec(
        "UPDATE instagram_accounts SET connection_status = 'syncing' WHERE id = @id AND connection_status <> 'disconnected'",
        {'id': accountId},
      );
      final access = await s.access(accountId);
      await _syncProfile(accountId, access);
      await _syncMedia(accountId, access);
      await _syncAccountInsights(accountId, access);
      await _syncStories(accountId, access, workspaceId);
      await _syncComments(accountId, access, workspaceId);
      await s.db.exec(
        '''UPDATE instagram_accounts SET last_synced_at = @now, last_sync_error = NULL WHERE id = @id''',
        {'id': accountId, 'now': s.now()},
      );
    } on InstagramApiException catch (e) {
      if (e.isAuthError) {
        await _markDisconnected(accountId, workspaceId, account['username'] as String);
      }
      await s.db.exec('UPDATE instagram_accounts SET last_sync_error = @e WHERE id = @id', {
        'id': accountId,
        'e': e.message,
      });
    } catch (e) {
      await s.db.exec('UPDATE instagram_accounts SET last_sync_error = @e WHERE id = @id', {
        'id': accountId,
        'e': e.toString(),
      });
    } finally {
      await _updateConnectionStatus(accountId);
    }
  }

  Future<void> _syncProfile(String accountId, IgAccess access) async {
    final p = await s.instagram.profile(access);
    final followers = (p['followers_count'] as num?)?.toInt();
    final type = (p['account_type'] ?? '').toString().toLowerCase();
    await s.db.exec(
      '''UPDATE instagram_accounts SET username = @u, profile_picture_url = @pic,
           followers_count = @f, media_count = @m,
           account_type = CASE WHEN @t IN ('business','creator') THEN @t ELSE account_type END
         WHERE id = @id''',
      {
        'id': accountId,
        'u': p['username'],
        'pic': p['profile_picture_url'],
        'f': followers,
        'm': (p['media_count'] as num?)?.toInt(),
        't': type == 'media_creator' ? 'creator' : type,
      },
    );
    if (followers != null) {
      // Eigener täglicher Snapshot: der Follower-Verlauf ist über die API
      // nicht sicher abrufbar (Spezifikation 7.3).
      await s.db.exec(
        '''INSERT INTO follower_snapshots (account_id, date, followers_count, fetched_at)
           VALUES (@a, @d, @f, @now)
           ON CONFLICT (account_id, date) DO UPDATE SET followers_count = @f, fetched_at = @now''',
        {'a': accountId, 'd': _day(s.now()), 'f': followers, 'now': s.now()},
      );
    }
  }

  Future<void> _syncMedia(String accountId, IgAccess access) async {
    final items = await s.instagram.recentMedia(access);
    for (final m in items) {
      final mediaId = await _upsertMedia(accountId, m);
      try {
        final insights = await s.instagram.mediaInsights(
          access,
          m['id'].toString(),
          productType: (m['media_product_type'] ?? 'FEED').toString(),
          mediaType: (m['media_type'] ?? '').toString(),
        );
        await _storeMediaMetrics(mediaId, insights);
      } on InstagramApiException catch (e) {
        if (e.isAuthError) rethrow;
        // Für einzelne Beiträge liefert Instagram teils keine Insights;
        // dann bleibt der Wert fehlend statt 0 (Spezifikation 6, Regeln).
      }
    }
  }

  Future<String> _upsertMedia(String accountId, Map<String, dynamic> m) async {
    final row = await s.db.one(
      '''INSERT INTO media (account_id, ig_media_id, media_type, media_product_type, caption, permalink, thumbnail_url, posted_at)
         VALUES (@a, @ig, @type, @product, @caption, @link, @thumb, @posted)
         ON CONFLICT (account_id, ig_media_id) DO UPDATE SET
           caption = EXCLUDED.caption, permalink = EXCLUDED.permalink,
           thumbnail_url = COALESCE(EXCLUDED.thumbnail_url, media.thumbnail_url),
           media_product_type = EXCLUDED.media_product_type
         RETURNING id''',
      {
        'a': accountId,
        'ig': m['id'].toString(),
        'type': (m['media_type'] ?? 'IMAGE').toString(),
        'product': _product(m),
        'caption': m['caption'],
        'link': m['permalink'],
        'thumb': m['thumbnail_url'] ?? (m['media_type'] == 'VIDEO' ? null : m['media_url']),
        'posted': m['timestamp'] == null ? null : DateTime.tryParse(m['timestamp'].toString())?.toUtc(),
      },
    );
    return row!['id'] as String;
  }

  static String _product(Map<String, dynamic> m) {
    final p = (m['media_product_type'] ?? 'FEED').toString().toUpperCase();
    if (p == 'REELS') return 'reels';
    if (p == 'STORY') return 'story';
    return 'feed';
  }

  Future<void> _storeMediaMetrics(String mediaId, Map<String, num?> values) async {
    for (final e in values.entries) {
      await s.db.exec(
        '''INSERT INTO media_metrics (media_id, metric, value, fetched_at) VALUES (@m, @k, @v, @now)
           ON CONFLICT (media_id, metric) DO UPDATE SET value = @v, fetched_at = @now''',
        {'m': mediaId, 'k': e.key, 'v': e.value?.toDouble(), 'now': s.now()},
      );
    }
  }

  Future<void> _syncAccountInsights(String accountId, IgAccess access) async {
    final today = _day(s.now());
    final last = await s.db.one(
      'SELECT max(date) AS d FROM account_daily_metrics WHERE account_id = @a',
      {'a': accountId},
    );
    final lastDate = last?['d'] as DateTime?;
    // Daten können bis zu 48 Stunden verzögert sein (Spezifikation 7.3),
    // daher die letzten 3 Tage immer neu holen.
    var start = lastDate == null
        ? today.subtract(const Duration(days: backfillDays))
        : lastDate.subtract(const Duration(days: 2));
    final oldest = today.subtract(const Duration(days: backfillDays));
    if (start.isBefore(oldest)) start = oldest;
    for (var day = start; day.isBefore(today); day = day.add(const Duration(days: 1))) {
      Map<String, num?> values;
      try {
        values = await s.instagram.accountDayInsights(access, day);
      } on InstagramApiException catch (e) {
        if (e.isAuthError) rethrow;
        continue;
      }
      for (final e in values.entries) {
        await s.db.exec(
          '''INSERT INTO account_daily_metrics (account_id, date, metric, value, fetched_at)
             VALUES (@a, @d, @k, @v, @now)
             ON CONFLICT (account_id, date, metric) DO UPDATE SET value = @v, fetched_at = @now''',
          {'a': accountId, 'd': day, 'k': e.key, 'v': e.value?.toInt(), 'now': s.now()},
        );
      }
    }
  }

  // ---------------------------------------------------------------------
  // Stories: alle 4 Stunden und kurz vor Ablauf (Spezifikation 4.7)
  // ---------------------------------------------------------------------

  Future<void> syncStoriesOnly(String accountId) async {
    final account = await s.db.one('SELECT workspace_id, account_type FROM instagram_accounts WHERE id = @id', {'id': accountId});
    if (account == null || account['account_type'] == 'manual') return;
    try {
      await _syncStories(accountId, await s.access(accountId), account['workspace_id'] as String);
    } catch (_) {
      // Fehler landen beim nächsten vollen Sync in last_sync_error.
    }
  }

  Future<void> _syncStories(String accountId, IgAccess access, String workspaceId) async {
    final stories = await s.instagram.stories(access);
    for (final story in stories) {
      final mediaId = await _upsertMedia(accountId, {...story, 'media_product_type': 'STORY'});
      try {
        final values = await s.instagram.storyInsights(access, story['id'].toString());
        final now = s.now();
        for (final e in values.entries) {
          await s.db.exec(
            '''INSERT INTO story_metric_snapshots (media_id, captured_at, metric, value)
               VALUES (@m, @t, @k, @v) ON CONFLICT DO NOTHING''',
            {'m': mediaId, 't': now, 'k': e.key, 'v': e.value?.toDouble()},
          );
        }
        await _storeMediaMetrics(mediaId, values);
      } on InstagramApiException catch (e) {
        if (e.isAuthError) rethrow;
        // Unter 5 Betrachtern liefert Instagram einen Fehler statt Werten.
      }
    }
  }

  /// Story-IDs, die in der nächsten Stunde ablaufen (für die letzte Sicherung).
  Future<List<String>> accountsWithExpiringStories() async {
    final rows = await s.db.query(
      '''SELECT DISTINCT account_id FROM media
         WHERE media_product_type = 'story'
           AND posted_at BETWEEN @from AND @to''',
      {
        'from': s.now().subtract(const Duration(hours: 24)),
        'to': s.now().subtract(const Duration(hours: 23)),
      },
    );
    return [for (final r in rows) r['account_id'] as String];
  }

  // ---------------------------------------------------------------------
  // Kommentare (Spezifikation 4.8)
  // ---------------------------------------------------------------------

  Future<void> _syncComments(String accountId, IgAccess access, String workspaceId) async {
    final media = await s.db.query(
      '''SELECT id, ig_media_id FROM media WHERE account_id = @a AND media_product_type <> 'story'
         ORDER BY posted_at DESC NULLS LAST LIMIT $commentMediaCount''',
      {'a': accountId},
    );
    final account = await s.db.one('SELECT username FROM instagram_accounts WHERE id = @a', {'a': accountId});
    final ownName = account?['username'] as String?;
    var newCount = 0;
    for (final m in media) {
      List<Map<String, dynamic>> comments;
      try {
        comments = await s.instagram.comments(access, m['ig_media_id'] as String);
      } on InstagramApiException catch (e) {
        if (e.isAuthError) rethrow;
        continue;
      }
      for (final c in comments) {
        newCount += await _upsertComment(m['id'] as String, c, null, ownName);
        final replies = (c['replies'] as Map?)?['data'] as List? ?? const [];
        for (final r in replies) {
          await _upsertComment(m['id'] as String, r as Map<String, dynamic>, c['id'].toString(), ownName);
        }
      }
    }
    if (newCount > 0) {
      await s.notify(
        workspaceId: workspaceId,
        accountId: accountId,
        kind: 'new_comments',
        title: newCount == 1 ? '1 neuer Kommentar bei @$ownName' : '$newCount neue Kommentare bei @$ownName',
        target: 'comments',
      );
    }
  }

  /// Liefert 1, wenn der Kommentar neu ist und nicht vom eigenen Account stammt.
  Future<int> _upsertComment(String mediaId, Map<String, dynamic> c, String? parent, String? ownName) async {
    final isOwn = ownName != null && c['username'] == ownName;
    final row = await s.db.one(
      '''INSERT INTO comments (media_id, ig_comment_id, parent_comment_id, author_username, text, created_at, is_hidden, is_own, fetched_at)
         VALUES (@m, @id, @p, @u, @t, @c, @h, @own, @now)
         ON CONFLICT (ig_comment_id) DO UPDATE SET text = @t, is_hidden = @h, fetched_at = @now
         RETURNING (xmax = 0) AS inserted''',
      {
        'm': mediaId,
        'id': c['id'].toString(),
        'p': parent,
        'u': (c['username'] ?? '').toString(),
        't': (c['text'] ?? '').toString(),
        'c': DateTime.tryParse((c['timestamp'] ?? '').toString())?.toUtc() ?? s.now(),
        'h': c['hidden'] == true,
        'own': isOwn,
        'now': s.now(),
      },
    );
    if (parent != null && isOwn) {
      // Antwort des eigenen Accounts: Elternkommentar gilt als beantwortet.
      await s.db.exec(
        'UPDATE comments SET replied_at = COALESCE(replied_at, @now) WHERE ig_comment_id = @p',
        {'p': parent, 'now': s.now()},
      );
    }
    return (row?['inserted'] == true && !isOwn) ? 1 : 0;
  }

  // ---------------------------------------------------------------------
  // Tokens (Spezifikation 7.2: Erneuerung ab Tag 45)
  // ---------------------------------------------------------------------

  Future<void> refreshTokens() async {
    final rows = await s.db.query(
      '''SELECT c.account_id, c.login_type, c.encrypted_access_token, a.workspace_id, a.username
         FROM instagram_credentials c JOIN instagram_accounts a ON a.id = c.account_id
         WHERE c.token_expires_at IS NOT NULL AND c.token_expires_at < @limit''',
      {'limit': s.now().add(const Duration(days: 15))},
    );
    for (final r in rows) {
      final accountId = r['account_id'] as String;
      try {
        final token = await s.security.decrypt(r['encrypted_access_token'] as String);
        final result = await s.instagram.refreshToken(r['login_type'] as String, token);
        await s.db.exec(
          '''UPDATE instagram_credentials SET encrypted_access_token = @t, token_expires_at = @e, last_refreshed_at = @now
             WHERE account_id = @a''',
          {
            'a': accountId,
            't': await s.security.encrypt(result.accessToken),
            'e': result.expiresAt,
            'now': s.now(),
          },
        );
      } on InstagramApiException catch (e) {
        if (e.isAuthError) {
          await _markDisconnected(accountId, r['workspace_id'] as String, r['username'] as String);
        }
      } catch (_) {
        // Nächster Versuch beim nächsten Lauf.
      }
      await _updateConnectionStatus(accountId);
    }
  }

  Future<void> _markDisconnected(String accountId, String workspaceId, String username) async {
    final row = await s.db.one(
      "UPDATE instagram_accounts SET connection_status = 'disconnected' WHERE id = @id AND connection_status <> 'disconnected' RETURNING id",
      {'id': accountId},
    );
    if (row != null) {
      await s.notify(
        workspaceId: workspaceId,
        accountId: accountId,
        kind: 'reconnect_required',
        title: 'Neu verbinden nötig: @$username',
        body: 'Instagram hat den Zugriff beendet oder das Token ist abgelaufen.',
        target: 'accounts',
      );
    }
  }

  /// Setzt „verbunden“ bzw. „läuft bald ab“ anhand des Token-Ablaufs.
  Future<void> _updateConnectionStatus(String accountId) async {
    final row = await s.db.one(
      '''SELECT a.connection_status, a.workspace_id, a.username, c.token_expires_at
         FROM instagram_accounts a LEFT JOIN instagram_credentials c ON c.account_id = a.id
         WHERE a.id = @id''',
      {'id': accountId},
    );
    if (row == null) return;
    final status = row['connection_status'] as String;
    if (status == 'disconnected' || status == 'manual') return;
    final expires = row['token_expires_at'] as DateTime?;
    final expiring =
        expires != null && expires.isBefore(s.now().add(const Duration(days: AppLimits.tokenWarningDays)));
    final next = expiring ? 'expiring' : 'connected';
    if (next != status) {
      await s.db.exec('UPDATE instagram_accounts SET connection_status = @s WHERE id = @id', {'id': accountId, 's': next});
      if (expiring) {
        await s.notify(
          workspaceId: row['workspace_id'] as String,
          accountId: accountId,
          kind: 'token_expiring',
          title: 'Verbindung von @${row['username']} läuft bald ab',
          body: 'Bitte in der Account-Übersicht neu verbinden.',
          target: 'accounts',
        );
      }
    }
  }

  // ---------------------------------------------------------------------
  // Wettbewerber (Business Discovery, täglich)
  // ---------------------------------------------------------------------

  Future<void> snapshotCompetitor(String competitorId) async {
    final c = await s.db.one('SELECT * FROM competitor_accounts WHERE id = @id', {'id': competitorId});
    if (c == null) return;
    try {
      final access = await s.facebookAccess(c['account_id'] as String);
      final bd = await s.instagram.businessDiscovery(access, c['username'] as String);
      final media = ((bd['media'] as Map?)?['data'] as List? ?? const []).cast<Map>();
      double? avg(String key) {
        final values = [for (final m in media) if (m[key] is num) (m[key] as num).toDouble()];
        if (values.isEmpty) return null;
        return values.reduce((a, b) => a + b) / values.length;
      }

      await s.db.exec(
        '''INSERT INTO competitor_snapshots (competitor_id, date, followers_count, media_count, avg_likes, avg_comments, fetched_at)
           VALUES (@c, @d, @f, @m, @l, @k, @now)
           ON CONFLICT (competitor_id, date) DO UPDATE SET followers_count = @f, media_count = @m,
             avg_likes = @l, avg_comments = @k, fetched_at = @now''',
        {
          'c': competitorId,
          'd': _day(s.now()),
          'f': (bd['followers_count'] as num?)?.toInt(),
          'm': (bd['media_count'] as num?)?.toInt(),
          'l': avg('like_count'),
          'k': avg('comments_count'),
          'now': s.now(),
        },
      );
      await s.db.exec('UPDATE competitor_accounts SET ig_user_id = @ig, last_error = NULL WHERE id = @id', {
        'id': competitorId,
        'ig': bd['id']?.toString(),
      });
    } catch (e) {
      await s.db.exec('UPDATE competitor_accounts SET last_error = @e WHERE id = @id', {'id': competitorId, 'e': '$e'});
    }
  }

  // ---------------------------------------------------------------------
  // Hashtags als Trendquelle (Spezifikation 4.9)
  // ---------------------------------------------------------------------

  Future<void> refreshHashtag(String watchId) async {
    final w = await s.db.one(
      '''SELECT h.*, a.workspace_id FROM hashtag_watches h JOIN instagram_accounts a ON a.id = h.account_id
         WHERE h.id = @id AND h.active''',
      {'id': watchId},
    );
    if (w == null || w['ig_hashtag_id'] == null) return;
    final source = await _hashtagSource(w['workspace_id'] as String);
    try {
      final access = await s.facebookAccess(w['account_id'] as String);
      final niches = await s.db.query('SELECT niche_id FROM account_niches WHERE account_id = @a', {'a': w['account_id']});
      for (final top in [true, false]) {
        final media = await s.instagram.hashtagMedia(access, w['ig_hashtag_id'] as String, top: top);
        for (final m in media.take(top ? 5 : 3)) {
          final likes = (m['like_count'] as num?)?.toDouble();
          final caption = (m['caption'] ?? '').toString();
          final row = await s.db.one(
            '''INSERT INTO trends (source_id, external_id, title, summary, reason, source_url, published_at, fetched_at, signal_value, signal_unit, listed)
               VALUES (@s, @ext, @title, @summary, @reason, @url, @pub, @now, @signal, @unit, @listed)
               ON CONFLICT (source_id, external_id) DO UPDATE SET signal_value = @signal, fetched_at = @now
               RETURNING id''',
            {
              's': source,
              'ext': '${w['hashtag']}:${m['id']}',
              'title': '#${w['hashtag']}: ${_shorten(caption.isEmpty ? 'Beitrag ohne Caption' : caption, 80)}',
              'summary': _shorten(caption, 300),
              'reason': top
                  ? 'Gehört zu den Top-Beiträgen für #${w['hashtag']} (${m['media_type'] ?? 'Beitrag'}).'
                  : 'Aktueller Beitrag zu #${w['hashtag']}.',
              'url': m['permalink'],
              'pub': DateTime.tryParse((m['timestamp'] ?? '').toString())?.toUtc(),
              'now': s.now(),
              'signal': likes,
              'unit': likes == null ? null : 'Likes',
              // Top-Beiträge erscheinen sofort als Trendsignal, aktuelle
              // Beiträge erst nach „Als Trend übernehmen“.
              'listed': top,
            },
          );
          for (final n in niches) {
            await s.db.exec(
              'INSERT INTO trend_niches (trend_id, niche_id) VALUES (@t, @n) ON CONFLICT DO NOTHING',
              {'t': row!['id'], 'n': n['niche_id']},
            );
          }
        }
      }
      await s.db.exec('UPDATE trend_sources SET last_success_at = @now, last_attempt_at = @now, last_error = NULL WHERE id = @id', {
        'id': source,
        'now': s.now(),
      });
    } catch (e) {
      await s.db.exec('UPDATE trend_sources SET last_attempt_at = @now, last_error = @e WHERE id = @id', {
        'id': source,
        'now': s.now(),
        'e': '$e',
      });
    }
  }

  Future<String> _hashtagSource(String workspaceId) async {
    final existing = await s.db.one(
      "SELECT id FROM trend_sources WHERE workspace_id = @w AND type = 'hashtag'",
      {'w': workspaceId},
    );
    if (existing != null) return existing['id'] as String;
    final row = await s.db.one(
      "INSERT INTO trend_sources (workspace_id, type, name) VALUES (@w, 'hashtag', 'Instagram Hashtag-Suche') RETURNING id",
      {'w': workspaceId},
    );
    return row!['id'] as String;
  }

  // ---------------------------------------------------------------------
  // RSS-Quellen (Spezifikation 7.4)
  // ---------------------------------------------------------------------

  Future<void> refreshRssSource(String sourceId) async {
    final src = await s.db.one(
      '''SELECT t.*, n.keywords FROM trend_sources t LEFT JOIN niches n ON n.id = t.niche_id
         WHERE t.id = @id AND t.type = 'rss' ''',
      {'id': sourceId},
    );
    if (src == null || src['url'] == null) return;
    try {
      final items = await s.rss.fetch(src['url'] as String);
      final keywords = [
        for (final k in (src['keywords'] as List? ?? const [])) k.toString().toLowerCase(),
      ].where((k) => k.isNotEmpty).toList();
      for (final item in items.take(30)) {
        final haystack = '${item.title} ${item.summary}'.toLowerCase();
        final matched = keywords.where(haystack.contains).toList();
        if (keywords.isNotEmpty && matched.isEmpty) continue;
        final row = await s.db.one(
          '''INSERT INTO trends (source_id, external_id, title, summary, reason, source_url, published_at, fetched_at)
             VALUES (@s, @ext, @title, @summary, @reason, @url, @pub, @now)
             ON CONFLICT (source_id, external_id) DO UPDATE SET fetched_at = @now
             RETURNING id''',
          {
            's': sourceId,
            'ext': item.id,
            'title': _shorten(item.title, 200),
            'summary': item.summary,
            'reason': matched.isEmpty
                ? 'Neuer Beitrag in „${src['name']}“.'
                : 'Neuer Beitrag in „${src['name']}“ zu: ${matched.join(', ')}.',
            'url': item.link,
            'pub': item.publishedAt,
            'now': s.now(),
          },
        );
        if (src['niche_id'] != null) {
          await s.db.exec(
            'INSERT INTO trend_niches (trend_id, niche_id) VALUES (@t, @n) ON CONFLICT DO NOTHING',
            {'t': row!['id'], 'n': src['niche_id']},
          );
        }
      }
      await s.db.exec('UPDATE trend_sources SET last_success_at = @now, last_attempt_at = @now, last_error = NULL WHERE id = @id', {
        'id': sourceId,
        'now': s.now(),
      });
    } catch (e) {
      await s.db.exec('UPDATE trend_sources SET last_attempt_at = @now, last_error = @e WHERE id = @id', {
        'id': sourceId,
        'now': s.now(),
        'e': e.toString().replaceFirst('Exception: ', ''),
      });
    }
  }

  // ---------------------------------------------------------------------
  // Aufräumen (Spezifikation 7.6)
  // ---------------------------------------------------------------------

  Future<void> cleanup() async {
    await s.db.exec('DELETE FROM comments WHERE created_at < @t', {'t': s.now().subtract(const Duration(days: 90))});
    await s.db.exec('DELETE FROM audit_log WHERE created_at < @t', {'t': s.now().subtract(const Duration(days: 365))});
    await s.db.exec('DELETE FROM sessions WHERE expires_at < @now', {'now': s.now()});
    await s.db.exec('DELETE FROM oauth_states WHERE created_at < @t', {'t': s.now().subtract(const Duration(hours: 1))});
    await s.db.exec('DELETE FROM oauth_results WHERE created_at < @t', {'t': s.now().subtract(const Duration(minutes: 15))});
    await s.db.exec('DELETE FROM notifications WHERE created_at < @t', {'t': s.now().subtract(const Duration(days: 60))});
  }

  static DateTime _day(DateTime t) => DateTime.utc(t.year, t.month, t.day);

  static String _shorten(String text, int max) {
    final oneLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return oneLine.length <= max ? oneLine : '${oneLine.substring(0, max - 1)}…';
  }

  /// Für Logs: kompakte Beschreibung.
  static String describe(Object e) => e is InstagramApiException ? e.message : jsonEncode('$e');
}
