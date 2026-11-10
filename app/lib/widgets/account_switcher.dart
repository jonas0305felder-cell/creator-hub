import 'package:flutter/material.dart';

import '../config/app_texts.dart';
import '../config/app_theme.dart';
import '../state/app_state.dart';
import 'common.dart';

/// Kopfzeile mit dem Account-Umschalter (oben auf jeder Hauptseite).
///
/// Tippen öffnet die Account-Auswahl, Wischen nach links/rechts wechselt zum
/// nächsten Account. Die Kopfzeile trägt die Farbe des aktiven Accounts.
class AccountHeader extends StatelessWidget implements PreferredSizeWidget {
  const AccountHeader({super.key, required this.title, this.actions = const []});

  final String title;
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final account = state.activeAccount;
    final background = account == null ? theme.colorScheme.surfaceContainerHigh : colorFromHex(account.color);
    final foreground = account == null ? theme.colorScheme.onSurface : onColor(background);
    return Material(
      color: background,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  label: T.switchAccount,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => showAccountSheet(context),
                    onHorizontalDragEnd: (details) {
                      final v = details.primaryVelocity ?? 0;
                      if (v.abs() < 150) return;
                      state.cycleAccount(v < 0 ? 1 : -1);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
                      child: Row(
                        children: [
                          AccountAvatar(account, size: 40),
                          const SizedBox(width: AppSpacing.m),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(title, style: theme.textTheme.labelMedium?.copyWith(color: foreground.withValues(alpha: 0.8))),
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        account == null ? T.allAccounts : '@${account.username}',
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.titleMedium?.copyWith(color: foreground, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    Icon(Icons.expand_more, color: foreground),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              IconTheme(
                data: IconThemeData(color: foreground),
                child: Row(mainAxisSize: MainAxisSize.min, children: actions),
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom Sheet mit „Alle Accounts“ und jedem Account samt Status.
Future<void> showAccountSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final state = AppScope.of(sheetContext);
      final theme = Theme.of(sheetContext);
      Widget tile({required String? id, required Widget leading, required String title, required String subtitle, Color? subtitleColor}) =>
          ListTile(
            leading: leading,
            title: Text(title),
            subtitle: Text(subtitle, style: TextStyle(color: subtitleColor)),
            trailing: state.activeAccountId == id ? Icon(Icons.check, color: theme.colorScheme.primary) : null,
            onTap: () {
              state.setActiveAccount(id);
              Navigator.pop(sheetContext);
            },
          );
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.75),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.l, 0, AppSpacing.l, AppSpacing.s),
                child: Text(T.switchAccount, style: theme.textTheme.titleMedium),
              ),
              tile(id: null, leading: const AccountAvatar(null), title: T.allAccounts, subtitle: T.allAccountsHint),
              for (final a in state.accounts)
                tile(
                  id: a.id,
                  leading: AccountAvatar(a),
                  title: '@${a.username}',
                  subtitle: accountStatusText(a),
                  subtitleColor: a.isDisconnected
                      ? theme.colorScheme.error
                      : a.isExpiring
                      ? AppColors.warning
                      : null,
                ),
              if (state.accounts.isEmpty) const Padding(padding: EdgeInsets.all(AppSpacing.l), child: Text(T.noAccountsYet)),
            ],
          ),
        ),
      );
    },
  );
}
