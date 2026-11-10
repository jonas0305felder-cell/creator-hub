import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../config/app_texts.dart';
import '../config/app_theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/account_switcher.dart';
import '../widgets/common.dart';
import 'quick_idea_sheet.dart';
import 'stats_detail_screens.dart';

typedef _TrendData = ({List<Trend> trends, List<TrendSource> sources});

Future<_TrendData> _loadTrends(AppState state) async {
  final data = await state.api.get('/api/trends') as Map;
  return (
    trends: [for (final t in data['trends'] as List) Trend.fromJson(Map<String, dynamic>.from(t as Map))],
    sources: [for (final s in data['sources'] as List) TrendSource.fromJson(Map<String, dynamic>.from(s as Map))],
  );
}

String _sourceTypeLabel(String type) => switch (type) {
  'rss' => 'RSS',
  'hashtag' => T.hashtags,
  _ => T.sourceManual,
};

/// Tab „Trends“: Signale aus eigenen Quellen, gefiltert nach Nische.
class TrendsScreen extends StatefulWidget {
  const TrendsScreen({super.key});

  @override
  State<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends State<TrendsScreen> {
  final _view = GlobalKey<AsyncViewState<_TrendData>>();
  String? _nicheId;
  String? _sourceType;
  int? _periodDays;

  Future<void> _reload() async => _view.currentState?.reload();

  Future<void> _push(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen));
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final account = state.activeAccount;
    // Nischen des aktiven Kontexts stehen als Filter zur Wahl.
    final niches = [for (final id in state.contextNicheIds) state.nicheById(id)].nonNulls.toList();
    final nicheId = niches.any((n) => n.id == _nicheId) ? _nicheId : null;
    return Scaffold(
      appBar: AccountHeader(
        title: T.tabTrends,
        actions: [
          if (AppConfig.featureHashtags || account != null)
            IconButton(
              tooltip: T.watchedHashtags,
              icon: const Icon(Icons.tag),
              onPressed: () => _push(HashtagsScreen(account: account)),
            ),
          IconButton(tooltip: T.sourcesTitle, icon: const Icon(Icons.rss_feed), onPressed: () => _push(const SourcesScreen())),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'trends-fab',
        onPressed: () async {
          if (state.niches.isEmpty) {
            showMessage(context, T.trendsNoNiches);
            return;
          }
          final saved = await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (_) => _TrendForm(initialNicheId: nicheId ?? account?.primaryNicheId),
          );
          if (saved == true) await _reload();
        },
        icon: const Icon(Icons.add),
        label: const Text(T.trendAdd),
      ),
      body: AsyncView<_TrendData>(
        key: _view,
        load: () => _loadTrends(state),
        builder: (context, data, reload) {
          final now = DateTime.now();
          final allowed = account?.nicheIds.toSet();
          final trends = data.trends.where((t) {
            // Im Account-Kontext nur Trends seiner Nischen (und nicht zugeordnete).
            if (allowed != null && t.nicheIds.isNotEmpty && !t.nicheIds.any(allowed.contains)) return false;
            if (nicheId != null && !t.nicheIds.contains(nicheId)) return false;
            if (_sourceType != null && t.sourceType != _sourceType) return false;
            if (_periodDays != null && now.difference(t.date).inDays > _periodDays!) return false;
            return true;
          }).toList();
          final disturbed = data.sources.where((s) => s.isDisturbed).toList();
          return PageList(
            onRefresh: reload,
            bottomSpace: true,
            children: [
              if (niches.isNotEmpty)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final n in niches)
                        Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.s),
                          child: FilterChip(
                            label: Text(n.name),
                            selected: nicheId == n.id,
                            onSelected: (on) => setState(() => _nicheId = on ? n.id : null),
                          ),
                        ),
                    ],
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      initialValue: _sourceType,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: T.filterSource, isDense: true),
                      items: [
                        const DropdownMenuItem(value: null, child: Text(T.all)),
                        for (final type in const ['manual', 'rss', 'hashtag'])
                          DropdownMenuItem(value: type, child: Text(_sourceTypeLabel(type))),
                      ],
                      onChanged: (v) => setState(() => _sourceType = v),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.m),
                  Expanded(
                    child: DropdownButtonFormField<int?>(
                      initialValue: _periodDays,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: T.filterPeriod, isDense: true),
                      items: const [
                        DropdownMenuItem(value: null, child: Text(T.periodAll)),
                        DropdownMenuItem(value: 7, child: Text(T.period7)),
                        DropdownMenuItem(value: 30, child: Text(T.period30)),
                      ],
                      onChanged: (v) => setState(() => _periodDays = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.m),
              // Gestörte Quelle: Zeitpunkt des letzten erfolgreichen Abrufs zeigen.
              for (final s in disturbed)
                Notice(
                  s.lastSuccessAt == null ? T.sourceNeverSucceeded(s.name) : T.sourceLastSuccess(s.name, formatDateTime(s.lastSuccessAt)),
                  icon: Icons.warning_amber,
                  color: AppColors.warning,
                ),
              if (trends.isEmpty) EmptyView(text: state.niches.isEmpty ? T.trendsNoNiches : T.trendsEmpty, icon: Icons.trending_up),
              for (final t in trends) TrendCard(trend: t, onChanged: reload),
            ],
          );
        },
      ),
    );
  }
}

