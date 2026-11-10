import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../config/app_texts.dart';
import '../config/app_theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'idea_detail_screen.dart';

typedef _CalendarData = ({List<ScheduledPost> posts, Map<String, Map<String, dynamic>> limits});

enum _Mode { month, week, list }

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Montag der Woche von [d].
DateTime _weekStart(DateTime d) => _day(d).subtract(Duration(days: d.weekday - 1));

IconData postStatusIcon(String status) => switch (status) {
  'published' => Icons.check_circle,
  'failed' => Icons.error,
  'publishing' => Icons.sync,
  'draft' => Icons.edit_calendar_outlined,
  _ => Icons.schedule,
};

/// Redaktionskalender: Monat, Woche, Liste. Einträge in Account-Farbe,
/// Verschieben per Ziehen auf einen anderen Tag.
class CalendarView extends StatefulWidget {
  const CalendarView({super.key, this.accountId});

  /// Filter nach Account; `null` zeigt alle.
  final String? accountId;

  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
  final _view = GlobalKey<AsyncViewState<_CalendarData>>();
  _Mode _mode = _Mode.month;
  DateTime _anchor = _day(DateTime.now());

  Future<_CalendarData> _load() async {
    final state = AppScope.read(context);
    final raw = await state.api.get('/api/posts') as List;
    final posts = [for (final p in raw) ScheduledPost.fromJson(Map<String, dynamic>.from(p as Map))];
    // Verbleibendes Tageslimit je verbundenem Account.
    final accounts = state.accounts.where((a) => a.canPublish && (widget.accountId == null || a.id == widget.accountId));
    final limits = <String, Map<String, dynamic>>{};
    if (AppConfig.featurePublishing) {
      await Future.wait([
        for (final a in accounts)
          state.api
              .get('/api/accounts/${a.id}/publish-limit')
              .then((l) => limits[a.id] = Map<String, dynamic>.from(l as Map))
              .catchError((Object _) => <String, dynamic>{}),
      ]);
    }
    return (posts: posts, limits: limits);
  }

  Future<void> _move(ScheduledPost post, DateTime day) async {
    if (!post.canMove || _sameDay(post.scheduledFor, day)) return;
    final state = AppScope.read(context);
    final target = moveToDay(post.scheduledFor, day);
    await guarded(
      context,
      () => state.api.patch('/api/posts/${post.id}', {'scheduled_for': target.toUtc().toIso8601String()}),
      success: T.postMoved,
    );
    await _view.currentState?.reload();
  }

  void _shift(int direction) => setState(() {
    _anchor = switch (_mode) {
      _Mode.week => _anchor.add(Duration(days: 7 * direction)),
      _ => DateTime(_anchor.year, _anchor.month + direction, 1),
    };
  });

