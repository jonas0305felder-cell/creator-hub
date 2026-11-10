import 'dart:async';
import 'dart:io';

import 'services/publish_service.dart';
import 'services/services.dart';
import 'services/sync_service.dart';

/// Hintergrundjobs des Servers. Ein Takt pro Minute prüft, was fällig ist.
///
/// Die Abstände stehen hier gebündelt, damit sie leicht anpassbar sind
/// (Spezifikation Abschnitt 8, Punkt 10).
class Scheduler {
  Scheduler(this.s, this.sync, this.publisher);

  final Services s;
  final SyncService sync;
  final PublishService publisher;

  static const accountSyncEvery = Duration(hours: 24);
  static const storySyncEvery = Duration(hours: 4);
  static const expiringStoryCheckEvery = Duration(minutes: 30);
  static const rssCheckEvery = Duration(hours: 1);
  static const weeklySummaryEvery = Duration(days: 7);

  Timer? _timer;
  bool _running = false;

  void start() {
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => tick());
  }

  void stop() => _timer?.cancel();

  /// Ein Durchlauf (auch direkt aus Tests aufrufbar).
  Future<void> tick() async {
    if (_running) return;
    _running = true;
    try {
      await _guard('publish', publisher.publishDue);
      if (await _due('expiring_stories', expiringStoryCheckEvery)) {
        await _guard('expiring_stories', () async {
          for (final id in await sync.accountsWithExpiringStories()) {
            await sync.syncStoriesOnly(id);
          }
        });
      }
      if (await _due('stories', storySyncEvery)) {
        await _guard('stories', () async {
          for (final id in await _connectedAccounts()) {
            await sync.syncStoriesOnly(id);
          }
        });
      }
      if (await _due('rss', rssCheckEvery)) {
        await _guard('rss', () async {
          final rows = await s.db.query(
            '''SELECT id FROM trend_sources WHERE type = 'rss'
               AND (last_attempt_at IS NULL OR last_attempt_at < @now::timestamptz - make_interval(hours => refresh_interval_hours))''',
            {'now': s.now()},
          );
          for (final r in rows) {
            await sync.refreshRssSource(r['id'] as String);
          }
        });
      }
      if (await _due('daily', accountSyncEvery)) {
        await _guard('daily', () async {
          await sync.refreshTokens();
          for (final id in await _connectedAccounts()) {
            await sync.syncAccount(id);
          }
          for (final r in await s.db.query('SELECT id FROM competitor_accounts')) {
            await sync.snapshotCompetitor(r['id'] as String);
          }
          for (final r in await s.db.query('SELECT id FROM hashtag_watches WHERE active')) {
            await sync.refreshHashtag(r['id'] as String);
          }
          await sync.cleanup();
        });
      }
      if (await _due('weekly_summary', weeklySummaryEvery)) {
        await _guard('weekly_summary', _weeklySummary);
      }
    } finally {
      _running = false;
    }
  }

  Future<List<String>> _connectedAccounts() async {
    final rows = await s.db.query(
      "SELECT id FROM instagram_accounts WHERE account_type <> 'manual' AND connection_status <> 'disconnected'",
    );
    return [for (final r in rows) r['id'] as String];
  }

  /// Prüft, ob ein Job fällig ist, und merkt sich den Start in der Datenbank
  /// (damit ein Neustart des Servers nichts doppelt auslöst).
  Future<bool> _due(String name, Duration every) async {
    final row = await s.db.one(
      '''INSERT INTO job_runs (name, last_run_at) VALUES (@n, @now)
         ON CONFLICT (name) DO UPDATE SET last_run_at = @now WHERE job_runs.last_run_at <= @limit
         RETURNING name''',
      {'n': name, 'now': s.now(), 'limit': s.now().subtract(every)},
    );
    return row != null;
  }

  Future<void> _guard(String name, Future<void> Function() job) async {
    try {
      await job();
    } catch (e) {
      stderr.writeln('[job $name] Fehler: $e');
    }
  }

  /// Wöchentliche Zusammenfassung pro Account als Benachrichtigung.
  Future<void> _weeklySummary() async {
    final accounts = await s.db.query("SELECT id, workspace_id, username FROM instagram_accounts WHERE account_type <> 'manual'");
    final to = s.now();
    final from = to.subtract(const Duration(days: 7));
    for (final a in accounts) {
      final rows = await s.db.query(
        '''SELECT metric, sum(value)::bigint AS total FROM account_daily_metrics
           WHERE account_id = @a AND date >= @from AND date < @to AND value IS NOT NULL
             AND metric IN ('reach','total_interactions') GROUP BY metric''',
        {'a': a['id'], 'from': from, 'to': to},
      );
      if (rows.isEmpty) continue;
      final totals = {for (final r in rows) r['metric'] as String: r['total']};
      await s.notify(
        workspaceId: a['workspace_id'] as String,
        accountId: a['id'] as String,
        kind: 'weekly_summary',
        title: 'Wochenrückblick @${a['username']}',
        body: 'Reichweite ${totals['reach'] ?? '–'}, Interaktionen ${totals['total_interactions'] ?? '–'} in den letzten 7 Tagen.',
        target: 'stats',
      );
    }
  }
}
