import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../config/app_config.dart';
import '../config/app_texts.dart';
import '../config/app_theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'accounts_screen.dart';
import 'comments_screen.dart';

/// Tab „Mehr“: Accounts, Kommentare, Nischen, Team, Datenschutz.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    Widget item(IconData icon, String title, String sub, Widget screen) => Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.s),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(sub),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen)),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text(T.tabMore)),
      body: PageList(
        children: [
          item(Icons.people_outline, T.moreAccounts, T.moreAccountsSub, const AccountsScreen()),
          if (AppConfig.featureComments) item(Icons.mode_comment_outlined, T.moreComments, T.moreCommentsSub, const CommentsScreen()),
          item(Icons.category_outlined, T.moreNiches, T.moreNichesSub, const NichesScreen()),
          item(Icons.group_work_outlined, T.moreTeam, T.moreTeamSub, const TeamScreen()),
          item(Icons.shield_outlined, T.morePrivacy, T.morePrivacySub, const PrivacyScreen()),
          const SizedBox(height: AppSpacing.l),
          Text(
            T.signedInAs((state.me?['user']?['email'] ?? '') as String),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Nischen
// ---------------------------------------------------------------------

class NichesScreen extends StatelessWidget {
  const NichesScreen({super.key});

  Future<void> _edit(BuildContext context, [Niche? niche]) async {
    final state = AppScope.read(context);
    final name = TextEditingController(text: niche?.name);
    final keywords = TextEditingController(text: niche?.keywords.join(', '));
    final language = TextEditingController(text: niche?.language ?? 'de');
    final region = TextEditingController(text: niche?.region ?? 'DE');
    final fields = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(niche == null ? T.nicheAdd : niche.name),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: T.nicheName),
              ),
              const SizedBox(height: AppSpacing.m),
              TextField(
                controller: keywords,
                decoration: const InputDecoration(labelText: T.nicheKeywords, helperText: T.nicheKeywordsHint, helperMaxLines: 2),
              ),
              const SizedBox(height: AppSpacing.m),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: language,
                      decoration: const InputDecoration(labelText: T.nicheLanguage),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.m),
                  Expanded(
                    child: TextField(
                      controller: region,
                      decoration: const InputDecoration(labelText: T.nicheRegion),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text(T.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(context, {
              'name': name.text.trim(),
              'keywords': keywords.text.split(',').map((k) => k.trim()).where((k) => k.isNotEmpty).toList(),
              'language': language.text.trim(),
              'region': region.text.trim().toUpperCase(),
            }),
            child: const Text(T.save),
          ),
        ],
      ),
    );
    if (fields == null || !context.mounted) return;
    if ((fields['name'] as String).isEmpty) {
      showMessage(context, T.requiredFields);
      return;
    }
    await guarded(context, () async {
      if (niche == null) {
        await state.api.post('/api/niches', fields);
      } else {
        await state.api.patch('/api/niches/${niche.id}', fields);
      }
      await state.refreshNiches();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(T.nichesTitle)),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'niche-fab',
        onPressed: () => _edit(context),
        icon: const Icon(Icons.add),
        label: const Text(T.nicheAdd),
      ),
      body: state.niches.isEmpty
          ? const EmptyView(text: T.nichesEmpty, icon: Icons.category_outlined)
          : PageList(
              onRefresh: state.refreshNiches,
              bottomSpace: true,
              children: [
                for (final n in state.niches)
                  Card(
                    margin: const EdgeInsets.only(bottom: AppSpacing.s),
                    child: ListTile(
                      title: Text(n.name),
                      subtitle: Text([if (n.keywords.isNotEmpty) n.keywords.join(', '), '${n.language} · ${n.region}'].join('\n')),
                      onTap: () => _edit(context, n),
                      trailing: IconButton(
                        tooltip: T.delete,
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          if (!await confirm(context, title: n.name, text: T.nicheDeleteConfirm, danger: true) || !context.mounted) return;
                          await guarded(context, () async {
                            await state.api.delete('/api/niches/${n.id}');
                            await Future.wait([state.refreshNiches(), state.refreshAccounts(), state.refreshIdeas()]);
                          });
                        },
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------
// Team und Workspace
// ---------------------------------------------------------------------

class TeamScreen extends StatelessWidget {
  const TeamScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.read(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(T.teamTitle)),
      body: AsyncView<Map<String, dynamic>>(
        load: () async => Map<String, dynamic>.from(await state.api.get('/api/team') as Map),
        builder: (context, team, reload) {
          final members = [for (final m in team['members'] as List) Map<String, dynamic>.from(m as Map)];
          final invites = [for (final i in team['invites'] as List) Map<String, dynamic>.from(i as Map)];
          final workspace = (state.me?['workspace']?['name'] ?? '') as String;
          return PageList(
            onRefresh: reload,
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.workspaces_outline),
                  title: Text(workspace),
                  subtitle: const Text(T.workspaceName),
                  trailing: state.isOwner ? const Icon(Icons.edit_outlined) : null,
                  onTap: !state.isOwner
                      ? null
                      : () async {
                          final controller = TextEditingController(text: workspace);
                          final name = await showDialog<String>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text(T.workspaceName),
                              content: TextField(controller: controller, autofocus: true),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context), child: const Text(T.cancel)),
                                FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text(T.save)),
                              ],
                            ),
                          );
                          if (name == null || name.isEmpty || !context.mounted) return;
                          await guarded(context, () async {
                            await state.api.patch('/api/workspace', {'name': name});
                            await state.reload();
                          });
                          await reload();
                        },
                ),
              ),
              const SectionTitle(T.members),
              for (final m in members)
                Card(
                  margin: const EdgeInsets.only(bottom: AppSpacing.s),
                  child: ListTile(
                    leading: CircleAvatar(child: Text(((m['name'] as String?) ?? '?').characters.first.toUpperCase())),
                    title: Text('${m['name']}${m['id'] == state.userId ? ' (${T.you})' : ''}'),
                    subtitle: Text('${m['email']} · ${m['role'] == 'owner' ? T.roleOwner : T.roleMember}'),
                    trailing: state.isOwner && m['id'] != state.userId
                        ? TextButton(
                            onPressed: () async {
                              if (!await confirm(
                                    context,
                                    title: T.removeMember,
                                    text: T.removeMemberConfirm,
                                    action: T.removeMember,
                                    danger: true,
                                  ) ||
                                  !context.mounted) {
                                return;
                              }
                              await guarded(context, () async {
                                await state.api.delete('/api/team/members/${m['id']}');
                                await state.refreshTeam();
                              });
                              await reload();
                            },
                            child: const Text(T.removeMember),
                          )
                        : null,
                  ),
                ),
              if (state.isOwner) ...[
                const SizedBox(height: AppSpacing.m),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: () async {
                      Map<String, dynamic>? invite;
                      final ok = await guarded(
                        context,
                        () async => invite = Map<String, dynamic>.from(await state.api.post('/api/team/invites') as Map),
                      );
                      if (!ok || !context.mounted) return;
                      await showDialog<void>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text(T.invite),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(T.inviteExplain),
                              const SizedBox(height: AppSpacing.m),
                              SelectableText(invite!['code'] as String, style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 2)),
                              Text(T.inviteValidUntil(formatDate(parseDate(invite!['expires_at']))), style: theme.textTheme.bodySmall),
                            ],
                          ),
                          actions: [
                            TextButton(onPressed: () => copyText(context, invite!['code'] as String), child: const Text(T.copy)),
                            FilledButton(onPressed: () => Navigator.pop(context), child: const Text(T.close)),
                          ],
                        ),
                      );
                      await reload();
                    },
                    icon: const Icon(Icons.person_add_alt, size: 18),
                    label: const Text(T.invite),
                  ),
                ),
                if (invites.isNotEmpty) ...[
                  const SectionTitle(T.openInvites),
                  for (final i in invites)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.vpn_key_outlined),
                      title: SelectableText(i['code'] as String),
                      subtitle: Text(T.inviteValidUntil(formatDate(parseDate(i['expires_at'])))),
                      trailing: IconButton(
                        tooltip: T.copy,
                        icon: const Icon(Icons.copy),
                        onPressed: () => copyText(context, i['code'] as String),
                      ),
                    ),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Datenschutz und Konto