Color _freshnessColor(Freshness f) => switch (f) {
  Freshness.fresh => AppColors.positive,
  Freshness.older => AppColors.warning,
  Freshness.stale => AppColors.negative,
};

String _freshnessLabel(Freshness f) => switch (f) {
  Freshness.fresh => T.freshnessFresh,
  Freshness.older => T.freshnessOlder,
  Freshness.stale => T.freshnessStale,
};

/// Trendkarte mit Quelle, Datum, Frische und Begründung.
class TrendCard extends StatelessWidget {
  const TrendCard({super.key, required this.trend, this.onChanged});
  final Trend trend;
  final Future<void> Function()? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = AppScope.of(context);
    final freshness = trend.freshness(DateTime.now());
    final niches = [for (final id in trend.nicheIds) state.nicheById(id)?.name].nonNulls.join(', ');
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.s),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => TrendDetailScreen(trend: trend)));
          await onChanged?.call();
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(trend.title, style: theme.textTheme.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: AppSpacing.s),
                  Pill(_freshnessLabel(freshness), color: _freshnessColor(freshness)),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                [trend.sourceName, formatDate(trend.date), if (niches.isNotEmpty) niches].join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (trend.reason.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.s),
                Text(trend.reason, maxLines: 3, overflow: TextOverflow.ellipsis),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class TrendDetailScreen extends StatelessWidget {
  const TrendDetailScreen({super.key, required this.trend});
  final Trend trend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = AppScope.of(context);
    final freshness = trend.freshness(DateTime.now());
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text(T.trendDetail),
        actions: [
          if (trend.sourceType == 'manual')
            IconButton(
              tooltip: T.delete,
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (!await confirm(context, title: T.delete, text: trend.title, action: T.delete, danger: true) || !context.mounted) return;
                final ok = await guarded(context, () => state.api.delete('/api/trends/${trend.id}'));
                if (ok && context.mounted) Navigator.pop(context);
              },
            ),
        ],
      ),
      body: PageList(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(trend.title, style: theme.textTheme.titleLarge)),
              const SizedBox(width: AppSpacing.s),
              Pill(_freshnessLabel(freshness), color: _freshnessColor(freshness)),
            ],
          ),
          const SizedBox(height: AppSpacing.m),
          if (trend.reason.isNotEmpty) ...[Text(trend.reason, style: theme.textTheme.bodyLarge), const SizedBox(height: AppSpacing.m)],
          if (trend.summary.isNotEmpty) ...[Text(trend.summary), const SizedBox(height: AppSpacing.m)],
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.m, AppSpacing.m, AppSpacing.m, AppSpacing.xs),
              child: Column(
                children: [
                  row(T.trendSource, [trend.sourceName, if (trend.createdByName != null) trend.createdByName!].join(' · ')),
                  if (trend.publishedAt != null) row(T.trendPublished, formatDateTime(trend.publishedAt)),
                  row(T.trendFetched, formatDateTime(trend.fetchedAt)),
                  if (trend.signalValue != null) row(T.trendSignal, '${formatNumber(trend.signalValue)} ${trend.signalUnit ?? ''}'.trim()),
                  if (trend.nicheIds.isNotEmpty)
                    row(T.trendNiches, [for (final id in trend.nicheIds) state.nicheById(id)?.name].nonNulls.join(', ')),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.l),
          Wrap(
            spacing: AppSpacing.s,
            runSpacing: AppSpacing.s,
            children: [
              FilledButton.icon(
                onPressed: () async {
                  // Die Idee übernimmt Titel, Verweis auf den Trend und die Nische.
                  final contextNiches = state.contextNicheIds;
                  final idea = await showQuickIdea(
                    context,
                    prefill: {
                      'title': trend.title,
                      'source_trend_id': trend.id,
                      'niche_id': trend.nicheIds.where(contextNiches.contains).firstOrNull ?? trend.nicheIds.firstOrNull,
                    },
                  );
                  if (idea != null && context.mounted) showMessage(context, T.savedAsIdea);
                },
                icon: const Icon(Icons.lightbulb_outline, size: 18),
                label: const Text(T.saveAsIdea),
              ),
              if (trend.sourceUrl != null)
                OutlinedButton.icon(
                  onPressed: () => openLink(context, trend.sourceUrl),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text(T.trendOpenSource),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.s),
                  child: Text(T.trendNoLink, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Formular für eine eigene Beobachtung.
class _TrendForm extends StatefulWidget {
  const _TrendForm({this.initialNicheId});
  final String? initialNicheId;

  @override
  State<_TrendForm> createState() => _TrendFormState();
}

class _TrendFormState extends State<_TrendForm> {
  final _title = TextEditingController();
  final _reason = TextEditingController();
  final _summary = TextEditingController();
  final _link = TextEditingController();
  late final Set<String> _niches = {?widget.initialNicheId};
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_title, _reason, _summary, _link]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || _reason.text.trim().isEmpty) {
      showMessage(context, T.requiredFields);
      return;
    }
    setState(() => _busy = true);
    final state = AppScope.read(context);
    final ok = await guarded(
      context,
      () => state.api.post('/api/trends', {
        'title': _title.text.trim(),
        'reason': _reason.text.trim(),
        'summary': _summary.text.trim(),
        'source_url': _link.text.trim(),
        'niche_ids': _niches.toList(),
      }),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpacing.l, 0, AppSpacing.l, MediaQuery.viewInsetsOf(context).bottom + AppSpacing.l),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(T.trendAdd, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.m),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: T.trendTitle),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpacing.m),
            TextField(
              controller: _reason,
              decoration: const InputDecoration(labelText: T.trendReason),
              minLines: 2,
              maxLines: 4,
            ),
            const SizedBox(height: AppSpacing.m),
            TextField(
              controller: _summary,
              decoration: const InputDecoration(labelText: T.trendSummary),
              minLines: 1,
              maxLines: 4,
            ),
            const SizedBox(height: AppSpacing.m),
            TextField(
              controller: _link,
              decoration: const InputDecoration(labelText: T.trendLink),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: AppSpacing.m),
            Text(T.trendNiches, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.s,
              children: [
                for (final n in state.niches)
                  FilterChip(
                    label: Text(n.name),
                    selected: _niches.contains(n.id),
                    onSelected: (on) => setState(() => on ? _niches.add(n.id) : _niches.remove(n.id)),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.l),
            FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? T.saving : T.save)),
          ],
        ),
      ),
    );
  }
}

