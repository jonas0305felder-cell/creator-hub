import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../config/app_config.dart';
import '../config/app_texts.dart';
import '../config/app_theme.dart';
import '../models/models.dart';
import '../services/voice_recorder.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'publish_sheet.dart';
import 'stats_detail_screens.dart';

/// MIME-Typ aus Dateiname, falls der Auswahldialog keinen liefert.
String mimeOf(XFile file) {
  if (file.mimeType != null && file.mimeType!.isNotEmpty) return file.mimeType!;
  final name = file.name.toLowerCase();
  return switch (name.split('.').last) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'mp4' => 'video/mp4',
    'mov' => 'video/quicktime',
    _ => 'application/octet-stream',
  };
}

/// Ideendetail: Angaben, Anhänge, Umsetzungsvorschlag, Abschließen.
class IdeaDetailScreen extends StatefulWidget {
  const IdeaDetailScreen({super.key, required this.ideaId});
  final String ideaId;

  @override
  State<IdeaDetailScreen> createState() => _IdeaDetailScreenState();
}

class _IdeaDetailScreenState extends State<IdeaDetailScreen> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  final _tags = TextEditingController();
  final _recorder = VoiceRecorder();
  final _player = AudioPlayer();
  bool _filled = false;
  bool _recording = false;
  bool _busy = false;
  String? _generating; // 'all' oder der Teil, der gerade neu erzeugt wird
  String? _playingId;
  String? _shownSuggestionId;
  List<ScheduledPost> _posts = [];

  AppState get _state => AppScope.read(context);

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingId = null);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPosts());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final idea = AppScope.of(context).ideaById(widget.ideaId);
    if (idea != null && !_filled) {
      _filled = true;
      _title.text = idea.title;
      _note.text = idea.note;
      _tags.text = idea.tags.join(', ');
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _tags.dispose();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _loadPosts() async {
    try {
      final raw = await _state.api.get('/api/posts') as List;
      if (!mounted) return;
      setState(() {
        _posts = [
          for (final p in raw)
            if ((p as Map)['idea_id'] == widget.ideaId) ScheduledPost.fromJson(Map<String, dynamic>.from(p)),
        ];
      });
    } catch (_) {
      // Kalendereinträge sind hier nur Zusatzinformation.
    }
  }

  Future<void> _update(Map<String, dynamic> fields) => guarded(context, () => _state.updateIdea(widget.ideaId, fields));

  /// Speichert Titel, Notiz und Tags, wenn sie geändert wurden.
  Future<void> _saveTexts(Idea idea) async {
    final tags = _tags.text.split(',').map((t) => t.trim().replaceFirst('#', '')).where((t) => t.isNotEmpty).toList();
    final changes = <String, dynamic>{
      if (_title.text.trim() != idea.title && _title.text.trim().isNotEmpty) 'title': _title.text.trim(),
      if (_note.text.trim() != idea.note) 'note': _note.text.trim(),
      if (tags.join(',') != idea.tags.join(',')) 'tags': tags,
    };
    if (changes.isNotEmpty) await _update(changes);
  }

  // ---------------------------------------------------------------
  // Anhänge
  // ---------------------------------------------------------------

  Future<void> _attach(Future<void> Function() action) async {
    setState(() => _busy = true);
    await guarded(context, action);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _addPhoto() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 2400);
    if (file == null || !mounted) return;
    await _attach(() async {
      final mime = mimeOf(file);
      _state.putIdea(await _state.api.upload('/api/ideas/${widget.ideaId}/attachments', await file.readAsBytes(), mime));
    });
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      setState(() => _recording = false);
      await _attach(() async {
        final wav = await _recorder.stop();
        _state.putIdea(await _state.api.upload('/api/ideas/${widget.ideaId}/attachments', wav, 'audio/wav'));
      });
      return;
    }
    try {
      final ok = await _recorder.start();
      if (!mounted) return;
      if (!ok) {
        showMessage(context, T.micDenied);
        return;
      }
      setState(() => _recording = true);
    } catch (_) {
      if (mounted) showMessage(context, T.micDenied);
    }
  }

  Future<void> _addLink() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(T.attachLink),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: T.linkField),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text(T.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text(T.add)),
        ],
      ),
    );
    if (url == null || url.trim().isEmpty || !mounted) return;
    await _attach(
      () async => _state.putIdea(await _state.api.post('/api/ideas/${widget.ideaId}/attachments', {'type': 'link', 'url': url.trim()})),
    );
  }

  Future<void> _play(Attachment a) async {
    if (_playingId == a.id) {
      await _player.stop();
      setState(() => _playingId = null);
      return;
    }
    try {
      await _player.play(UrlSource(a.url!));
      if (mounted) setState(() => _playingId = a.id);
    } catch (e) {
      if (mounted) showMessage(context, T.errorUnknown);
    }
  }

  // ---------------------------------------------------------------
  // Umsetzungsvorschlag
  // ---------------------------------------------------------------

  Future<void> _generate([String? part]) async {
    setState(() => _generating = part ?? 'all');
    await guarded(context, () async {
      _state.putIdea(await _state.api.post('/api/ideas/${widget.ideaId}/suggestions', {'part': ?part}, true));
      _shownSuggestionId = null; // neue Version anzeigen
    });
    if (mounted) setState(() => _generating = null);
  }

  Future<void> _patchSuggestion(Suggestion s, Map<String, dynamic> fields) =>
      guarded(context, () async => _state.putIdea(await _state.api.patch('/api/suggestions/${s.id}', fields)));

  /// Bearbeiten eines Vorschlagsteils von Hand.
  Future<void> _editPart(
    Suggestion s,
    String label,
    String field,
    String initial, {
    String? hint,
    bool list = false,
    bool hashtags = false,
  }) async {
    final controller = TextEditingController(text: initial);
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 3,
            maxLines: 14,
            decoration: InputDecoration(helperText: hint),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text(T.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text(T.save)),
        ],
      ),
    );
    if (text == null || !mounted) return;
    final Object value = hashtags
        ? text
              .split(RegExp(r'[\s,]+'))
              .where((t) => t.isNotEmpty)
              .map((t) => t.startsWith('#') ? t : '#$t')
              .take(AppConfig.maxSuggestedHashtags)
              .toList()
        : list
        ? text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList()
        : text.trim();
    await _patchSuggestion(s, {field: value});
  }

  Future<void> _openPublish(Idea idea, {required bool planOnly}) async {
    if (idea.accountId == null) {
      showMessage(context, T.publishNeedsAccount);
      return;
    }
    await showPublishSheet(context, idea: idea, suggestion: _shown(idea), planOnly: planOnly);
    await _loadPosts();
  }

  Suggestion? _shown(Idea idea) => idea.suggestions.where((s) => s.id == _shownSuggestionId).firstOrNull ?? idea.activeSuggestion;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final idea = state.ideaById(widget.ideaId);
    if (idea == null) {
      return Scaffold(
        appBar: AppBar(title: const Text(T.ideaDetail)),
        body: const EmptyView(text: T.ideasNoMatch, icon: Icons.search_off),
      );
    }
    final suggestion = _shown(idea);
    final account = state.accountById(idea.accountId);

    Widget dropdown<V>(String label, V? value, Map<V?, String> options, void Function(V?) onChanged) => DropdownButtonFormField<V?>(
      key: ValueKey('$label-$value'),
      initialValue: options.containsKey(value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, isDense: true),
      items: [
        for (final e in options.entries)
          DropdownMenuItem(
            value: e.key,
            child: Text(e.value, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text(T.ideaDetail),
        actions: [
          IconButton(
            tooltip: T.delete,
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (!await confirm(context, title: T.delete, text: T.ideaDeleteConfirm, action: T.delete, danger: true) || !context.mounted) {
                return;
              }
              final navigator = Navigator.of(context);
              final ok = await guarded(context, () => state.deleteIdea(idea.id));
              if (ok) navigator.pop();
            },
          ),
        ],
      ),
      body: PageList(
        children: [
          // Verlässt der Fokus die Textfelder, wird gespeichert.
          Focus(
            onFocusChange: (has) {
              if (!has) _saveTexts(idea);
            },
            child: Column(
              children: [
                TextField(
                  controller: _title,
                  style: theme.textTheme.titleLarge,
                  decoration: const InputDecoration(labelText: T.ideaTitle),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: AppSpacing.m),
                TextField(
                  controller: _note,
                  decoration: const InputDecoration(labelText: T.ideaNote),
                  minLines: 2,
                  maxLines: 8,
                ),
                const SizedBox(height: AppSpacing.m),
                TextField(
                  controller: _tags,
                  decoration: const InputDecoration(labelText: T.tags, helperText: T.tagsHint),
                  onSubmitted: (_) => _saveTexts(idea),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.m),
          TileGrid(
            minTileWidth: 220,
            children: [
              dropdown<String>(T.account, idea.accountId, {
                null: T.noAccount,
                for (final a in state.accounts) a.id: '@${a.username}',
              }, (v) => _update({'account_id': v})),
              dropdown<String>(T.niche, idea.nicheId, {
                null: T.noNiche,
                for (final n in state.niches) n.id: n.name,
              }, (v) => _update({'niche_id': v})),
              dropdown<String>(T.format, idea.format, {
                null: T.noFormat,
                for (final f in Idea.formats) f: formatLabel(f),
              }, (v) => _update({'format': v})),
              dropdown<String>(T.status, idea.status, {for (final s in Idea.statuses) s: statusLabel(s)}, (v) => _update({'status': v})),
              dropdown<String>(T.assignee, idea.assigneeId, {
                null: T.nobody,
                for (final m in state.members) m['id'] as String: m['name'] as String,
              }, (v) => _update({'assignee_id': v})),
              InkWell(
                onTap: () async {
                  final when = await pickDateTime(context, initial: idea.plannedFor, allowPast: true);
                  if (when != null) await _update({'planned_for': when.toUtc().toIso8601String()});
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: T.plannedFor,
                    isDense: true,
                    suffixIcon: idea.plannedFor == null
                        ? const Icon(Icons.event)
                        : IconButton(tooltip: T.noDate, icon: const Icon(Icons.clear), onPressed: () => _update({'planned_for': null})),
                  ),
                  child: Text(idea.plannedFor == null ? T.noDate : formatDateTime(idea.plannedFor)),
                ),
              ),
            ],
          ),
          if (idea.sourceTrendTitle != null || idea.sourceMediaId != null) ...[
            const SectionTitle(T.origin),
            if (idea.sourceTrendTitle != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.trending_up),
                title: Text(T.originTrend(idea.sourceTrendTitle!)),
              ),
            if (idea.sourceMediaId != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.photo_outlined),
                title: Text(
                  T.originMedia((idea.sourceMediaCaption ?? '').replaceAll('\n', ' ')),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => MediaDetailScreen(mediaId: idea.sourceMediaId!))),
              ),
          ],

          const SectionTitle(T.attachments),
          Wrap(
            spacing: AppSpacing.s,
            runSpacing: AppSpacing.s,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final a in idea.attachments)
                InputChip(
                  avatar: Icon(switch (a.type) {
                    'image' => Icons.image_outlined,
                    'audio' => _playingId == a.id ? Icons.stop : Icons.play_arrow,
                    _ => Icons.link,
                  }, size: 18),
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(switch (a.type) {
                      'image' => T.attachPhoto,
                      'audio' => T.voiceNote,
                      _ => Uri.tryParse(a.url ?? '')?.host ?? T.attachLink,
                    }, overflow: TextOverflow.ellipsis),
                  ),
                  onPressed: () => a.type == 'audio' ? _play(a) : openLink(context, a.url),
                  onDeleted: () => _attach(() async => _state.putIdea(await _state.api.delete('/api/attachments/${a.id}'))),
                  deleteButtonTooltipMessage: T.delete,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s),
          Wrap(
            spacing: AppSpacing.s,
            runSpacing: AppSpacing.s,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _busy || _recording ? null : _addPhoto,
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: const Text(T.attachPhoto),
              ),
              if (_recording)
                FilledButton.icon(
                  onPressed: _toggleRecording,
                  style: FilledButton.styleFrom(backgroundColor: AppColors.negative),
                  icon: const Icon(Icons.stop, size: 18),
                  label: const Text(T.attachStop),
                )
              else
                OutlinedButton.icon(
                  onPressed: _busy ? null : _toggleRecording,
                  icon: const Icon(Icons.mic_none, size: 18),
                  label: const Text(T.attachVoice),
                ),
              OutlinedButton.icon(
                onPressed: _busy || _recording ? null : _addLink,
                icon: const Icon(Icons.link, size: 18),
                label: const Text(T.attachLink),
              ),
              if (_recording) Text(T.recording, style: theme.textTheme.bodySmall),
              if (_busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: AppSpacing.s),
          Text(T.shareMenuNote, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),

          const SectionTitle(T.suggestion),
          if (suggestion == null) ...[
            Text(T.suggestIntro, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: AppSpacing.m),
            if (state.serverSetup['ai'] == false) const Notice(T.aiNotConfigured, icon: Icons.settings_outlined),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _generating != null ? null : _generate,
                icon: _generating != null
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome, size: 18),
                label: Text(_generating != null ? T.suggesting : T.suggest),
              ),
            ),
          ] else
            _SuggestionView(
              idea: idea,
              suggestion: suggestion,
              generating: _generating,
              onGenerate: _generate,
              onEdit: (label, field, initial, {hint, list = false, hashtags = false}) =>
                  _editPart(suggestion, label, field, initial, hint: hint, list: list, hashtags: hashtags),
              onShowVersion: (id) => setState(() => _shownSuggestionId = id),
              onUseVersion: () => _patchSuggestion(suggestion, {'is_selected': true}),
            ),

          const SectionTitle(T.finish),
          Wrap(
            spacing: AppSpacing.s,
            runSpacing: AppSpacing.s,
            children: [
              if (idea.status != 'ready' && idea.status != 'published')
                OutlinedButton.icon(
                  onPressed: () => _update({'status': 'ready'}),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text(T.markReady),
                ),
              if (AppConfig.featurePublishing && (account?.canPublish ?? false))
                FilledButton.icon(
                  onPressed: () => _openPublish(idea, planOnly: false),
                  icon: const Icon(Icons.send, size: 18),
                  label: const Text(T.publish),
                ),
              OutlinedButton.icon(
                onPressed: () => _openPublish(idea, planOnly: !(AppConfig.featurePublishing && (account?.canPublish ?? false))),
                icon: const Icon(Icons.event, size: 18),
                label: const Text(T.planInCalendar),
              ),
              if (suggestion != null)
                OutlinedButton.icon(
                  onPressed: () => copyText(context, suggestion.captionWithHashtags),
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text(T.copyCaption),
                ),
            ],
          ),
          if (!AppConfig.featurePublishing)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.m),
              child: Notice(T.featureOff),
            ),
          if (account != null && !account.canPublish)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.m),
              child: Notice(T.publishNoConnection),
            ),
          if (idea.publishedMediaId != null) ...[
            const SectionTitle(T.linkedPost),
            Card(
              child: ListTile(
                leading: const Icon(Icons.check_circle, color: AppColors.positive),
                title: const Text(T.linkedPost),
                subtitle: const Text(T.linkedPostSub),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => MediaDetailScreen(mediaId: idea.publishedMediaId!))),
              ),
            ),
          ],
          if (_posts.isNotEmpty) ...[
            const SectionTitle(T.scheduledEntries),
            for (final p in _posts)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(p.status == 'failed' ? Icons.error : Icons.event, color: p.status == 'failed' ? AppColors.negative : null),
                title: Text('${formatDateTime(p.scheduledFor)} · ${postStatusLabel(p.status)}'),
                subtitle: p.errorMessage == null ? null : Text(p.errorMessage!),
                trailing: p.permalink == null
                    ? null
                    : IconButton(tooltip: T.viewPost, icon: const Icon(Icons.open_in_new), onPressed: () => openLink(context, p.permalink)),
              ),
          ],
        ],
      ),
    );
  }
}

