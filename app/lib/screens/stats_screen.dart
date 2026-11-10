import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../config/app_texts.dart';
import '../config/app_theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/account_switcher.dart';
import '../widgets/common.dart';
import '../widgets/line_chart.dart';
import 'accounts_screen.dart';
import 'stats_detail_screens.dart';

/// Tab „Statistiken“: ein Account im Detail oder alle im Vergleich.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  int _days = AppConfig.statsPeriods.first;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final account = state.activeAccount;
    return Scaffold(
      appBar: const AccountHeader(title: T.tabStats),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.m, AppSpacing.l, 0),
            child: SegmentedButton<int>(
              segments: [for (final d in AppConfig.statsPeriods) ButtonSegment(value: d, label: Text(T.periodDays(d)))],
              selected: {_days},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _days = s.first),
            ),
          ),
          Expanded(
            child: state.accounts.isEmpty
                ? EmptyView(
                    text: T.statsNoAccounts,
                    icon: Icons.bar_chart,
                    action: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const AccountsScreen())),
                    actionLabel: T.connectAccount,
                  )
                : account == null
                ? _CompareView(key: ValueKey('compare-$_days'), days: _days)
                : _AccountStats(key: ValueKey('${account.id}-$_days'), account: account, days: _days),
          ),
        ],
      ),
    );
  }
}

/// „Alle Accounts“: Kennzahlen nebeneinander.
class _CompareView extends StatelessWidget {
  const _CompareView({super.key, required this.days});
  final int days;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    return AsyncView<Map<String, dynamic>>(
      load: () async => Map<String, dynamic>.from(await state.api.get('/api/stats/overview', query: {'days': '$days'}) as Map),
      builder: (context, data, reload) {
        final rows = [for (final s in data['accounts'] as List) Map<String, dynamic>.from(s as Map)];
        Widget cell(String text, {bool head = false, bool muted = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s, vertical: AppSpacing.m),
          child: Text(
            text,
            textAlign: TextAlign.right,
            style: head
                ? theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)
                : theme.textTheme.bodyMedium?.copyWith(color: muted ? theme.colorScheme.outline : null),
          ),
        );
        String value(Map<String, dynamic> row, String key) {
          final v = (row['totals'] as Map)[key] as num?;
          return v == null ? '–' : formatCompact(v);
        }

        return PageList(
          onRefresh: reload,
          children: [
            const SectionTitle(T.statsCompare),
            Card(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Table(
                  defaultColumnWidth: const IntrinsicColumnWidth(),
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    TableRow(
                      children: [
                        const SizedBox(width: 150),
                        for (final h in [T.reach, T.views, T.interactions, T.followers, T.followerBalance]) cell(h, head: true),
                      ],
                    ),
                    for (final row in rows)
                      TableRow(
                        decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
                        ),
                        children: [
                          InkWell(
                            onTap: () => state.setActiveAccount(row['account_id'] as String),
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.m),
                              child: SizedBox(width: 150, child: AccountTag(state.accountById(row['account_id'] as String))),
                            ),
                          ),
                          cell(value(row, 'reach')),
                          cell(value(row, 'views')),
                          cell(value(row, 'total_interactions')),
                          cell(formatCompact(row['followers_count'] as num?)),
                          cell(
                            row['follower_delta'] == null
                                ? '–'
                                : '${(row['follower_delta'] as int) > 0 ? '+' : ''}${formatNumber(row['follower_delta'] as int)}',
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.m),
            // Gründe für fehlende Werte je Account.
            for (final row in rows)
              for (final m in row['missing'] as List)
                Notice('@${state.accountById(row['account_id'] as String)?.username ?? ''}: ${(m as Map)['text']}'),
          ],
        );
      },
    );
  }
}

class _AccountStats extends StatefulWidget {
  const _AccountStats({super.key, required this.account, required this.days});
  final Account account;
  final int days;

  @override
  State<_AccountStats> createState() => _AccountStatsState();
}

class _AccountStatsState extends State<_AccountStats> {
  String _chartMetric = 'reach';
  String _sort = 'reach';