/// Trendquellen: RSS-Feeds je Nische mit Zustand des letzten Abrufs.
class SourcesScreen extends StatelessWidget {
  const SourcesScreen({super.key});

  Future<void> _add(BuildContext context, Future<void> Function() reload) async {
    final state = AppScope.read(context);
    if (state.niches.isEmpty) {
      showMessage(context, T.trendsNoNiches);
      return;
    }
    final name = TextEditingController();
    final url = TextEditingController();
    String nicheId = state.niches.first.id;
    final fields = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text(T.sourceAddRss),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: T.sourceName),
                ),
                const SizedBox(height: AppSpacing.m),
                TextField(
                  controller: url,
                  decoration: const InputDecoration(labelText: T.sourceUrl),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: AppSpacing.m),
                DropdownButtonFormField<String>(
                  initialValue: nicheId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: T.sourceNiche),
                  items: [for (final n in state.niches) DropdownMenuItem(value: n.id, child: Text(n.name))],
                  onChanged: (v) => setState(() => nicheId = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text(T.cancel)),
            FilledButton(
              onPressed: () => Navigator.pop(context, {'name': name.text.trim(), 'url': url.text.trim(), 'niche_id': nicheId}),
              child: const Text(T.add),
            ),
          ],
        ),
      ),
    );
    if (fields == null || !context.mounted) return;
    await guarded(context, () => state.api.post('/api/trend-sources', fields, true));
    await reload();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(T.sourcesTitle)),
      body: AsyncView<_TrendData>(
        load: () => _loadTrends(state),
        builder: (context, data, reload) {
          final rss = data.sources.where((s) => s.type == 'rss').toList();
          return PageList(
            onRefresh: reload,
            children: [
              Text(T.sourceRssNote, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: AppSpacing.m),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: () => _add(context, reload),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text(T.sourceAddRss),
                ),
              ),
              const SizedBox(height: AppSpacing.m),
              if (rss.isEmpty) const EmptyView(text: T.sourcesEmpty, icon: Icons.rss_feed),
              for (final s in rss)
                Card(
                  margin: const EdgeInsets.only(bottom: AppSpacing.s),
                  child: ListTile(
                    leading: Icon(s.isDisturbed ? Icons.warning_amber : Icons.rss_feed, color: s.isDisturbed ? AppColors.warning : null),
                    title: Text(s.name),
                    subtitle: Text(
                      [
                        state.nicheById(s.nicheId)?.name ?? T.noNiche,
                        s.lastSuccessAt == null
                            ? T.sourceNeverSucceeded(s.name)
                            : T.sourceLastSuccess(s.name, formatDateTime(s.lastSuccessAt)),
                        if (s.isDisturbed) T.sourceError(s.lastError!),
                      ].join('\n'),
                    ),
                    isThreeLine: true,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: T.refresh,
                          icon: const Icon(Icons.refresh),
                          onPressed: () async {
                            await guarded(context, () => state.api.post('/api/trend-sources/${s.id}/refresh', null, true));
                            await reload();
                          },
                        ),
                        IconButton(
                          tooltip: T.delete,
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            if (!await confirm(context, title: T.delete, text: s.name, action: T.delete, danger: true) ||
                                !context.mounted) {
                              return;
                            }
                            await guarded(context, () => state.api.delete('/api/trend-sources/${s.id}'));
                            await reload();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.m),
              const Notice(T.googleTrendsNote),
            ],
          );
        },
      ),
    );
  }
}

