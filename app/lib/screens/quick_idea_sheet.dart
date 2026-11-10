import 'package:flutter/material.dart';

import '../config/app_texts.dart';
import '../config/app_theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'idea_detail_screen.dart';

/// Schnell-Idee erfassen (Plus-Button). Account und Nische sind aus dem
/// aktiven Kontext vorbelegt; [prefill] übernimmt Werte aus Trend/Beitrag.
Future<Idea?> showQuickIdea(BuildContext context, {Map<String, dynamic> prefill = const {}, bool openAfterSave = false}) {
  return showModalBottomSheet<Idea>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _QuickIdeaSheet(prefill: prefill, openAfterSave: openAfterSave),
  );
}

class _QuickIdeaSheet extends StatefulWidget {
  const _QuickIdeaSheet({required this.prefill, required this.openAfterSave});
  final Map<String, dynamic> prefill;
  final bool openAfterSave;

  @override
  State<_QuickIdeaSheet> createState() => _QuickIdeaSheetState();
}

class _QuickIdeaSheetState extends State<_QuickIdeaSheet> {
  late final _title = TextEditingController(text: widget.prefill['title'] as String? ?? '');
  late final _note = TextEditingController(text: widget.prefill['note'] as String? ?? '');
  String? _accountId;
  String? _nicheId;
  bool _busy = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final state = AppScope.read(context);
    _accountId = widget.prefill.containsKey('account_id') ? widget.prefill['account_id'] as String? : state.activeAccountId;
    final account = state.accountById(_accountId);
    _nicheId = widget.prefill['niche_id'] as String? ?? account?.primaryNicheId ?? account?.nicheIds.firstOrNull;
    if (state.nicheById(_nicheId) == null) _nicheId = null;
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save({required bool open}) async {
    if (_title.text.trim().isEmpty && _note.text.trim().isEmpty) {
      showMessage(context, T.ideaTitleOrNote);
      return;
    }
    setState(() => _busy = true);
    final state = AppScope.read(context);
    final navigator = Navigator.of(context);
    try {
      final idea = await state.createIdea({
        ...widget.prefill,
        'title': _title.text.trim(),
        'note': _note.text.trim(),
        'account_id': _accountId,
        'niche_id': _nicheId,
      });
      navigator.pop(idea);
      if (open) navigator.push(MaterialPageRoute<void>(builder: (_) => IdeaDetailScreen(ideaId: idea.id)));
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpacing.l, 0, AppSpacing.l, MediaQuery.viewInsetsOf(context).bottom + AppSpacing.l),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(T.quickIdea, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.m),
            TextField(
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(labelText: T.ideaTitle),
              textInputAction: TextInputAction.next,
              maxLength: 200,
              buildCounter: _noCounter,
            ),
            const SizedBox(height: AppSpacing.m),
            TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: T.ideaNote),
              minLines: 2,
              maxLines: 5,
            ),
            const SizedBox(height: AppSpacing.m),
            DropdownButtonFormField<String?>(
              initialValue: _accountId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: T.account),
              items: [
                const DropdownMenuItem(value: null, child: Text(T.noAccount)),
                for (final a in state.accounts) DropdownMenuItem(value: a.id, child: AccountTag(a)),
              ],
              onChanged: (v) => setState(() => _accountId = v),
            ),
            const SizedBox(height: AppSpacing.m),
            DropdownButtonFormField<String?>(
              initialValue: _nicheId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: T.niche),
              items: [
                const DropdownMenuItem(value: null, child: Text(T.noNiche)),
                for (final n in state.niches) DropdownMenuItem(value: n.id, child: Text(n.name)),
              ],
              onChanged: (v) => setState(() => _nicheId = v),
            ),
            const SizedBox(height: AppSpacing.l),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => _save(open: true),
                    child: const Text('${T.save} + ${T.attachments}', textAlign: TextAlign.center),
                  ),
                ),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : () => _save(open: widget.openAfterSave),
                    child: const Text(T.save),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Widget? _noCounter(BuildContext context, {required int currentLength, required bool isFocused, required int? maxLength}) => null;
