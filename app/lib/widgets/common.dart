import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../config/app_texts.dart';
import '../config/app_theme.dart';
import '../models/models.dart';
import '../services/api_client.dart';

// ---------------------------------------------------------------------
// Formatierung
// ---------------------------------------------------------------------

final _number = NumberFormat.decimalPattern('de');
final _compact = NumberFormat.compact(locale: 'de');

/// Zahl mit Tausenderpunkt; fehlende Werte als „–“, nie als 0.
String formatNumber(num? value) => value == null ? '–' : _number.format(value);

/// Kurze Zahl, z. B. 12.400 → „12.400“, 1.250.000 → „1,3 Mio.“.
String formatCompact(num? value) => value == null ? '–' : (value.abs() < 100000 ? _number.format(value) : _compact.format(value));

String formatDate(DateTime? d) => d == null ? '–' : DateFormat('dd.MM.yyyy', 'de').format(d);
String formatDateTime(DateTime? d) => d == null ? '–' : DateFormat('dd.MM., HH:mm', 'de').format(d);
String formatTime(DateTime d) => DateFormat('HH:mm', 'de').format(d);
String formatDayShort(DateTime d) => DateFormat('dd.MM.', 'de').format(d);
String formatWeekday(DateTime d) => DateFormat('EEE dd.MM.', 'de').format(d);
String formatMonth(DateTime d) => DateFormat('MMMM yyyy', 'de').format(d);

/// „vor 3 Tagen“, „vor 2 Stunden“ …
String formatAgo(DateTime d, [DateTime? now]) {
  final diff = (now ?? DateTime.now()).difference(d);
  if (diff.inMinutes < 1) return 'gerade eben';
  if (diff.inMinutes < 60) return 'vor ${diff.inMinutes} Min.';
  if (diff.inHours < 24) return 'vor ${diff.inHours} ${diff.inHours == 1 ? 'Stunde' : 'Stunden'}';
  return 'vor ${diff.inDays} ${diff.inDays == 1 ? 'Tag' : 'Tagen'}';
}

/// Dauer in Millisekunden als „4,2 s“.
String formatSeconds(num? ms) => ms == null ? '–' : '${NumberFormat('0.0', 'de').format(ms / 1000)} s';

String statusLabel(String status) => switch (status) {
  'idea' => T.statusIdea,
  'in_progress' => T.statusInProgress,
  'ready' => T.statusReady,
  'published' => T.statusPublished,
  'discarded' => T.statusDiscarded,
  _ => status,
};

String formatLabel(String? format) => switch (format) {
  'reel' => T.formatReel,
  'carousel' => T.formatCarousel,
  'image' => T.formatImage,
  'story' => T.formatStory,
  'post' => T.formatPost,
  _ => T.noFormat,
};

/// Format eines Instagram-Beitrags aus den API-Feldern.
String mediaFormatLabel(Map<String, dynamic> media) {
  if (media['media_product_type'] == 'reels') return T.formatReel;
  if (media['media_product_type'] == 'story') return T.formatStory;
  return switch (media['media_type']) {
    'CAROUSEL_ALBUM' => T.formatCarousel,
    'VIDEO' => T.formatVideo,
    _ => T.formatImage,
  };
}

String postStatusLabel(String status) => switch (status) {
  'draft' => T.postDraft,
  'scheduled' => T.postScheduled,
  'publishing' => T.postPublishing,
  'published' => T.postPublished,
  'failed' => T.postFailed,
  _ => status,
};

String accountStatusText(Account a, [DateTime? now]) => switch (a.status) {
  'manual' => T.statusManual,
  'disconnected' => T.statusDisconnected,
  'syncing' => T.statusSyncing,
  'expiring' =>
    a.daysUntilExpiry(now ?? DateTime.now()) == null ? T.statusExpiringSoon : T.statusExpiring(a.daysUntilExpiry(now ?? DateTime.now())!),
  _ => T.statusConnected,
};

// ---------------------------------------------------------------------
// Aktionen
// ---------------------------------------------------------------------

void showMessage(BuildContext context, String text) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(SnackBar(content: Text(text)));
}

void showError(BuildContext context, Object error) => showMessage(context, error is ApiException ? error.message : T.errorUnknown);

Future<void> copyText(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showMessage(context, T.copied);
}

Future<void> openLink(BuildContext context, String? url) async {
  final uri = Uri.tryParse(url ?? '');
  if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) return;
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) showMessage(context, T.errorUnknown);
}