/// Beobachtete Hashtags eines Accounts mit Kontingent-Anzeige.
class HashtagsScreen extends StatelessWidget {
  const HashtagsScreen({super.key, required this.account});
  final Account? account;

  Future<void> _add(BuildContext context, Future<void> Function() reload) async {
    final controller = TextEditingController();
    final tag = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(T.hashtagAdd),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: T.hashtagField, prefixText: '#'),
              onSubmitted: (v) => Navigator.pop(context, v),
            ),
            const SizedBox(height: AppSpacing.m),
            const Text(T.hashtagQuotaWarning),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text(T.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text(T.add)),
        ],
      ),
    );
    if (tag == null || tag.trim().isEmpty || !context.mounted) return;
    final state = AppScope.read(context);
    await guarded(context, () => state.api.post('/api/accounts/${account!.id}/hashtags', {'hashtag': tag.trim()}, true));
    await reload();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.read(context);
    final theme = Theme.of(context);
    final gate = facebookFeatureGate(featureEnabled: AppConfig.featureHashtags, account: account);
    return Scaffold(
      appBar: AppBar(title: Text(account == null ? T.watchedHashtags : '${T.watchedHashtags} · @${account!.username}')),
      body:
          gate ??
          AsyncView<Map<String, dynamic>>(
            load: () async => Map<String, dynamic>.from(await state.api.get('/api/accounts/${account!.id}/hashtags') as Map),
            builder: (context, data, reload) {
              final items = [for (final i in data['items'] as List) Map<String, dynamic>.from(i as Map)];
              final remaining = data['remaining'] as int;
              return PageList(
                onRefresh: reload,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(T.remainingHashtags(remaining, data['quota'] as int), style: theme.textTheme.titleSmall)),
                      FilledButton.icon(
                        onPressed: remaining <= 0 ? null : () => _add(context, reload),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text(T.add),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.m),
                  if (items.isEmpty) const EmptyView(text: T.hashtagsEmpty, icon: Icons.tag),
                  for (final h in items)
                    Card(
                      margin: const EdgeInsets.only(bottom: AppSpacing.s),
                      child: ListTile(
                        leading: const Icon(Icons.tag),
                        title: Text('#${h['hashtag']}'),
                        trailing: IconButton(
                          tooltip: T.delete,
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await guarded(context, () => state.api.delete('/api/hashtags/${h['id']}'));
                            await reload();
                          },
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => _HashtagPostsScreen(id: h['id'] as String, hashtag: h['hashtag'] as String),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
    );
  }
}

/// Top- und aktuelle Beiträge eines Hashtags. Top-Beiträge stehen
/// automatisch in den Trends, aktuelle erst nach „Als Trend übernehmen“.
class _HashtagPostsScreen extends StatelessWidget {
  const _HashtagPostsScreen({required this.id, required this.hashtag});
  final String id;
  final String hashtag;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.read(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('#$hashtag')),
      body: AsyncView<List<dynamic>>(
        load: () async => await state.api.get('/api/hashtags/$id/posts') as List,
        builder: (context, posts, reload) => PageList(
          onRefresh: reload,
          children: [
            if (posts.isEmpty) const EmptyView(text: T.hashtagNoPosts, icon: Icons.tag),
            for (final p in posts.cast<Map>())
              Card(
                margin: const EdgeInsets.only(bottom: AppSpacing.s),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.m),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p['title'] as String, style: theme.textTheme.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        [
                          formatDate(parseDate(p['published_at']) ?? parseDate(p['fetched_at'])),
                          if (p['signal_value'] != null) '${formatCompact(p['signal_value'] as num)} ${p['signal_unit'] ?? ''}'.trim(),
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      if ((p['reason'] as String? ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: Text(p['reason'] as String),
                        ),
                      const SizedBox(height: AppSpacing.s),
                      Wrap(
                        spacing: AppSpacing.s,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (p['listed'] == true)
                            const Pill(T.adopted, color: AppColors.positive)
                          else
                            OutlinedButton(
                              onPressed: () async {
                                await guarded(context, () => state.api.post('/api/trends/${p['id']}/adopt'));
                                await reload();
                              },
                              child: const Text(T.adoptTrend),
                            ),
                          if (p['source_url'] != null)
                            TextButton(
                              onPressed: () => openLink(context, p['source_url'] as String?),
                              child: const Text(T.openOnInstagram),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
