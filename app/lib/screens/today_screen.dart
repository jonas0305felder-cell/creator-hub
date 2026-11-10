import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../config/app_texts.dart';
import '../config/app_theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/account_switcher.dart';
import '../widgets/common.dart';
import 'accounts_screen.dart';
import 'comments_screen.dart';
import 'idea_detail_screen.dart';
import 'quick_idea_sheet.dart';
import 'stats_detail_screens.dart';
import 'trends_screen.dart';

/// Tab „Heute“: Überblick in unter zwei Minuten.
class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AccountHeader(
        title: T.tabToday,
        actions: [
          IconButton(
            tooltip: T.notifications,
            icon: Badge(
              isLabelVisible: state.unreadNotifications > 0,
              label: Text('${state.unreadNotifications}'),
              child: const Icon(Icons.notifications_outlined),
            ),
            onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const NotificationsScreen())),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'today-fab',
        onPressed: () => showQuickIdea(context),
        icon: const Icon(Icons.add),
        label: const Text(T.quickIdea),
      ),
      body: AsyncView<_TodayData>(
        key: ValueKey('today-${state.accounts.length}'),
        load: () async {
          final results = await Future.wait([
            state.api.get('/api/stats/overview', query: {'days': '7'}),
            state.api.get('/api/trends'),
          ]);
          return _TodayData(
            overview: Map<String, dynamic>.from(results[0] as Map),
            trends: [for (final t in (results[1] as Map)['trends'] as List) Trend.fromJson(Map<String, dynamic>.from(t as Map))],
          );
        },
        builder: (context, data, reload) => _TodayBody(
          data: data,
          onRefresh: () async {
            await state.reload();
            await reload();
          },
        ),
      ),
    );
  }
}

class _TodayData {
  _TodayData({required this.overview, required this.trends});
  final Map<String, dynamic> overview;
  final List<Trend> trends;
}

class _TodayBody extends StatelessWidget {
  const _TodayBody({required this.data, required this.onRefresh});
  final _TodayData data;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final now = DateTime.now();
    final active = state.activeAccountId;
    final accounts = state.accounts.where((a) => active == null || a.id == active).toList();
    final summaries = {
      for (final s in (data.overview['accounts'] as List)) (s as Map)['account_id'] as String: Map<String, dynamic>.from(s),
    };
    final unanswered = Map<String, dynamic>.from(data.overview['unanswered_comments'] as Map? ?? const {});
    final unansweredCount = accounts.fold<int>(0, (sum, a) => sum + ((unanswered[a.id] as int?) ?? 0));

    // Hinweise: abgelaufene Verbindung oder veraltete Daten.
    final warnings = <Widget>[
      for (final a in accounts)
        if (a.isDisconnected)
          Notice(
            T.warnDisconnected(a.username),
            icon: Icons.link_off,
            color: theme.colorScheme.error,
            action: () => _openAccounts(context),
            actionLabel: T.reconnect,
          )
        else if (a.isExpiring)
          Notice(
            T.warnExpiring(a.username),
            icon: Icons.timer_outlined,
            color: AppColors.warning,
            action: () => _openAccounts(context),
            actionLabel: T.reconnect,
          )
        else if (!a.isManual && a.lastSyncedAt == null)
          Notice(T.warnNeverSynced(a.username), icon: Icons.sync_problem, color: AppColors.warning)
        else if (a.isStale(now))
          Notice(T.warnStale(a.username, formatDateTime(a.lastSyncedAt)), icon: Icons.history, color: AppColors.warning),
    ];

    final nicheIds = state.contextNicheIds.toSet();
    final trends = data.trends
        .where((t) => t.freshness(now) != Freshness.stale)
        .where((t) => nicheIds.isEmpty || t.nicheIds.any(nicheIds.contains))
        .take(AppConfig.todayTrendCount)
        .toList();
    final inProgress = state.ideas.where((i) => i.status == 'in_progress' && (active == null || i.accountId == active)).toList();
    final standout = data.overview['standout'] as Map?;
    final showStandout = standout != null && (active == null || standout['account_id'] == active);

    return PageList(
      onRefresh: onRefresh,
      bottomSpace: true,
      children: [
        if (warnings.isNotEmpty) ...[const SectionTitle(T.todayWarnings), ...warnings],
        if (unansweredCount > 0 && AppConfig.featureComments)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.m),
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.mode_comment_outlined),
                title: Text(T.unansweredComments(unansweredCount)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const CommentsScreen())),
              ),
            ),
          ),
        const SectionTitle(T.todayAccounts),
        if (state.accounts.isEmpty)
          EmptyView(text: T.todayNoAccounts, icon: Icons.add_link, action: () => _openAccounts(context), actionLabel: T.todayConnectButton)
        else
          for (final a in accounts) _AccountCard(account: a, summary: summaries[a.id]),
        const SectionTitle(T.todayStandout),
        if (showStandout)
          _StandoutCard(media: Map<String, dynamic>.from(standout), account: state.accountById(standout['account_id'] as String?))
        else
          const _MutedText(T.todayNoStandout),
        const SectionTitle(T.todayTrends),
        if (trends.isEmpty) const _MutedText(T.todayNoTrends) else for (final t in trends) TrendCard(trend: t),
        const SectionTitle(T.todayInProgress),
        if (inProgress.isEmpty)
          const _MutedText(T.todayNoInProgress)
        else
          for (final i in inProgress)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s),
              child: Card(
                child: ListTile(
                  title: Text(i.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: AccountTag(state.accountById(i.accountId)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => IdeaDetailScreen(ideaId: i.id))),
                ),
              ),
            ),
      ],
    );
  }

  void _openAccounts(BuildContext context) => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const AccountsScreen()));
}

