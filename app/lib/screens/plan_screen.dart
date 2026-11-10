import 'package:flutter/material.dart';

import '../config/app_texts.dart';
import '../config/app_theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/account_switcher.dart';
import '../widgets/common.dart';
import 'calendar_view.dart';
import 'idea_detail_screen.dart';
import 'quick_idea_sheet.dart';

/// Tab „Planen“: Ideen (Liste, Kanban) und Redaktionskalender.
class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key});

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  bool _calendar = false;
  bool _board = false;
  final _search = TextEditingController();
  IdeaFilter _filter = const IdeaFilter();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  IdeaFilter _with({
    String? query,
    Object? nicheId = _keep,
    Object? format = _keep,
    Object? status = _keep,
    Object? tag = _keep,
    bool? sortByPlanned,
  }) => IdeaFilter(
    query: query ?? _filter.query,
    nicheId: nicheId == _keep ? _filter.nicheId : nicheId as String?,
    format: format == _keep ? _filter.format : format as String?,
    status: status == _keep ? _filter.status : status as String?,
    tag: tag == _keep ? _filter.tag : tag as String?,
    sortByPlanned: sortByPlanned ?? _filter.sortByPlanned,
  );
  static const _keep = Object();

  Future<void> _openFilters(AppState state) async {
    final tags = {for (final i in state.ideas) ...i.tags}.toList()..sort();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          void apply(IdeaFilter f) {
            setState(() => _filter = f);
            setSheet(() {});
          }

          Widget dropdown(String label, String? value, Map<String, String> options, void Function(String?) onChanged) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.m),
            child: DropdownButtonFormField<String?>(
              key: ValueKey('$label-$value'),
              initialValue: options.containsKey(value) ? value : null,
              isExpanded: true,
              decoration: InputDecoration(labelText: label),
              items: [
                const DropdownMenuItem(value: null, child: Text(T.all)),
                for (final e in options.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: onChanged,
            ),
          );

          return Padding(
            padding: EdgeInsets.fromLTRB(AppSpacing.l, 0, AppSpacing.l, MediaQuery.viewInsetsOf(context).bottom + AppSpacing.l),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(T.filters, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: AppSpacing.m),
                  dropdown(T.niche, _filter.nicheId, {for (final n in state.niches) n.id: n.name}, (v) => apply(_with(nicheId: v))),
                  dropdown(T.format, _filter.format, {for (final f in Idea.formats) f: formatLabel(f)}, (v) => apply(_with(format: v))),
                  dropdown(T.status, _filter.status, {for (final s in Idea.statuses) s: statusLabel(s)}, (v) => apply(_with(status: v))),
                  dropdown(T.tags, _filter.tag, {for (final t in tags) t: t}, (v) => apply(_with(tag: v))),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text(T.sortUpdated)),
                      ButtonSegment(value: true, label: Text(T.sortPlanned)),
                    ],
                    selected: {_filter.sortByPlanned},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => apply(_with(sortByPlanned: s.first)),
                  ),
                  const SizedBox(height: AppSpacing.m),
                  TextButton(
                    onPressed: () => apply(IdeaFilter(query: _filter.query, sortByPlanned: _filter.sortByPlanned)),
                    child: const Text(T.filterReset),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    // Der Account-Filter folgt dem aktiven Account der Kopfzeile.
    final filter = IdeaFilter(
      query: _filter.query,
      accountId: state.activeAccountId,
      nicheId: _filter.nicheId,
      format: _filter.format,
      status: _filter.status,
      tag: _filter.tag,
      sortByPlanned: _filter.sortByPlanned,
    );
    final ideas = filter.apply(state.ideas);
    return Scaffold(
      appBar: const AccountHeader(title: T.tabPlan),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'plan-fab',
        onPressed: () => showQuickIdea(context),
        icon: const Icon(Icons.add),
        label: const Text(T.quickIdea),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.m, AppSpacing.l, AppSpacing.s),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, icon: Icon(Icons.lightbulb_outline), label: Text(T.ideas)),
                ButtonSegment(value: true, icon: Icon(Icons.calendar_month_outlined), label: Text(T.calendar)),
              ],
              selected: {_calendar},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _calendar = s.first),
            ),
          ),
          if (_calendar)
            Expanded(
              child: CalendarView(key: ValueKey('cal-${state.activeAccountId}'), accountId: state.activeAccountId),
            )
          else ...[
            ContentWidth(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _search,
                        decoration: InputDecoration(
                          hintText: T.searchIdeas,
                          prefixIcon: const Icon(Icons.search),
                          isDense: true,
                          suffixIcon: _filter.query.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: T.close,
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _search.clear();
                                    setState(() => _filter = _with(query: ''));
                                  },
                                ),
                        ),
                        onChanged: (v) => setState(() => _filter = _with(query: v)),
                      ),
                    ),
                    IconButton(
                      tooltip: T.filters,
                      onPressed: () => _openFilters(state),
                      icon: Badge(
                        isLabelVisible: filter.activeCount > 0,
                        label: Text('${filter.activeCount}'),
                        child: const Icon(Icons.filter_list),
                      ),
                    ),
                    IconButton(
                      tooltip: _board ? T.viewList : T.viewBoard,
                      onPressed: () => setState(() => _board = !_board),
                      icon: Icon(_board ? Icons.view_list : Icons.view_kanban_outlined),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: state.ideas.isEmpty
                  ? const EmptyView(text: T.ideasEmpty, icon: Icons.lightbulb_outline)
                  : ideas.isEmpty
                  ? const EmptyView(text: T.ideasNoMatch, icon: Icons.search_off)
                  : _board
                  ? _IdeaBoard(ideas: ideas)
                  : PageList(
                      onRefresh: state.refreshIdeas,
                      bottomSpace: true,
                      children: [for (final i in ideas) IdeaCard(idea: i)],
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

Color ideaStatusColor(String status) => switch (status) {
  'in_progress' => AppColors.warning,
  'ready' => AppColors.positive,
  'published' => AppColors.brand,
  'discarded' => AppColors.negative,
  _ => const Color(0xFF6B7280),
};

/// Karte einer Idee in Liste und Kanban.
class IdeaCard extends StatelessWidget {
  const IdeaCard({super.key, required this.idea, this.showStatus = true});
  final Idea idea;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = AppScope.of(context);
    final account = state.accountById(idea.accountId);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.s),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => IdeaDetailScreen(ideaId: idea.id))),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      idea.title.isEmpty ? T.untitled : idea.title,
                      style: theme.textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (showStatus) ...[
                    const SizedBox(width: AppSpacing.s),
                    Pill(statusLabel(idea.status), color: ideaStatusColor(idea.status)),
                  ],
                ],
              ),
              if (idea.note.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    idea.note,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              const SizedBox(height: AppSpacing.s),
              Wrap(
                spacing: AppSpacing.s,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (account != null) AccountTag(account),
                  if (idea.format != null) Pill(formatLabel(idea.format)),
                  if (idea.plannedFor != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.event, size: 14),
                        const SizedBox(width: 2),
                        Text(formatDayShort(idea.plannedFor!), style: theme.textTheme.bodySmall),
                      ],
                    ),
                  for (final t in idea.tags.take(3))
                    Text('#$t', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kanban nach Status. Karten lassen sich in eine andere Spalte ziehen.
class _IdeaBoard extends StatelessWidget {
  const _IdeaBoard({required this.ideas});
  final List<Idea> ideas;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = AppScope.read(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.s, AppSpacing.l, 0),
          child: Text(T.boardDragHint, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
        Expanded(
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.s, AppSpacing.l, 96),
            children: [
              for (final status in Idea.statuses)
                DragTarget<Idea>(
                  onWillAcceptWithDetails: (d) => d.data.status != status,
                  onAcceptWithDetails: (d) => guarded(context, () => state.updateIdea(d.data.id, {'status': status})),
                  builder: (context, candidates, _) {
                    final items = ideas.where((i) => i.status == status).toList();
                    return Container(
                      width: 270,
                      margin: const EdgeInsets.only(right: AppSpacing.m),
                      padding: const EdgeInsets.all(AppSpacing.s),
                      decoration: BoxDecoration(
                        color: candidates.isNotEmpty
                            ? theme.colorScheme.primaryContainer
                            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(AppSpacing.radius),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(AppSpacing.s),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(color: ideaStatusColor(status), shape: BoxShape.circle),
                                ),
                                const SizedBox(width: AppSpacing.s),
                                Expanded(child: Text(statusLabel(status), style: theme.textTheme.titleSmall)),
                                Text('${items.length}', style: theme.textTheme.bodySmall),
                              ],
                            ),
                          ),
                          Expanded(
                            child: items.isEmpty
                                ? Center(child: Text(T.columnEmpty, style: theme.textTheme.bodySmall))
                                : ListView(
                                    children: [
                                      for (final i in items)
                                        LongPressDraggable<Idea>(
                                          data: i,
                                          delay: const Duration(milliseconds: 250),
                                          feedback: SizedBox(
                                            width: 250,
                                            child: Opacity(
                                              opacity: 0.9,
                                              child: AppScope(
                                                state: state,
                                                child: IdeaCard(idea: i, showStatus: false),
                                              ),
                                            ),
                                          ),
                                          childWhenDragging: Opacity(opacity: 0.3, child: IdeaCard(idea: i, showStatus: false)),
                                          child: IdeaCard(idea: i, showStatus: false),
                                        ),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}
