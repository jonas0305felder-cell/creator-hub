import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import '../config/app_config.dart';
import '../config/app_texts.dart';
import '../config/app_theme.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'more_screen.dart';

/// Accounts verbinden, einrichten und trennen.
class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  bool _connecting = false;

  AppState get _state => AppScope.read(context);

  /// Instagram-Login: Der Server liefert die Anmeldeadresse, das Fenster
  /// springt nach der Anmeldung zurück, der Ergebniscode holt das Ergebnis.
  Future<void> _connect({String? accountId}) async {
    final loginType = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _ConnectInfoSheet(server: _state.serverSetup),
    );
    if (loginType == null || !mounted) return;
    setState(() => _connecting = true);
    try {
      final start = await _state.api.post('/api/oauth/start', {'login_type': loginType, 'account_id': ?accountId}) as Map;
      final result = await FlutterWebAuth2.authenticate(
        url: start['url'] as String,
        callbackUrlScheme: kIsWeb ? Uri.parse(start['callback'] as String).scheme : AppConfig.callbackScheme,
      );
      final code = Uri.parse(result).queryParameters['result'];
      if (code == null) throw ApiException('cancelled', T.connectCancelled);
      final done = await _state.api.post('/api/oauth/result', {'code': code}) as Map;
      await _state.refreshAccounts();
      if (!mounted) return;
      final account = _state.accountById(done['account_id'] as String?);
      if (account != null) {
        showMessage(context, T.connectSuccess(account.username));
        await _edit(account, firstSetup: true);
      }
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    } catch (_) {
      // Fenster geschlossen oder Anmeldung abgebrochen.
      if (mounted) showMessage(context, T.connectCancelled);
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _addManual() async {
    final controller = TextEditingController();
    final username = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(T.addManual),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: T.manualUsername, prefixText: '@'),
            ),
            const SizedBox(height: AppSpacing.m),
            const Text(T.manualNote),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text(T.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text(T.add)),
        ],
      ),
    );
    if (username == null || username.trim().isEmpty || !mounted) return;
    // Nächste freie Farbe aus der Palette vorschlagen.
    final used = _state.accounts.map((a) => a.color.toUpperCase()).toSet();
    final color = AppColors.accountPalette
        .map(colorToHex)
        .firstWhere((c) => !used.contains(c.toUpperCase()), orElse: () => colorToHex(AppColors.brand));
    String? id;
    final ok = await guarded(context, () async {
      id = (await _state.api.post('/api/accounts/manual', {'username': username.trim(), 'color': color}) as Map)['id'] as String;
      await _state.refreshAccounts();
    });
    if (ok && mounted && _state.accountById(id) != null) await _edit(_state.accountById(id)!, firstSetup: true);
  }

  Future<void> _edit(Account account, {bool firstSetup = false}) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => AccountEditScreen(accountId: account.id, firstSetup: firstSetup),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final full = state.accounts.length >= AppConfig.maxAccounts;
    return Scaffold(
      appBar: AppBar(title: const Text(T.accountsTitle)),
      body: PageList(
        onRefresh: state.refreshAccounts,
        children: [
          if (!state.isOwner) const Notice(T.ownerOnly),
          if (full) Notice(T.accountLimit(AppConfig.maxAccounts)),
          if (state.isOwner)
            Wrap(
              spacing: AppSpacing.s,
              runSpacing: AppSpacing.s,
              children: [
                FilledButton.icon(
                  onPressed: _connecting || full ? null : () => _connect(),
                  icon: _connecting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.link, size: 18),
                  label: Text(_connecting ? T.connecting : T.connectAccount),
                ),
                OutlinedButton.icon(
                  onPressed: full ? null : _addManual,
                  icon: const Icon(Icons.person_add_alt, size: 18),
                  label: const Text(T.addManual),
                ),
              ],
            ),
          const SizedBox(height: AppSpacing.m),
          if (state.accounts.isEmpty) const EmptyView(text: T.accountsEmpty, icon: Icons.people_outline),
          for (final a in state.accounts)
            Card(
              margin: const EdgeInsets.only(bottom: AppSpacing.s),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.m),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        AccountAvatar(a, size: 44),
                        const SizedBox(width: AppSpacing.m),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('@${a.username}', style: theme.textTheme.titleMedium),
                              Text(
                                [
                                  switch (a.type) {
                                    'creator' => T.accountTypeCreator,
                                    'manual' => T.accountTypeManual,
                                    _ => T.accountTypeBusiness,
                                  },
                                  if (a.loginType == 'facebook') T.loginTypeFacebook,
                                  if (a.loginType == 'instagram') T.loginTypeInstagram,
                                ].join(' · '),
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        IconButton(tooltip: T.edit, icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(a)),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s),
                    Text(
                      accountStatusText(a),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: a.isDisconnected
                            ? AppColors.negative
                            : a.isExpiring
                            ? AppColors.warning
                            : null,
                      ),
                    ),
                    if (!a.isManual)
                      Text(
                        a.lastSyncedAt == null ? T.neverSynced : T.lastSync(formatDateTime(a.lastSyncedAt)),
                        style: theme.textTheme.bodySmall,
                      ),
                    if (a.lastSyncError != null)
                      Text(a.lastSyncError!, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.negative)),
                    if (state.isOwner && !a.isManual) ...[
                      const SizedBox(height: AppSpacing.s),
                      Wrap(
                        spacing: AppSpacing.s,
                        children: [
                          if (!a.isDisconnected)
                            TextButton.icon(
                              onPressed: () => guarded(context, () async {
                                await state.api.post('/api/accounts/${a.id}/sync', null, true);
                                await state.refreshAccounts();
                              }, success: T.syncDone),
                              icon: const Icon(Icons.sync, size: 18),
                              label: const Text(T.syncNow),
                            ),
                          TextButton.icon(
                            onPressed: _connecting ? null : () => _connect(accountId: a.id),
                            icon: const Icon(Icons.link, size: 18),
                            label: const Text(T.reconnect),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Erklärt vor dem Login, was die App liest und tut, und lässt den
/// Login-Weg wählen.
class _ConnectInfoSheet extends StatelessWidget {
  const _ConnectInfoSheet({required this.server});
  final Map<String, dynamic> server;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final instagram = server['instagram_login'] == true;
    final facebook = server['facebook_login'] == true;
    final unified = server['unified_login'] == true;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.l, 0, AppSpacing.l, AppSpacing.l),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(T.connectInfoTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.m),
            const Text(T.connectInfo),
            const SizedBox(height: AppSpacing.m),
            const Notice(T.privateAccountHelp),
            const Notice(T.otherAccountHint),
            if (!instagram && !facebook) const Notice(T.instagramNotConfigured, icon: Icons.settings_outlined, color: AppColors.warning),
            const SizedBox(height: AppSpacing.s),
            Card(
              child: ListTile(
                enabled: instagram,
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text(T.loginInstagram),
                subtitle: Text(instagram ? T.loginInstagramSub : T.notConfiguredTitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(context, 'instagram'),
              ),
            ),
            Card(
              child: ListTile(
                enabled: facebook,
                leading: const Icon(Icons.facebook),
                title: Text(unified ? T.loginMeta : T.loginFacebook),
                subtitle: Text(!facebook ? T.notConfiguredTitle : (unified ? T.loginMetaSub : T.loginFacebookSub)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(context, 'facebook'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Farbe, Nischen, Tonalität, Zielgruppe und Sprache eines Accounts.
class AccountEditScreen extends StatefulWidget {
  const AccountEditScreen({super.key, required this.accountId, this.firstSetup = false});
  final String accountId;
  final bool firstSetup;

  @override
  State<AccountEditScreen> createState() => _AccountEditScreenState();
}

class _AccountEditScreenState extends State<AccountEditScreen> {
  final _tone = TextEditingController();
  final _audience = TextEditingController();
  final _language = TextEditingController();
  String _color = '#6C4CF1';
  final Set<String> _niches = {};
  String? _primary;
  bool _loaded = false;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    final a = AppScope.read(context).accountById(widget.accountId);
    if (a == null) return;
    _loaded = true;
    _tone.text = a.tone;
    _audience.text = a.audienceNote;
    _language.text = a.language;
    _color = a.color;
    _niches.addAll(a.nicheIds);
    _primary = a.primaryNicheId;
  }

  @override
  void dispose() {
    _tone.dispose();
    _audience.dispose();
    _language.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final state = AppScope.read(context);
    setState(() => _saving = true);
    final ok = await guarded(context, () async {
      await state.api.patch('/api/accounts/${widget.accountId}', {
        'color': _color,
        'tone': _tone.text.trim(),
        'audience_note': _audience.text.trim(),
        'language': _language.text.trim().isEmpty ? 'de' : _language.text.trim(),
        'niche_ids': _niches.toList(),
        'primary_niche_id': _primary,
      });
      await state.refreshAccounts();
    }, success: T.saved);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.pop(context);
  }

  Future<void> _disconnect(Account a) async {
    final state = AppScope.read(context);
    final choice = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(T.disconnectTitle),
        content: const Text(T.disconnectText),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text(T.cancel)),
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text(T.disconnectKeepIdeas)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.negative),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(T.disconnectDeleteIdeas),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    final navigator = Navigator.of(context);
    final ok = await guarded(context, () async {
      await state.api.delete('/api/accounts/${a.id}', query: {'delete_ideas': '$choice'});
      await Future.wait([state.refreshAccounts(), state.refreshIdeas()]);
    });
    if (ok) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final a = state.accountById(widget.accountId);
    if (a == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyView(text: T.accountsEmpty),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.firstSetup ? T.connectedSetup : '@${a.username}')),
      body: PageList(
        children: [
          Text(T.accountColor, style: theme.textTheme.labelLarge),
          const SizedBox(height: AppSpacing.s),
          Wrap(
            spacing: AppSpacing.s,
            runSpacing: AppSpacing.s,
            children: [
              for (final c in AppColors.accountPalette)
                Semantics(
                  label: colorToHex(c),
                  selected: colorToHex(c).toUpperCase() == _color.toUpperCase(),
                  button: true,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() => _color = colorToHex(c)),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colorToHex(c).toUpperCase() == _color.toUpperCase() ? theme.colorScheme.onSurface : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: colorToHex(c).toUpperCase() == _color.toUpperCase() ? Icon(Icons.check, color: onColor(c), size: 20) : null,
                    ),
                  ),
                ),
            ],
          ),
          const SectionTitle(T.accountNiches),
          if (state.niches.isEmpty)
            Notice(
              T.nichesEmpty,
              action: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const NichesScreen())),
              actionLabel: T.nicheAdd,
            ),
          Wrap(
            spacing: AppSpacing.s,
            runSpacing: AppSpacing.xs,
            children: [
              for (final n in state.niches)
                FilterChip(
                  label: Text(n.name),
                  selected: _niches.contains(n.id),
                  onSelected: (on) => setState(() {
                    on ? _niches.add(n.id) : _niches.remove(n.id);
                    if (!_niches.contains(_primary)) _primary = _niches.firstOrNull;
                  }),
                ),
            ],
          ),
          if (_niches.length > 1) ...[
            const SizedBox(height: AppSpacing.m),
            DropdownButtonFormField<String>(
              initialValue: _primary,
              decoration: const InputDecoration(labelText: T.primaryNiche),
              items: [for (final id in _niches) DropdownMenuItem(value: id, child: Text(state.nicheById(id)?.name ?? ''))],
              onChanged: (v) => setState(() => _primary = v),
            ),
          ],
          const SizedBox(height: AppSpacing.l),
          TextField(
            controller: _tone,
            decoration: const InputDecoration(labelText: T.tone, hintText: T.toneHint),
            maxLines: 3,
            minLines: 1,
          ),
          const SizedBox(height: AppSpacing.m),
          TextField(
            controller: _audience,
            decoration: const InputDecoration(labelText: T.audience, hintText: T.audienceHint),
            maxLines: 3,
            minLines: 1,
          ),
          const SizedBox(height: AppSpacing.m),
          TextField(
            controller: _language,
            decoration: const InputDecoration(labelText: T.language),
          ),
          const SizedBox(height: AppSpacing.l),
          FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? T.saving : T.save)),
          if (state.isOwner) ...[
            const SizedBox(height: AppSpacing.xl),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.negative),
              onPressed: () => _disconnect(a),
              icon: const Icon(Icons.link_off, size: 18),
              label: const Text(T.disconnect),
            ),
          ],
        ],
      ),
    );
  }
}