typedef _EditPart = void Function(String label, String field, String initial, {String? hint, bool list, bool hashtags});

class _SuggestionView extends StatelessWidget {
  const _SuggestionView({
    required this.idea,
    required this.suggestion,
    required this.generating,
    required this.onGenerate,
    required this.onEdit,
    required this.onShowVersion,
    required this.onUseVersion,
  });

  final Idea idea;
  final Suggestion suggestion;
  final String? generating;
  final void Function([String? part]) onGenerate;
  final _EditPart onEdit;
  final void Function(String id) onShowVersion;
  final VoidCallback onUseVersion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = suggestion;
    final busy = generating != null;

    // Abschnitt mit Überschrift, „Neu erzeugen“ und „Bearbeiten“.
    Widget part(String label, String key, Widget content, VoidCallback edit, {String? copy}) => Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.s),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.m, AppSpacing.xs, AppSpacing.xs, AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(label, style: theme.textTheme.titleSmall)),
                if (generating == key || generating == 'all')
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else ...[
                  if (copy != null)
                    IconButton(tooltip: T.copy, icon: const Icon(Icons.copy, size: 20), onPressed: () => copyText(context, copy)),
                  IconButton(tooltip: T.edit, icon: const Icon(Icons.edit_outlined, size: 20), onPressed: busy ? null : edit),
                  IconButton(
                    tooltip: T.regenerate,
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: busy ? null : () => onGenerate(key),
                  ),
                ],
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.s),
              child: content,
            ),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Notice(T.aiNotice, icon: Icons.auto_awesome),
        Row(
          children: [
            if (idea.suggestions.length > 1)
              DropdownButton<String>(
                value: s.id,
                underline: const SizedBox.shrink(),
                items: [
                  for (final v in idea.suggestions)
                    DropdownMenuItem(value: v.id, child: Text('${T.version(v.version)}${v.isSelected ? ' (${T.versionActive})' : ''}')),
                ],
                onChanged: (id) => onShowVersion(id!),
              )
            else
              Text(T.version(s.version), style: theme.textTheme.labelLarge),
            const SizedBox(width: AppSpacing.s),
            if (!s.isSelected) TextButton(onPressed: onUseVersion, child: const Text(T.useVersion)),
            const Spacer(),
            TextButton.icon(
              onPressed: busy ? null : () => onGenerate(),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text(T.regenerateAll),
            ),
          ],
        ),
        part(
          T.formatRecommendation,
          'format',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Pill(formatLabel(s.format), color: theme.colorScheme.primary),
              if (s.formatReason.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.s),
                  child: Text(s.formatReason),
                ),
            ],
          ),
          () => onEdit(T.formatRecommendation, 'format_reason', s.formatReason),
        ),
        part(
          T.hooks,
          'hooks',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final h in s.hooks)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text('• $h'),
                ),
            ],
          ),
          () => onEdit(T.hooks, 'hooks', s.hooks.join('\n'), hint: T.onePerLine, list: true),
        ),
        part(
          T.outline,
          'outline',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < s.outline.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text('${i + 1}. ${s.outline[i]}'),
                ),
            ],
          ),
          () => onEdit(T.outline, 'outline', s.outline.join('\n'), hint: T.onePerLine, list: true),
        ),
        part(T.cta, 'cta', Text(s.cta), () => onEdit(T.cta, 'cta', s.cta)),
        part(T.caption, 'caption', Text(s.caption), () => onEdit(T.caption, 'caption_draft', s.caption), copy: s.captionWithHashtags),
        part(
          T.hashtags,
          'hashtags',
          Text(s.hashtags.join(' '), style: TextStyle(color: theme.colorScheme.primary)),
          () => onEdit(T.hashtags, 'hashtags', s.hashtags.join(' '), hint: T.hashtagsHint, hashtags: true),
        ),
        Wrap(
          spacing: AppSpacing.s,
          runSpacing: AppSpacing.s,
          children: [
            OutlinedButton.icon(
              onPressed: () =>
                  copyText(context, s.asText(hooksLabel: T.hooks, outlineLabel: T.outline, ctaLabel: T.cta, captionLabel: T.caption)),
              icon: const Icon(Icons.copy_all, size: 18),
              label: const Text(T.copyAll),
            ),
            OutlinedButton.icon(
              onPressed: () => SharePlus.instance.share(
                ShareParams(
                  text: s.asText(hooksLabel: T.hooks, outlineLabel: T.outline, ctaLabel: T.cta, captionLabel: T.caption),
                  subject: idea.title,
                ),
              ),
              icon: const Icon(Icons.ios_share, size: 18),
              label: const Text(T.share),
            ),
          ],
        ),
      ],
    );
  }
}