  static const _chartMetrics = {'reach': T.reach, 'views': T.views, 'total_interactions': T.interactions};
  static const _sortOptions = {'reach': T.reach, 'total_interactions': T.interactions, 'saved': T.saves, 'shares': T.shares};

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final account = widget.account;
    final color = colorFromHex(account.color);
    return AsyncView<({Map<String, dynamic> stats, List<Map<String, dynamic>> media})>(
      // Zeigt zuerst die gespeicherten Werte; „Aktualisieren“ holt neue.
      load: () async {
        final results = await Future.wait([
          state.api.get('/api/accounts/${account.id}/stats', query: {'days': '${widget.days}'}),
          state.api.get('/api/accounts/${account.id}/media', query: {'days': '${widget.days}'}),
        ]);
        return (
          stats: Map<String, dynamic>.from(results[0] as Map),
          media: [for (final m in results[1] as List) Map<String, dynamic>.from(m as Map)],
        );
      },
      builder: (context, data, reload) {
        final totals = Map<String, dynamic>.from(data.stats['totals'] as Map);
        final previous = Map<String, dynamic>.from(data.stats['previous'] as Map);
        final missing = [for (final m in data.stats['missing'] as List) (m as Map)['text'] as String];
        List<ChartPoint> points(List<dynamic>? raw) => [
          for (final p in raw ?? const [])
            if ((p as Map)['value'] != null) ChartPoint(DateTime.parse(p['date'] as String), p['value'] as num),
        ];
        final series = points((data.stats['series'] as Map)[_chartMetric] as List?);
        final followerSeries = points(data.stats['follower_series'] as List?);
        final media = [...data.media]
          ..sort((a, b) {
            final av = (a['metrics'] as Map)[_sort] as num?;
            final bv = (b['metrics'] as Map)[_sort] as num?;
            // Beiträge ohne Wert ans Ende.
            if (av == null && bv == null) return 0;
            if (av == null) return 1;
            if (bv == null) return -1;
            return bv.compareTo(av);
          });

        Widget tile(String label, String key) => MetricTile(
          label: label,
          value: totals[key] as num?,
          change: percentChange(totals[key] as num?, previous[key] as num?),
          changeLabel: T.vsPrevPeriod,
        );

        Future<void> refresh() async {
          if (!account.isManual) {
            // Manuelles Aktualisieren stößt eine Synchronisation an.
            await guarded(context, () => state.api.post('/api/accounts/${account.id}/sync', null, true));
            await state.refreshAccounts();
          }
          await reload();
        }

        return PageList(
          onRefresh: refresh,
          children: [
            Row(
              children: [
                Expanded(child: DataStamp(parseDate(data.stats['fetched_at']))),
                TextButton.icon(onPressed: refresh, icon: const Icon(Icons.refresh, size: 18), label: const Text(T.refresh)),
              ],
            ),
            for (final m in missing) Notice(m),
            TileGrid(
              children: [
                tile(T.reach, 'reach'),
                tile(T.views, 'views'),
                tile(T.interactions, 'total_interactions'),
                MetricTile(
                  label: T.followers,
                  value: account.followers,
                  sub: data.stats['follower_delta'] == null
                      ? null
                      : '${T.followerBalance}: ${(data.stats['follower_delta'] as int) > 0 ? '+' : ''}${data.stats['follower_delta']}',
                ),
                tile(T.likes, 'likes'),
                tile(T.comments, 'comments'),
                tile(T.shares, 'shares'),
                tile(T.saves, 'saves'),
                tile(T.follows, 'follows'),
                tile(T.unfollows, 'unfollows'),
              ],
            ),
            const SizedBox(height: AppSpacing.m),
            Wrap(
              spacing: AppSpacing.s,
              runSpacing: AppSpacing.s,
              children: [
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => StoriesScreen(account: account))),
                  icon: const Icon(Icons.amp_stories_outlined, size: 18),
                  label: const Text(T.storyStats),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => CompetitorsScreen(account: account))),
                  icon: const Icon(Icons.groups_outlined, size: 18),
                  label: const Text(T.competitors),
                ),
              ],
            ),
            SectionTitle(
              T.statsChart,
              trailing: DropdownButton<String>(
                value: _chartMetric,
                underline: const SizedBox.shrink(),
                items: [for (final e in _chartMetrics.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => setState(() => _chartMetric = v!),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.m),
                child: LineChart(
                  points: series,
                  color: color,
                  semanticLabel: '${_chartMetrics[_chartMetric]}, ${T.periodDays(widget.days)}',
                ),
              ),
            ),
            const SectionTitle(T.statsFollowerChart),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.m),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LineChart(points: followerSeries, color: color, height: 140, semanticLabel: T.statsFollowerChart),
                    const SizedBox(height: AppSpacing.s),
                    Text(T.followerHistoryNote, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
            SectionTitle(
              T.statsPosts,
              trailing: DropdownButton<String>(
                value: _sort,
                underline: const SizedBox.shrink(),
                items: [for (final e in _sortOptions.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => setState(() => _sort = v!),
              ),
            ),
            if (media.isEmpty) const EmptyView(text: T.statsNoPosts, icon: Icons.photo_library_outlined),
            for (final m in media)
              Card(
                margin: const EdgeInsets.only(bottom: AppSpacing.s),
                child: ListTile(
                  leading: MediaThumb(m['thumbnail_url'] as String?),
                  title: Text(
                    (m['caption'] as String?)?.replaceAll('\n', ' ') ?? mediaFormatLabel(m),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text('${mediaFormatLabel(m)} · ${formatDate(parseDate(m['posted_at']))}'),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(formatCompact((m['metrics'] as Map)[_sort] as num?), style: theme.textTheme.titleSmall),
                      Text(_sortOptions[_sort]!, style: theme.textTheme.bodySmall),
                    ],
                  ),
                  onTap: () =>
                      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => MediaDetailScreen(mediaId: m['id'] as String))),
                ),
              ),
          ],
        );
      },
    );
  }
}
