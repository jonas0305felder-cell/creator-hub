import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../config/app_texts.dart';
import '../config/app_theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'stats_detail_screens.dart';

/// Kommentar-Eingang aller Accounts (folgt dem aktiven Account).
class CommentsScreen extends StatefulWidget {
  const CommentsScreen({super.key});

  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  bool _onlyUnanswered = true;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(T.commentsTitle)),
      body: !AppConfig.featureComments
          ? const EmptyView(title: T.featureOffTitle, text: T.featureOff, icon: Icons.lock_clock_outlined)
          : AsyncView<List<dynamic>>(
              key: ValueKey('comments-${state.activeAccountId}-$_onlyUnanswered'),
              load: () async => await state.api.get(
                '/api/comments',
                query: {'account_id': state.activeAccountId, 'filter': _onlyUnanswered ? 'unanswered' : null},
              ) as List,
              builder: (context, list, reload) => PageList(
                onRefresh: reload,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text(T.commentsUnanswered)),
                      ButtonSegment(value: false, label: Text(T.all)),
                    ],
                    selected: {_onlyUnanswered},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setState(() => _onlyUnanswered = s.first),
                  ),
                  const SizedBox(height: AppSpacing.s),
                  Text(T.noAutoReplies, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: AppSpacing.m),
                  if (list.isEmpty)
                    EmptyView(text: _onlyUnanswered ? T.commentsEmptyUnanswered : T.commentsEmpty, icon: Icons.mode_comment_outlined),
                  for (final c in list) _CommentCard(comment: Map<String, dynamic>.from(c as Map), onChanged: reload),
                ],
              ),
            ),
    );
  }
}

class _CommentCard extends StatefulWidget {
  const _CommentCard({required this.comment, required this.onChanged});
  final Map<String, dynamic> comment;
  final Future<void> Function() onChanged;

  @override
  State<_CommentCard> createState() => _CommentCardState();
}

class _CommentCardState extends State<_CommentCard> {
  final _reply = TextEditingController();
  bool _replying = false;
  bool _busy = false;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    setState(() => _busy = true);
    final ok = await guarded(context, action, success: success);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.read(context);
    final theme = Theme.of(context);
    final c = widget.comment;
    final hidden = c['is_hidden'] == true;
    final answered = c['replied_at'] != null;
    final replies = [for (final r in (c['replies'] as List? ?? const [])) Map<String, dynamic>.from(r as Map)];
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.s),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MediaThumb(c['media_thumbnail'] as String?, size: 44),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: AppSpacing.s,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('@${c['author_username']}', style: theme.textTheme.titleSmall),
                          Text(formatAgo(parseDate(c['created_at']) ?? DateTime.now()), style: theme.textTheme.bodySmall),
                          if (hidden) const Pill(T.hidden),
                          if (answered) const Pill(T.answered, color: AppColors.positive),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      AccountTag(state.accountById(c['account_id'] as String?)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s),
            Text(c['text'] as String? ?? ''),
            for (final r in replies)
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.l, top: AppSpacing.s),
                child: Text('↳ @${r['author_username']}: ${r['text']}', style: theme.textTheme.bodySmall),
              ),
            if (_replying) ...[
              const SizedBox(height: AppSpacing.s),
              TextField(
                controller: _reply,
                autofocus: true,
                minLines: 1,
                maxLines: 5,
                decoration: const InputDecoration(hintText: T.replyHint),
              ),
              const SizedBox(height: AppSpacing.s),
              Row(
                children: [
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () {
                            if (_reply.text.trim().isEmpty) return;
                            _run(
                              () => state.api.post('/api/comments/${c['id']}/reply', {'message': _reply.text.trim()}),
                              success: T.replySent,
                            );
                          },
                    child: const Text(T.replySend),
                  ),
                  TextButton(onPressed: () => setState(() => _replying = false), child: const Text(T.cancel)),
                ],
              ),
            ] else
              Wrap(
                spacing: AppSpacing.s,
                children: [
                  if (!hidden)
                    TextButton.icon(
                      onPressed: _busy ? null : () => setState(() => _replying = true),
                      icon: const Icon(Icons.reply, size: 18),
                      label: const Text(T.reply),
                    ),
                  TextButton.icon(
                    onPressed: _busy ? null : () => _run(() => state.api.post('/api/comments/${c['id']}/hide', {'hide': !hidden})),
                    icon: Icon(hidden ? Icons.visibility : Icons.visibility_off_outlined, size: 18),
                    label: Text(hidden ? T.unhide : T.hide),
                  ),
                  TextButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(builder: (_) => MediaDetailScreen(mediaId: c['media_id'] as String)),
                    ),
                    icon: const Icon(Icons.photo_outlined, size: 18),
                    label: const Text(T.toPost),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