// ---------------------------------------------------------------------

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  Future<void> _export(BuildContext context) async {
    final state = AppScope.read(context);
    await guarded(context, () async {
      final bytes = await state.api.download('/api/export');
      // Im Browser startet ein Download, auf dem iPhone das Teilen-Menü.
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, mimeType: 'application/json', name: 'content-hub-export.json')],
          fileNameOverrides: const ['content-hub-export.json'],
          downloadFallbackEnabled: true,
        ),
      );
    }, success: T.exportDone);
  }

  Future<void> _delete(BuildContext context) async {
    final state = AppScope.read(context);
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text(T.deleteAccount),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(T.deleteAccountText),
              const SizedBox(height: AppSpacing.m),
              TextField(
                controller: controller,
                decoration: const InputDecoration(labelText: T.deleteAccountConfirmField),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text(T.cancel)),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.negative),
              onPressed: controller.text.trim() == T.deleteWord ? () => Navigator.pop(context, true) : null,
              child: const Text(T.deleteAccount),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final navigator = Navigator.of(context);
    if (await guarded(context, state.deleteAccountAndData)) navigator.popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(T.privacyTitle)),
      body: PageList(
        children: [
          Text(T.privacyWhat, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.s),
          const Text(T.privacyText),
          const SizedBox(height: AppSpacing.s),
          Text(T.privacyOperatorNote, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SectionTitle(T.connectedAccounts),
          if (state.accounts.isEmpty) Text(T.accountsEmpty, style: theme.textTheme.bodySmall),
          for (final a in state.accounts)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: AccountAvatar(a),
              title: Text('@${a.username}'),
              subtitle: Text(accountStatusText(a)),
            ),
          const SizedBox(height: AppSpacing.m),
          Card(
            child: ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text(T.exportData),
              subtitle: const Text(T.exportSub),
              onTap: () => _export(context),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout),
              title: const Text(T.logout),
              onTap: () async {
                final navigator = Navigator.of(context);
                await state.signOut();
                navigator.popUntil((r) => r.isFirst);
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.delete_forever_outlined, color: AppColors.negative),
              title: const Text(T.deleteAccount, style: TextStyle(color: AppColors.negative)),
              onTap: () => _delete(context),
            ),
          ),
        ],
      ),
    );
  }
}
