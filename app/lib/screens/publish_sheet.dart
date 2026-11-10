import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../config/app_config.dart';
import '../config/app_texts.dart';
import '../config/app_theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'calendar_view.dart';
import 'idea_detail_screen.dart' show mimeOf;

/// Öffnet „Veröffentlichen“ bzw. „Im Kalender einplanen“ für eine Idee.
Future<void> showPublishSheet(BuildContext context, {required Idea idea, Suggestion? suggestion, required bool planOnly}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PublishSheet(idea: idea, suggestion: suggestion, planOnly: planOnly),
    );

class _Picked {
  _Picked(this.name, this.mime, this.bytes);
  final String name;
  final String mime;
  final Uint8List bytes;
}

enum _When { now, schedule, planOnly }

class _PublishSheet extends StatefulWidget {
  const _PublishSheet({required this.idea, required this.suggestion, required this.planOnly});
  final Idea idea;
  final Suggestion? suggestion;
  final bool planOnly;

  @override
  State<_PublishSheet> createState() => _PublishSheetState();
}

class _PublishSheetState extends State<_PublishSheet> {
  late final _caption = TextEditingController(text: widget.suggestion?.captionWithHashtags ?? '');
  late String _format = switch (widget.idea.format ?? widget.suggestion?.format) {
    'reel' => 'reel',
    'carousel' => 'carousel',
    _ => 'post',
  };
  late _When _when = widget.planOnly ? _When.planOnly : _When.schedule;
  DateTime? _date;
  final List<_Picked> _media = [];
  Map<String, dynamic>? _limit;
  List<String> _problems = [];
  String? _progress;

  Account? get _account => AppScope.read(context).accountById(widget.idea.accountId);
  bool get _canPublish => AppConfig.featurePublishing && (_account?.canPublish ?? false);