  Future<void> _open(ScheduledPost post) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _PostSheet(post: post),
    );
    await _view.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final title = _mode == _Mode.week
        ? '${formatDayShort(_weekStart(_anchor))} – ${formatDayShort(_weekStart(_anchor).add(const Duration(days: 6)))}'
        : formatMonth(_anchor);
    return AsyncView<_CalendarData>(
      key: _view,
      load: _load,
      builder: (context, data, reload) {
        final posts = data.posts.where((p) => widget.accountId == null || p.accountId == widget.accountId).toList();
        List<ScheduledPost> on(DateTime day) => posts.where((p) => _sameDay(p.scheduledFor, day)).toList();
        return ContentWidth(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: MaterialLocalizations.of(context).previousPageTooltip,
                      onPressed: () => _shift(-1),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
                    ),
                    IconButton(
                      tooltip: MaterialLocalizations.of(context).nextPageTooltip,
                      onPressed: () => _shift(1),
                      icon: const Icon(Icons.chevron_right),
                    ),
                    TextButton(onPressed: () => setState(() => _anchor = _day(DateTime.now())), child: const Text(T.today)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
                child: SegmentedButton<_Mode>(
                  segments: const [
                    ButtonSegment(value: _Mode.month, label: Text(T.calMonth)),
                    ButtonSegment(value: _Mode.week, label: Text(T.calWeek)),
                    ButtonSegment(value: _Mode.list, label: Text(T.calList)),
                  ],
                  selected: {_mode},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _mode = s.first),
                ),
              ),
              if (data.limits.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.s, AppSpacing.l, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: AppSpacing.m,
                      runSpacing: AppSpacing.xs,
                      children: [
                        for (final e in data.limits.entries)
                          Text(
                            '@${state.accountById(e.key)?.username ?? ''}: ${limitText(e.value)}',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.s),
              Expanded(
                child: switch (_mode) {
                  _Mode.month => _MonthGrid(anchor: _anchor, postsOn: on, onMove: _move, onOpen: _open),
                  _Mode.week => _WeekList(start: _weekStart(_anchor), postsOn: on, onMove: _move, onOpen: _open, onRefresh: reload),
                  _Mode.list => _MonthList(
                    posts: posts.where((p) => p.scheduledFor.year == _anchor.year && p.scheduledFor.month == _anchor.month).toList(),
                    onOpen: _open,
                    onRefresh: reload,
                  ),
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Text zum Tageslimit eines Accounts (Antwort von `/publish-limit`).
String limitText(Map<String, dynamic> limit) => limit['limit'] == null
    ? T.limitUnknown(limit['used'] as int? ?? 0)
    : T.limitRemaining(limit['remaining'] as int, limit['limit'] as int);

/// Kleiner Eintrag in Account-Farbe; lässt sich ziehen.
class _PostChip extends StatelessWidget {
  const _PostChip({required this.post, required this.onOpen, this.compact = false});
  final ScheduledPost post;
  final void Function(ScheduledPost) onOpen;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.read(context);
    final color = colorFromHex(state.accountById(post.accountId)?.color);
    final chip = Material(
      color: post.status == 'draft' ? color.withValues(alpha: 0.55) : color,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => onOpen(post),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 3 : AppSpacing.s, vertical: compact ? 1 : AppSpacing.xs),
          child: Row(
            children: [
              Icon(postStatusIcon(post.status), size: compact ? 10 : 14, color: onColor(color)),
              SizedBox(width: compact ? 2 : AppSpacing.xs),
              Expanded(
                child: Text(
                  compact ? post.label(T.untitled) : '${formatTime(post.scheduledFor)}  ${post.label(T.untitled)}',
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  softWrap: false,
                  style: TextStyle(fontSize: compact ? 10 : 13, color: onColor(color)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final semantic = Semantics(
      label: '${postStatusLabel(post.status)}, ${formatDateTime(post.scheduledFor)}, ${post.label(T.untitled)}',
      child: chip,
    );
    if (!post.canMove) return semantic;
    return LongPressDraggable<ScheduledPost>(
      data: post,
      delay: const Duration(milliseconds: 250),
      feedback: SizedBox(
        width: 160,
        child: Opacity(
          opacity: 0.9,
          child: AppScope(
            state: state,
            child: _PostChip(post: post, onOpen: (_) {}),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: chip),
      child: semantic,
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.anchor, required this.postsOn, required this.onMove, required this.onOpen});
  final DateTime anchor;
  final List<ScheduledPost> Function(DateTime) postsOn;
  final Future<void> Function(ScheduledPost, DateTime) onMove;
  final void Function(ScheduledPost) onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = _weekStart(DateTime(anchor.year, anchor.month, 1));
    final last = DateTime(anchor.year, anchor.month + 1, 0);
    final weeks = (last.difference(first).inDays ~/ 7) + 1;
    final today = _day(DateTime.now());
    const weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.s, 0, AppSpacing.s, AppSpacing.s),
      child: Column(
        children: [
          Row(
            children: [
              for (final w in weekdays)
                Expanded(
                  child: Center(child: Text(w, style: theme.textTheme.labelSmall)),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          for (var w = 0; w < weeks; w++)
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var d = 0; d < 7; d++)
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          // Über Kalendertage rechnen, damit die Zeitumstellung nichts verschiebt.
                          final day = DateTime(first.year, first.month, first.day + w * 7 + d);
                          final items = postsOn(day);
                          final inMonth = day.month == anchor.month;
                          return DragTarget<ScheduledPost>(
                            onWillAcceptWithDetails: (details) => !_sameDay(details.data.scheduledFor, day),
                            onAcceptWithDetails: (details) => onMove(details.data, day),
                            builder: (context, candidates, _) => Container(
                              margin: const EdgeInsets.all(1),
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: candidates.isNotEmpty
                                    ? theme.colorScheme.primaryContainer
                                    : inMonth
                                    ? theme.colorScheme.surfaceContainerLow
                                    : Colors.transparent,
                                border: Border.all(
                                  color: _sameDay(day, today) ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                                  width: _sameDay(day, today) ? 2 : 0.5,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: LayoutBuilder(
                                builder: (context, box) {
                                  // So viele Einträge zeigen, wie in die Zelle passen.
                                  final fit = ((box.maxHeight - 18) / 17).floor().clamp(0, 6);
                                  final visible = items.length > fit ? (fit - 1).clamp(0, 6) : items.length;
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        '${day.day}',
                                        style: theme.textTheme.labelSmall?.copyWith(color: inMonth ? null : theme.colorScheme.outline),
                                      ),
                                      for (final p in items.take(visible))
                                        Padding(
                                          padding: const EdgeInsets.only(top: 1),
                                          child: _PostChip(post: p, onOpen: onOpen, compact: true),
                                        ),
                                      if (items.length > visible) Text('+${items.length - visible}', style: const TextStyle(fontSize: 10)),
                                    ],
                                  );
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              T.calDragHint,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekList extends StatelessWidget {
  const _WeekList({required this.start, required this.postsOn, required this.onMove, required this.onOpen, required this.onRefresh});
  final DateTime start;
  final List<ScheduledPost> Function(DateTime) postsOn;
  final Future<void> Function(ScheduledPost, DateTime) onMove;
  final void Function(ScheduledPost) onOpen;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = _day(DateTime.now());
    return PageList(
      onRefresh: onRefresh,
      bottomSpace: true,
      children: [
        for (var d = 0; d < 7; d++)
          Builder(
            builder: (context) {
              final day = DateTime(start.year, start.month, start.day + d);
              final items = postsOn(day);
              return DragTarget<ScheduledPost>(
                onWillAcceptWithDetails: (details) => !_sameDay(details.data.scheduledFor, day),
                onAcceptWithDetails: (details) => onMove(details.data, day),
                builder: (context, candidates, _) => Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.s),
                  padding: const EdgeInsets.all(AppSpacing.s),
                  constraints: const BoxConstraints(minHeight: 56),
                  decoration: BoxDecoration(
                    color: candidates.isNotEmpty ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerLow,
                    border: Border.all(
                      color: _sameDay(day, today) ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                      width: _sameDay(day, today) ? 2 : 0.5,
                    ),
                    borderRadius: BorderRadius.circular(AppSpacing.radius),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 84,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(formatWeekday(day), style: theme.textTheme.labelLarge),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final p in items)
                              Padding(
                                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                                child: _PostChip(post: p, onOpen: onOpen),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        Text(T.calDragHint, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _MonthList extends StatelessWidget {
  const _MonthList({required this.posts, required this.onOpen, required this.onRefresh});
  final List<ScheduledPost> posts;
  final void Function(ScheduledPost) onOpen;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return PageList(
      onRefresh: onRefresh,
      bottomSpace: true,
      children: [
        if (posts.isEmpty) const EmptyView(text: T.calEmpty, icon: Icons.calendar_month_outlined),
        for (final p in posts)
          Card(
            margin: const EdgeInsets.only(bottom: AppSpacing.s),
            child: ListTile(
              leading: Icon(
                postStatusIcon(p.status),
                color: p.status == 'failed' ? AppColors.negative : colorFromHex(state.accountById(p.accountId)?.color),
              ),
              title: Text(p.label(T.untitled), maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${formatWeekday(p.scheduledFor)} ${formatTime(p.scheduledFor)} · ${postStatusLabel(p.status)} · @${state.accountById(p.accountId)?.username ?? ''}',
              ),
              onTap: () => onOpen(p),
            ),
          ),
      ],
    );
  }
}

/// Details eines Kalendereintrags mit Aktionen.
class _PostSheet extends StatelessWidget {
  const _PostSheet({required this.post});
  final ScheduledPost post;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.read(context);
    final theme = Theme.of(context);
    Future<void> run(Future<void> Function() action, {String? success}) async {
      final ok = await guarded(context, action, success: success);
      if (ok && context.mounted) Navigator.pop(context);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.l, 0, AppSpacing.l, AppSpacing.l),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(post.label(T.untitled), style: theme.textTheme.titleLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: AppSpacing.s),
            Wrap(
              spacing: AppSpacing.s,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                AccountTag(state.accountById(post.accountId)),
                Pill(
                  postStatusLabel(post.status),
                  color: post.status == 'failed'
                      ? AppColors.negative
                      : post.status == 'published'
                      ? AppColors.positive
                      : null,
                ),
                Pill(formatLabel(post.format)),
                Text(formatDateTime(post.scheduledFor)),
              ],
            ),
            if (post.status == 'draft')
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.s),
                child: Text(T.publishPlanOnlyNote, style: theme.textTheme.bodySmall),
              ),
            if (post.status == 'failed' && post.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.m),
                child: Notice('${T.postReason}: ${post.errorMessage}', icon: Icons.error_outline, color: AppColors.negative),
              ),
            if (post.caption.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.m),
                child: Text(post.caption, maxLines: 8, overflow: TextOverflow.ellipsis),
              ),
            const SizedBox(height: AppSpacing.l),
            Wrap(
              spacing: AppSpacing.s,
              runSpacing: AppSpacing.s,
              children: [
                if (post.status == 'failed')
                  FilledButton.icon(
                    onPressed: () => run(() => state.api.post('/api/posts/${post.id}/retry')),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text(T.postRetry),
                  ),
                if (post.canMove)
                  OutlinedButton.icon(
                    onPressed: () async {
                      final when = await pickDateTime(context, initial: post.scheduledFor, allowPast: post.status == 'draft');
                      if (when == null || !context.mounted) return;
                      await run(
                        () => state.api.patch('/api/posts/${post.id}', {'scheduled_for': when.toUtc().toIso8601String()}),
                        success: T.postMoved,
                      );
                    },
                    icon: const Icon(Icons.event, size: 18),
                    label: const Text(T.postChangeDate),
                  ),
                if (post.permalink != null)
                  OutlinedButton.icon(
                    onPressed: () => openLink(context, post.permalink),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text(T.viewPost),
                  ),
                if (post.caption.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => copyText(context, post.caption),
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text(T.copyCaption),
                  ),
                if (post.ideaId != null && state.ideaById(post.ideaId) != null)
                  OutlinedButton.icon(
                    onPressed: () {
                      final navigator = Navigator.of(context)..pop();
                      navigator.push(MaterialPageRoute<void>(builder: (_) => IdeaDetailScreen(ideaId: post.ideaId!)));
                    },
                    icon: const Icon(Icons.lightbulb_outline, size: 18),
                    label: const Text(T.postOpenIdea),
                  ),
                if (post.status != 'publishing')
                  TextButton.icon(
                    onPressed: () async {
                      if (!await confirm(context, title: T.delete, text: T.postDeleteConfirm, action: T.delete, danger: true) ||
                          !context.mounted) {
                        return;
                      }
                      await run(() => state.api.delete('/api/posts/${post.id}'));
                    },
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text(T.delete),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