Future<bool> confirm(BuildContext context, {required String title, required String text, String? action, bool danger = false}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(text),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text(T.cancel)),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error) : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(action ?? T.delete),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Führt eine Aktion aus und zeigt Fehler als Hinweis. Liefert true bei Erfolg.
Future<bool> guarded(BuildContext context, Future<void> Function() action, {String? success}) async {
  try {
    await action();
    if (success != null && context.mounted) showMessage(context, success);
    return true;
  } catch (e) {
    if (context.mounted) showError(context, e);
    return false;
  }
}

// ---------------------------------------------------------------------
// Zustände: Laden, leer, Fehler
// ---------------------------------------------------------------------

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label});
  final String? label;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (label != null) ...[const SizedBox(height: AppSpacing.l), Text(label!, textAlign: TextAlign.center)],
        ],
      ),
    ),
  );
}

/// Leerer Zustand mit Erklärung statt Platzhalterdaten.
class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.text, this.icon = Icons.inbox_outlined, this.title, this.action, this.actionLabel});
  final String text;
  final IconData icon;
  final String? title;
  final VoidCallback? action;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: theme.colorScheme.outline),
              const SizedBox(height: AppSpacing.m),
              if (title != null) ...[
                Text(title!, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.s),
              ],
              Text(
                text,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (action != null) ...[
                const SizedBox(height: AppSpacing.l),
                FilledButton(onPressed: action, child: Text(actionLabel ?? T.add)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => EmptyView(
    icon: Icons.error_outline,
    title: T.errorTitle,
    text: error is ApiException ? (error as ApiException).message : T.errorUnknown,
    action: onRetry,
    actionLabel: T.retry,
  );
}

/// Lädt Daten und zeigt Lade-, Fehler- oder Inhaltszustand.
///
/// `key` wechseln (z. B. mit der Account-ID), um neu zu laden. Über
/// [AsyncViewState.reload] lässt sich von außen aktualisieren.
class AsyncView<D> extends StatefulWidget {
  const AsyncView({super.key, required this.load, required this.builder});
  final Future<D> Function() load;
  final Widget Function(BuildContext context, D data, Future<void> Function() reload) builder;

  @override
  State<AsyncView<D>> createState() => AsyncViewState<D>();
}

class AsyncViewState<D> extends State<AsyncView<D>> {
  D? _data;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    if (_data == null) setState(() => _loading = true);
    try {
      final data = await widget.load();
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // Bereits gezeigte Daten bleiben stehen; der Fehler erscheint als Hinweis.
      if (_data != null) {
        showError(context, e);
        setState(() => _loading = false);
      } else {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data != null) return widget.builder(context, data, reload);
    if (_loading) return const LoadingView();
    return ErrorView(error: _error ?? T.errorUnknown, onRetry: reload);
  }
}

// ---------------------------------------------------------------------
// Bausteine
// ---------------------------------------------------------------------

/// Begrenzt die Inhaltsbreite auf großen Bildschirmen.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: AppConfig.maxContentWidth),
      child: child,
    ),
  );
}

/// Scrollbare Seite mit einheitlichem Rand, Pull-to-Refresh und Platz für
/// den Plus-Button.
class PageList extends StatelessWidget {
  const PageList({super.key, required this.children, this.onRefresh, this.bottomSpace = false});
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final bool bottomSpace;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.m, AppSpacing.l, bottomSpace ? 96 : AppSpacing.xl),
      children: children,
    );
    return ContentWidth(
      child: onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, child: list),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.xl, bottom: AppSpacing.s),
    child: Row(
      children: [
        Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium)),
        ?trailing,
      ],
    ),
  );
}

/// Sichtbarer Datenstand: „Stand: 10.11., 06:00“.
class DataStamp extends StatelessWidget {
  const DataStamp(this.when, {super.key});
  final DateTime? when;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.schedule, size: 14, color: theme.colorScheme.outline),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            when == null ? T.dataNever : T.dataAsOf(formatDateTime(when)),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// Hinweis-Kasten (Info, Warnung oder Fehler).
class Notice extends StatelessWidget {
  const Notice(this.text, {super.key, this.icon = Icons.info_outline, this.color, this.action, this.actionLabel});
  final String text;
  final IconData icon;
  final Color? color;
  final VoidCallback? action;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.s),
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: c),
          const SizedBox(width: AppSpacing.m),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
          if (action != null) TextButton(onPressed: action, child: Text(actionLabel ?? T.open)),
        ],
      ),
    );
  }
}