class _MutedText extends StatelessWidget {
  const _MutedText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant));
  }
}

/// Kachel eines Accounts: Reichweite und Interaktionen der letzten 7 Tage
/// mit Veränderung zur Vorwoche und Follower-Saldo.
class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.account, required this.summary});
  final Account account;
  final Map<String, dynamic>? summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totals = Map<String, dynamic>.from(summary?['totals'] as Map? ?? const {});
    final previous = Map<String, dynamic>.from(summary?['previous'] as Map? ?? const {});
    final missing = [for (final m in (summary?['missing'] as List? ?? const [])) (m as Map)['text'] as String];
    final delta = summary?['follower_delta'] as int?;
    final color = colorFromHex(account.color);

    Widget metric(String label, String key) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          Text(
            totals[key] == null ? T.noData : formatCompact(totals[key] as num),
            style: totals[key] == null
                ? theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)
                : theme.textTheme.titleMedium,
          ),
          ChangeBadge(percentChange(totals[key] as num?, previous[key] as num?), label: T.vsPrevWeek),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => AppScope.read(context).setActiveAccount(account.id),
          child: Container(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: color, width: 5)),
            ),
            padding: const EdgeInsets.all(AppSpacing.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AccountAvatar(account, size: 32),
                    const SizedBox(width: AppSpacing.s),
                    Expanded(
                      child: Text('@${account.username}', style: theme.textTheme.titleSmall, overflow: TextOverflow.ellipsis),
                    ),
                    if (!account.isManual) DataStamp(parseDate(summary?['fetched_at'])),
                  ],
                ),
                const SizedBox(height: AppSpacing.m),
                if (account.isManual)
                  const _MutedText(T.statusManual)
                else ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      metric(T.reach, 'reach'),
                      metric(T.interactions, 'total_interactions'),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(T.followerBalance, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                            Text(
                              delta == null ? T.noData : '${delta > 0 ? '+' : ''}${formatNumber(delta)}',
                              style: delta == null
                                  ? theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)
                                  : theme.textTheme.titleMedium?.copyWith(color: delta < 0 ? AppColors.negative : null),
                            ),
                            Text(
                              '${formatCompact(account.followers)} ${T.followers}',
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // Fehlende Daten werden begründet statt als 0 gezeigt.
                  for (final m in missing)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.s),
                      child: Text(m, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StandoutCard extends StatelessWidget {
  const _StandoutCard({required this.media, required this.account});
  final Map<String, dynamic> media;
  final Account? account;

  @override
  Widget build(BuildContext context) {
    final reach = media['reach'] as num?;
    final median = media['median'] as num?;
    final factor = (reach != null && median != null && median > 0) ? (reach / median).toStringAsFixed(1).replaceAll('.', ',') : null;
    return Card(
      child: ListTile(
        leading: MediaThumb(media['thumbnail_url'] as String?),
        title: Text(
          (media['caption'] as String?)?.replaceAll('\n', ' ') ?? mediaFormatLabel(media),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AccountTag(account),
            Text('${T.reach}: ${formatCompact(reach)}${factor == null ? '' : ' · ${T.standoutFactor(factor)}'}'),
          ],
        ),
        isThreeLine: true,
        onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => MediaDetailScreen(mediaId: media['id'] as String))),
      ),
    );
  }
}

/// Liste der Benachrichtigungen (in der App).
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.read(context);
    return Scaffold(
      appBar: AppBar(title: const Text(T.notifications)),
      body: AsyncView<List<dynamic>>(
        load: () async {
          final list = await state.api.get('/api/notifications') as List;
          // Beim Öffnen gelten alle als gelesen.
          await state.api.post('/api/notifications/read');
          await state.refreshNotifications();
          return list;
        },
        builder: (context, list, reload) => PageList(
          onRefresh: reload,
          children: [
            const Notice(T.pushNote),
            if (list.isEmpty) const EmptyView(text: T.noNotifications, icon: Icons.notifications_none),
            for (final n in list.cast<Map>())
              Card(
                margin: const EdgeInsets.only(bottom: AppSpacing.s),
                child: ListTile(
                  leading: Icon(switch (n['kind']) {
                    'publish_failed' => Icons.error_outline,
                    'new_comments' => Icons.mode_comment_outlined,
                    'weekly_summary' => Icons.insights,
                    _ => Icons.link_off,
                  }),
                  title: Text(n['title'] as String),
                  subtitle: Text(
                    [if ((n['body'] as String).isNotEmpty) n['body'] as String, formatDateTime(parseDate(n['created_at']))].join('\n'),
                  ),
                  trailing: AccountTag(state.accountById(n['account_id'] as String?)).account == null
                      ? null
                      : SizedBox(width: 90, child: AccountTag(state.accountById(n['account_id'] as String?))),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