  @override
  void initState() {
    super.initState();
    _date = widget.idea.plannedFor != null && widget.idea.plannedFor!.isAfter(DateTime.now()) ? widget.idea.plannedFor : null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _validate());
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  /// Vorab-Prüfung: Formatregeln und verbleibendes Tageslimit.
  Future<void> _validate() async {
    if (!_canPublish || _when == _When.planOnly) {
      setState(() => _problems = []);
      return;
    }
    try {
      final result = await AppScope.read(context).api.post('/api/posts/validate', {
        'account_id': widget.idea.accountId,
        'format': _format,
        'media': [
          for (final m in _media) {'mime_type': m.mime},
        ],
      }) as Map;
      if (!mounted) return;
      setState(() {
        _problems = [for (final p in result['problems'] as List) p.toString()];
        _limit = Map<String, dynamic>.from(result['limit'] as Map);
      });
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _pick({required bool video}) async {
    final picker = ImagePicker();
    final files = <XFile>[];
    if (video) {
      final f = await picker.pickVideo(source: ImageSource.gallery);
      if (f != null) files.add(f);
    } else if (_format == 'carousel') {
      files.addAll(await picker.pickMultiImage());
    } else {
      final f = await picker.pickImage(source: ImageSource.gallery);
      if (f != null) files.add(f);
    }
    for (final f in files) {
      _media.add(_Picked(f.name, mimeOf(f), await f.readAsBytes()));
    }
    if (mounted) setState(() {});
    await _validate();
  }

  bool get _limitReached => _limit != null && _limit!['remaining'] != null && (_limit!['remaining'] as int) <= 0;

  Future<void> _submit() async {
    final state = AppScope.read(context);
    final planOnly = _when == _When.planOnly;
    if (_when != _When.now && _date == null) {
      showMessage(context, T.pickDate);
      return;
    }
    try {
      final media = <Map<String, String>>[];
      if (!planOnly) {
        setState(() => _progress = T.uploading);
        for (final m in _media) {
          final r = await state.api.upload('/api/uploads', m.bytes, m.mime) as Map;
          media.add({'key': r['key'] as String, 'mime_type': r['mime_type'] as String});
        }
      }
      setState(() => _progress = _when == _When.now ? T.publishing : T.saving);
      final post = await state.api.post('/api/posts', {
        'account_id': widget.idea.accountId,
        'idea_id': widget.idea.id,
        'suggestion_id': widget.suggestion?.id,
        'format': _format,
        'caption': _caption.text,
        'media': media,
        'publish_now': _when == _When.now,
        'plan_only': planOnly,
        if (_when != _When.now) 'scheduled_for': _date!.toUtc().toIso8601String(),
      }, true) as Map;
      // Status der Idee: veröffentlicht wird vom Server gesetzt, sonst „Bereit“.
      if (widget.idea.status == 'idea' || widget.idea.status == 'in_progress') {
        await state.updateIdea(widget.idea.id, {'status': 'ready'});
      }
      if (_when == _When.now) {
        await _waitForResult(post['id'] as String);
      } else if (mounted) {
        showMessage(context, T.publishScheduled);
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _progress = null);
      showError(context, e);
    }
  }

  /// Fragt den Status ab, bis Instagram den Beitrag veröffentlicht hat.
  Future<void> _waitForResult(String postId) async {
    final state = AppScope.read(context);
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      final post = ScheduledPost.fromJson(Map<String, dynamic>.from(await state.api.get('/api/posts/$postId') as Map));
      if (!mounted) return;
      if (post.status == 'published') {
        await state.refreshIdeas();
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(
          SnackBar(
            content: const Text(T.publishSuccess),
            action: post.permalink == null ? null : SnackBarAction(label: T.viewPost, onPressed: () => launchUrlString(post.permalink!)),
          ),
        );
        return;
      }
      if (post.status == 'failed') {
        setState(() => _progress = null);
        showMessage(context, '${T.publishFailed}: ${post.errorMessage ?? T.errorUnknown}');
        return;
      }
    }
    if (mounted) {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text(T.publishStillRunning)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final account = _account;
    final planOnly = _when == _When.planOnly;
    final rules = switch (_format) {
      'reel' => T.rulesReel,
      'carousel' => T.rulesCarousel(AppConfig.maxCarouselItems),
      _ => T.rulesPost,
    };
    final blocked = _progress != null || (!planOnly && (_problems.isNotEmpty || _limitReached));
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpacing.l, 0, AppSpacing.l, MediaQuery.viewInsetsOf(context).bottom + AppSpacing.l),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.planOnly ? T.planInCalendar : T.publishTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.s),
            Align(alignment: Alignment.centerLeft, child: AccountTag(account)),
            if (!_canPublish)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.m),
                child: Notice(AppConfig.featurePublishing ? T.publishNoConnection : T.featureOff),
              ),
            const SizedBox(height: AppSpacing.m),
            Text(T.publishFormat, style: theme.textTheme.labelLarge),
            const SizedBox(height: AppSpacing.xs),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'post', label: Text(T.formatPost)),
                ButtonSegment(value: 'reel', label: Text(T.formatReel)),
                ButtonSegment(value: 'carousel', label: Text(T.formatCarousel)),
              ],
              selected: {_format},
              showSelectedIcon: false,
              onSelectionChanged: (s) {
                setState(() => _format = s.first);
                _validate();
              },
            ),
            const SizedBox(height: AppSpacing.xs),
            Text('$rules ${T.storiesNotPublished}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            if (!planOnly) ...[
              const SizedBox(height: AppSpacing.m),
              Text(T.publishMedia, style: theme.textTheme.labelLarge),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.s,
                runSpacing: AppSpacing.s,
                children: [
                  for (var i = 0; i < _media.length; i++)
                    InputChip(
                      avatar: Icon(_media[i].mime.startsWith('video/') ? Icons.movie_outlined : Icons.image_outlined, size: 18),
                      label: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 160),
                        child: Text('${i + 1}. ${_media[i].name}', overflow: TextOverflow.ellipsis),
                      ),
                      onDeleted: () {
                        setState(() => _media.removeAt(i));
                        _validate();
                      },
                    ),
                  if (_format != 'reel')
                    OutlinedButton.icon(
                      onPressed: () => _pick(video: false),
                      icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                      label: const Text(T.addImage),
                    ),
                  if (_format != 'post')
                    OutlinedButton.icon(
                      onPressed: () => _pick(video: true),
                      icon: const Icon(Icons.video_call_outlined, size: 18),
                      label: const Text(T.addVideo),
                    ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.m),
            TextField(
              controller: _caption,
              minLines: 3,
              maxLines: 10,
              maxLength: 2200,
              decoration: const InputDecoration(labelText: T.publishCaption),
            ),
            Text(T.publishWhen, style: theme.textTheme.labelLarge),
            const SizedBox(height: AppSpacing.xs),
            SegmentedButton<_When>(
              segments: [
                if (_canPublish) const ButtonSegment(value: _When.now, label: Text(T.publishNow)),
                if (_canPublish) const ButtonSegment(value: _When.schedule, label: Text(T.publishSchedule)),
                const ButtonSegment(value: _When.planOnly, label: Text(T.publishPlanOnly)),
              ],
              selected: {_canPublish ? _when : _When.planOnly},
              showSelectedIcon: false,
              onSelectionChanged: (s) {
                setState(() => _when = s.first);
                _validate();
              },
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              planOnly
                  ? T.publishPlanOnlyNote
                  : _when == _When.schedule
                  ? T.publishServerNote
                  : '',
              style: theme.textTheme.bodySmall,
            ),
            if (_when != _When.now) ...[
              const SizedBox(height: AppSpacing.s),
              OutlinedButton.icon(
                onPressed: () async {
                  final d = await pickDateTime(context, initial: _date, allowPast: planOnly);
                  if (d != null) setState(() => _date = d);
                },
                icon: const Icon(Icons.event, size: 18),
                label: Text(_date == null ? T.pickDate : formatDateTime(_date)),
              ),
            ],
            if (!planOnly && _canPublish) ...[
              const SectionTitle(T.precheck),
              if (_problems.isEmpty && _media.isNotEmpty)
                const Notice(T.precheckOk, icon: Icons.check_circle_outline, color: AppColors.positive),
              for (final p in _problems) Notice(p, icon: Icons.error_outline, color: AppColors.negative),
              if (_limit != null)
                Notice(
                  _limitReached ? T.limitReached : limitText(_limit!),
                  icon: Icons.speed,
                  color: _limitReached ? AppColors.negative : null,
                ),
            ],
            const SizedBox(height: AppSpacing.l),
            FilledButton.icon(
              onPressed: blocked ? null : _submit,
              icon: _progress != null
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check, size: 18),
              label: Text(
                _progress ??
                    switch (_canPublish ? _when : _When.planOnly) {
                      _When.now => T.publishNowButton,
                      _When.schedule => T.publishScheduleButton,
                      _When.planOnly => T.publishPlanButton,
                    },
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            OutlinedButton.icon(
              onPressed: () => copyText(context, _caption.text),
              icon: const Icon(Icons.copy, size: 18),
              label: const Text(T.copyCaption),
            ),
          ],
        ),
      ),
    );
  }
}