/// Profilbild bzw. Anfangsbuchstabe mit Farbring des Accounts.
class AccountAvatar extends StatelessWidget {
  const AccountAvatar(this.account, {super.key, this.size = 36});
  final Account? account;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = account;
    final color = a == null ? theme.colorScheme.primary : colorFromHex(a.color);
    final letter = a == null ? null : (a.username.isEmpty ? '?' : a.username[0].toUpperCase());
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      child: CircleAvatar(
        backgroundColor: theme.colorScheme.surface,
        foregroundImage: a?.pictureUrl == null ? null : NetworkImage(a!.pictureUrl!),
        // Lädt das Bild nicht, bleibt der Buchstabe sichtbar.
        onForegroundImageError: a?.pictureUrl == null ? null : (_, _) {},
        child: letter == null
            ? Icon(Icons.apps, size: size * 0.5, color: color)
            : Text(
                letter,
                style: TextStyle(fontSize: size * 0.4, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface),
              ),
      ),
    );
  }
}

/// Kleiner farbiger Punkt mit Handle, für Karten in Mischansichten.
class AccountTag extends StatelessWidget {
  const AccountTag(this.account, {super.key});
  final Account? account;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = account;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(shape: BoxShape.circle, color: a == null ? theme.colorScheme.outlineVariant : colorFromHex(a.color)),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            a == null ? T.noAccount : '@${a.username}',
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurface)),
    );
  }
}

/// Veränderung in Prozent mit Pfeil; ohne Vergleichswert bleibt es leer.
class ChangeBadge extends StatelessWidget {
  const ChangeBadge(this.percent, {super.key, this.label});
  final double? percent;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = percent;
    if (p == null) return const SizedBox.shrink();
    final up = p >= 0;
    final color = p.abs() < 0.5 ? theme.colorScheme.outline : (up ? AppColors.positive : AppColors.negative);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(up ? Icons.arrow_upward : Icons.arrow_downward, size: 13, color: color),
        Flexible(
          child: Text(
            '${p.abs().toStringAsFixed(0)} %${label == null ? '' : ' $label'}',
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// Kachel mit einer Kennzahl. Fehlende Werte erscheinen als „keine Daten“.
class MetricTile extends StatelessWidget {
  const MetricTile({super.key, required this.label, required this.value, this.change, this.changeLabel, this.sub});
  final String label;
  final num? value;
  final double? change;
  final String? changeLabel;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 2),
            if (value == null)
              Text(T.noData, style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.outline))
            else
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(formatCompact(value), style: theme.textTheme.titleLarge),
              ),
            if (change != null) ChangeBadge(change, label: changeLabel),
            if (sub != null) Text(sub!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

/// Raster, das je nach Breite 2 bis 4 Kacheln nebeneinander zeigt.
class TileGrid extends StatelessWidget {
  const TileGrid({super.key, required this.children, this.minTileWidth = 150});
  final List<Widget> children;
  final double minTileWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = (constraints.maxWidth / minTileWidth).floor().clamp(2, 4);
      final width = (constraints.maxWidth - (columns - 1) * AppSpacing.s) / columns;
      return Wrap(
        spacing: AppSpacing.s,
        runSpacing: AppSpacing.s,
        children: [for (final c in children) SizedBox(width: width, child: c)],
      );
    },
  );
}

/// Vorschaubild eines Beitrags mit Platzhalter, falls es nicht lädt.
class MediaThumb extends StatelessWidget {
  const MediaThumb(this.url, {super.key, this.size = 56});
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placeholder = Container(
      width: size,
      height: size,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(Icons.image_outlined, color: theme.colorScheme.outline, size: size * 0.45),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: url == null
          ? placeholder
          : Image.network(url!, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder),
    );
  }
}

/// Fragt Datum und Uhrzeit ab. Liefert `null` bei Abbruch.
Future<DateTime?> pickDateTime(BuildContext context, {DateTime? initial, bool allowPast = false}) async {
  final now = DateTime.now();
  final start = initial ?? now.add(const Duration(hours: 1));
  final date = await showDatePicker(
    context: context,
    initialDate: start,
    firstDate: allowPast
        ? DateTime(now.year - 2)
        : DateTime(now.year, now.month, now.day).isAfter(start)
        ? start
        : DateTime(now.year, now.month, now.day),
    lastDate: DateTime(now.year + 2),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(start));
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}
