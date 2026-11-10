import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../config/app_texts.dart';
import '../config/app_theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/line_chart.dart';
import 'quick_idea_sheet.dart';

/// Beitragsdetail: Kennzahlen, Vergleich zum Account-Median, Kommentare.
class MediaDetailScreen extends StatelessWidget {
  const MediaDetailScreen({super.key, required this.mediaId});
  final String mediaId;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.read(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(T.mediaDetail)),
      body: AsyncView<Map<String, dynamic>>(
        load: () async => Map<String, dynamic>.from(await state.api.get('/api/media/$mediaId') as Map),
        builder: (context, m, reload) {
          final metrics = Map<String, dynamic>.from(m['metrics'] as Map);
          final medians = Map<String, dynamic>.from(m['medians'] as Map);
          final account = state.accountById(m['account_id'] as String?);
          final isReel = m['media_product_type'] == 'reels';
          final isStory = m['media_product_type'] == 'story';
          final caption = (m['caption'] as String?) ?? '';
          final comments = [for (final c in m['comments'] as List) Map<String, dynamic>.from(c as Map)];

          Widget tile(String label, String key) {
            final value = metrics[key] as num?;
            final median = medians[key] as num?;
            return MetricTile(
              label: label,
              value: value,
              change: isStory ? null : percentChange(value, median),
              sub: (isStory || median == null) ? null : T.medianValue(formatCompact(median.round())),
            );
          }

          return PageList(
            onRefresh: reload,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MediaThumb(m['thumbnail_url'] as String?, size: 96),
                  const SizedBox(width: AppSpacing.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AccountTag(account),
                        const SizedBox(height: AppSpacing.xs),
                        Text('${mediaFormatLabel(m)} · ${formatDateTime(parseDate(m['posted_at']))}', style: theme.textTheme.titleSmall),
                        const SizedBox(height: AppSpacing.xs),
                        DataStamp(parseDate(m['fetched_at'])),
                      ],
                    ),
                  ),
                ],
              ),
              if (caption.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.m),
                  child: Text(caption, maxLines: 6, overflow: TextOverflow.ellipsis),
                ),
              const SizedBox(height: AppSpacing.m),
              Wrap(
                spacing: AppSpacing.s,
                runSpacing: AppSpacing.s,
                children: [
                  FilledButton.icon(
                    onPressed: () async {
                      // Folgeidee übernimmt Account und Verweis auf den Beitrag.
                      final idea = await showQuickIdea(
                        context,
                        prefill: {
                          'title': T.followUpTitle(
                            caption.isEmpty
                                ? mediaFormatLabel(m)
                                : (caption.length > 60 ? '${caption.substring(0, 60)}…' : caption).replaceAll('\n', ' '),
                          ),
                          'account_id': m['account_id'],
                          'source_media_id': m['id'],
                        },
                      );
                      if (idea != null && context.mounted) showMessage(context, T.ideaSaved);
                    },
                    icon: const Icon(Icons.lightbulb_outline, size: 18),
                    label: const Text(T.followUpIdea),
                  ),
                  if (m['permalink'] != null)
                    OutlinedButton.icon(
                      onPressed: () => openLink(context, m['permalink'] as String?),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text(T.openOnInstagram),
                    ),
                ],
              ),
              SectionTitle(isStory ? T.storyStats : T.vsMedian),
              if (metrics.isEmpty) const Notice(T.storyNoValues),
              TileGrid(
                children: [
                  tile(T.reach, 'reach'),
                  tile(T.views, 'views'),
                  if (!isStory) ...[tile(T.likes, 'likes'), tile(T.comments, 'comments'), tile(T.saves, 'saved')],
                  tile(T.shares, 'shares'),
                  if (isStory) ...[
                    tile(T.replies, 'replies'),
                    tile(T.navigation, 'navigation'),
                    tile(T.follows, 'follows'),
                    tile(T.profileVisits, 'profile_visits'),
                  ],
                  if (isReel)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.m),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(T.avgWatchTime, style: theme.textTheme.bodySmall),
                            Text(
                              metrics['ig_reels_avg_watch_time'] == null
                                  ? T.noData
                                  : formatSeconds(metrics['ig_reels_avg_watch_time'] as num),
                              style: theme.textTheme.titleLarge,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.s),
              if (!isStory) Text(T.medianNote, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              if (m['media_type'] == 'CAROUSEL_ALBUM')
                Text(T.carouselNote, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              if (isStory) Text(T.storyOnly24h, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              if (!isStory && AppConfig.featureComments) ...[
                const SectionTitle(T.comments),
                if (comments.where((c) => c['parent_comment_id'] == null).isEmpty)
                  Text(T.commentsEmpty, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                for (final c in comments.where((c) => c['parent_comment_id'] == null))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('@${c['author_username']}', style: theme.textTheme.labelLarge),
                    subtitle: Text(c['text'] as String),
                    trailing: Text(formatAgo(parseDate(c['created_at']) ?? DateTime.now()), style: theme.textTheme.bodySmall),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Gesicherte Story-Werte je Story mit Uhrzeit der letzten Sicherung.
class StoriesScreen extends StatelessWidget {
  const StoriesScreen({super.key, required this.account});
  final Account account;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.read(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('${T.storyStats} · @${account.username}')),
      body: AsyncView<List<dynamic>>(
        load: () async => await state.api.get('/api/accounts/${account.id}/stories') as List,
        builder: (context, list, reload) => PageList(
          onRefresh: reload,
          children: [
            const Notice(T.storyOnly24h),
            if (list.isEmpty) const EmptyView(text: T.storiesEmpty, icon: Icons.amp_stories_outlined),
            for (final s in list.cast<Map>())
              Card(
                margin: const EdgeInsets.only(bottom: AppSpacing.s),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppSpacing.radius),
                  onTap: () =>
                      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => MediaDetailScreen(mediaId: s['id'] as String))),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.m),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MediaThumb(s['thumbnail_url'] as String?),
                        const SizedBox(width: AppSpacing.m),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: Text(formatDateTime(parseDate(s['posted_at'])), style: theme.textTheme.titleSmall)),
                                  if (s['is_live'] == true) const Pill(T.storyLive, color: AppColors.positive),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              if ((s['metrics'] as Map).isEmpty)
                                Text(T.storyNoValues, style: theme.textTheme.bodySmall)
                              else
                                Text(
                                  [
                                    '${T.reach}: ${formatCompact((s['metrics'] as Map)['reach'] as num?)}',
                                    '${T.replies}: ${formatCompact((s['metrics'] as Map)['replies'] as num?)}',
                                    '${T.profileVisits}: ${formatCompact((s['metrics'] as Map)['profile_visits'] as num?)}',
                                  ].join(' · '),
                                ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                s['last_captured_at'] == null
                                    ? T.snapshotNone
                                    : T.lastSaved(formatDateTime(parseDate(s['last_captured_at']))),
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                              ),
                              if (s['saved_in_time'] == false)
                                Padding(
                                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                                  child: Text(T.storyNotSavedInTime, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.warning)),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Erklärt, warum eine Funktion für diesen Account nicht verfügbar ist.
/// Liefert `null`, wenn sie nutzbar ist.
Widget? facebookFeatureGate({required bool featureEnabled, required Account? account}) {
  if (!featureEnabled) return const EmptyView(title: T.featureOffTitle, text: T.featureOff, icon: Icons.lock_clock_outlined);
  if (account == null) return const EmptyView(text: T.needsAccount, icon: Icons.person_search_outlined);
  if (!account.hasFacebookLogin) return const EmptyView(title: T.needsFacebookTitle, text: T.needsFacebook, icon: Icons.link_off);
  return null;
}

/// Öffentliche Kennzahlen anderer professioneller Accounts im Vergleich.
class CompetitorsScreen extends StatelessWidget {
  const CompetitorsScreen({super.key, required this.account});
  final Account account;

  Future<void> _add(BuildContext context, Future<void> Function() reload) async {
    final controller = TextEditingController();
    final username = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(T.competitorAdd),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: T.competitorUsername, prefixText: '@'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text(T.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text(T.add)),
        ],
      ),
    );
    if (username == null || username.trim().isEmpty || !context.mounted) return;
    final state = AppScope.read(context);
    await guarded(context, () => state.api.post('/api/accounts/${account.id}/competitors', {'username': username.trim()}, true));
    await reload();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.read(context);
    final theme = Theme.of(context);
    final gate = facebookFeatureGate(featureEnabled: AppConfig.featureCompetitors, account: account);
    return Scaffold(
      appBar: AppBar(title: Text('${T.competitors} · @${account.username}')),
      body:
          gate ??
          AsyncView<Map<String, dynamic>>(
            load: () async => Map<String, dynamic>.from(await state.api.get('/api/accounts/${account.id}/competitors') as Map),
            builder: (context, data, reload) {
              final items = [for (final i in data['items'] as List) Map<String, dynamic>.from(i as Map)];
              final max = data['max'] as int;
              return PageList(
                onRefresh: reload,
                children: [
                  Text(T.competitorsIntro, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: AppSpacing.m),
                  Row(
                    children: [
                      Expanded(child: Text(T.competitorCount(items.length, max), style: theme.textTheme.titleSmall)),
                      FilledButton.icon(
                        onPressed: items.length >= max ? null : () => _add(context, reload),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text(T.add),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.m),
                  if (items.isEmpty) const EmptyView(text: T.competitorsEmpty, icon: Icons.groups_outlined),
                  for (final c in items)
                    _CompetitorCard(
                      competitor: c,
                      color: colorFromHex(account.color),
                      onRemove: () async {
                        await guarded(context, () => state.api.delete('/api/competitors/${c['id']}'));
                        await reload();
                      },
                    ),
                ],
              );
            },
          ),
    );
  }
}

class _CompetitorCard extends StatelessWidget {
  const _CompetitorCard({required this.competitor, required this.color, required this.onRemove});
  final Map<String, dynamic> competitor;
  final Color color;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snapshots = [for (final s in competitor['snapshots'] as List) Map<String, dynamic>.from(s as Map)];
    final last = snapshots.lastOrNull;
    final points = [
      for (final s in snapshots)
        if (s['followers_count'] != null) ChartPoint(DateTime.parse(s['date'] as String), s['followers_count'] as num),
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.m),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('@${competitor['username']}', style: theme.textTheme.titleMedium)),
                IconButton(tooltip: T.delete, onPressed: onRemove, icon: const Icon(Icons.delete_outline)),
              ],
            ),
            if (last == null)
              Text(
                competitor['last_error'] == null ? T.snapshotNone : T.sourceError(competitor['last_error'] as String),
                style: theme.textTheme.bodySmall,
              )
            else ...[
              DataStamp(parseDate(last['fetched_at'])),
              const SizedBox(height: AppSpacing.s),
              TileGrid(
                minTileWidth: 120,
                children: [
                  MetricTile(label: T.followers, value: last['followers_count'] as num?),
                  MetricTile(label: T.posts, value: last['media_count'] as num?),
                  MetricTile(label: T.avgLikes, value: (last['avg_likes'] as num?)?.round()),
                  MetricTile(label: T.avgComments, value: (last['avg_comments'] as num?)?.round()),
                ],
              ),
              const SizedBox(height: AppSpacing.s),
              LineChart(points: points, color: color, height: 120, semanticLabel: T.statsFollowerChart),
            ],
          ],
        ),
      ),
    );
  }
}
