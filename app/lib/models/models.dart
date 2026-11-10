import '../config/app_config.dart';

/// Datenklassen der App. Sie lesen die JSON-Antworten des Servers.

DateTime? parseDate(Object? value) => value is String && value.isNotEmpty ? DateTime.tryParse(value)?.toLocal() : null;

List<String> stringList(Object? value) => [for (final v in (value as List? ?? const [])) v.toString()];

class Niche {
  Niche({required this.id, required this.name, required this.keywords, required this.language, required this.region});

  factory Niche.fromJson(Map<String, dynamic> j) => Niche(
    id: j['id'] as String,
    name: j['name'] as String,
    keywords: stringList(j['keywords']),
    language: (j['language'] ?? 'de') as String,
    region: (j['region'] ?? 'DE') as String,
  );

  final String id;
  final String name;
  final List<String> keywords;
  final String language;
  final String region;
}

class Account {
  Account({
    required this.id,
    required this.username,
    required this.type,
    required this.color,
    required this.status,
    required this.nicheIds,
    this.primaryNicheId,
    this.pictureUrl,
    this.tone = '',
    this.audienceNote = '',
    this.language = 'de',
    this.followers,
    this.lastSyncedAt,
    this.lastSyncError,
    this.tokenExpiresAt,
    this.loginType,
  });

  factory Account.fromJson(Map<String, dynamic> j) {
    final niches = (j['niches'] as List? ?? const []).cast<Map>();
    return Account(
      id: j['id'] as String,
      username: j['username'] as String,
      type: j['account_type'] as String,
      color: (j['color'] ?? '#6C4CF1') as String,
      status: j['connection_status'] as String,
      nicheIds: [for (final n in niches) n['niche_id'] as String],
      primaryNicheId: niches.where((n) => n['is_primary'] == true).map((n) => n['niche_id'] as String).firstOrNull,
      pictureUrl: j['profile_picture_url'] as String?,
      tone: (j['tone'] ?? '') as String,
      audienceNote: (j['audience_note'] ?? '') as String,
      language: (j['language'] ?? 'de') as String,
      followers: j['followers_count'] as int?,
      lastSyncedAt: parseDate(j['last_synced_at']),
      lastSyncError: j['last_sync_error'] as String?,
      tokenExpiresAt: parseDate(j['token_expires_at']),
      loginType: j['login_type'] as String?,
    );
  }

  final String id;
  final String username;

  /// `business`, `creator` oder `manual`.
  final String type;
  final String color;

  /// `connected`, `expiring`, `disconnected`, `manual` oder `syncing`.
  final String status;
  final List<String> nicheIds;
  final String? primaryNicheId;
  final String? pictureUrl;
  final String tone;
  final String audienceNote;
  final String language;
  final int? followers;
  final DateTime? lastSyncedAt;
  final String? lastSyncError;
  final DateTime? tokenExpiresAt;

  /// `instagram` oder `facebook` (null bei manuellen Accounts).
  final String? loginType;

  bool get isManual => type == 'manual';
  bool get isDisconnected => status == 'disconnected';
  bool get isExpiring => status == 'expiring';
  bool get canPublish => !isManual && !isDisconnected;
  bool get hasFacebookLogin => loginType == 'facebook';

  /// Tage bis zum Ablauf der Verbindung (null, wenn unbekannt).
  int? daysUntilExpiry(DateTime now) => tokenExpiresAt?.difference(now).inDays;

  /// Daten älter als [AppConfig.staleAfter]?
  bool isStale(DateTime now) => !isManual && lastSyncedAt != null && now.difference(lastSyncedAt!) > AppConfig.staleAfter;
}

class Attachment {
  Attachment({required this.id, required this.type, this.url});

  factory Attachment.fromJson(Map<String, dynamic> j) =>
      Attachment(id: j['id'] as String, type: j['type'] as String, url: j['url'] as String?);

  final String id;

  /// `image`, `audio` oder `link`.
  final String type;
  final String? url;
}

class Suggestion {
  Suggestion({
    required this.id,
    required this.version,
    required this.format,
    required this.formatReason,
    required this.hooks,
    required this.outline,
    required this.cta,
    required this.caption,
    required this.hashtags,
    required this.isSelected,
    this.createdAt,
  });

  factory Suggestion.fromJson(Map<String, dynamic> j) => Suggestion(
    id: j['id'] as String,
    version: j['version'] as int,
    format: j['format'] as String?,
    formatReason: (j['format_reason'] ?? '') as String,
    hooks: stringList(j['hooks']),
    outline: stringList(j['outline']),
    cta: (j['cta'] ?? '') as String,
    caption: (j['caption_draft'] ?? '') as String,
    hashtags: stringList(j['hashtags']),
    isSelected: j['is_selected'] == true,
    createdAt: parseDate(j['created_at']),
  );

  final String id;
  final int version;
  final String? format;
  final String formatReason;
  final List<String> hooks;
  final List<String> outline;
  final String cta;
  final String caption;
  final List<String> hashtags;
  final bool isSelected;
  final DateTime? createdAt;

  /// Caption mit angehängten Hashtags, fertig zum Kopieren.
  String get captionWithHashtags => hashtags.isEmpty ? caption : '$caption\n\n${hashtags.join(' ')}';

  /// Ganzer Vorschlag als Text zum Kopieren oder Teilen.
  String asText({required String hooksLabel, required String outlineLabel, required String ctaLabel, required String captionLabel}) => [
    '$hooksLabel:\n${hooks.map((h) => '• $h').join('\n')}',
    '$outlineLabel:\n${[for (var i = 0; i < outline.length; i++) '${i + 1}. ${outline[i]}'].join('\n')}',
    '$ctaLabel:\n$cta',
    '$captionLabel:\n$captionWithHashtags',
  ].join('\n\n');
}

class Idea {
  Idea({
    required this.id,
    required this.title,
    required this.note,
    required this.status,
    required this.tags,
    required this.attachments,
    required this.suggestions,
    required this.updatedAt,
    this.accountId,
    this.nicheId,
    this.format,
    this.plannedFor,
    this.assigneeId,
    this.assigneeName,
    this.sourceTrendId,
    this.sourceTrendTitle,
    this.sourceMediaId,
    this.sourceMediaCaption,
    this.publishedMediaId,
    this.publishedPermalink,
  });

  factory Idea.fromJson(Map<String, dynamic> j) => Idea(
    id: j['id'] as String,
    title: (j['title'] ?? '') as String,
    note: (j['note'] ?? '') as String,
    status: j['status'] as String,
    tags: stringList(j['tags']),
    attachments: [for (final a in (j['attachments'] as List? ?? const [])) Attachment.fromJson(Map<String, dynamic>.from(a as Map))],
    suggestions: [for (final s in (j['suggestions'] as List? ?? const [])) Suggestion.fromJson(Map<String, dynamic>.from(s as Map))],
    updatedAt: parseDate(j['updated_at']) ?? DateTime.now(),
    accountId: j['account_id'] as String?,
    nicheId: j['niche_id'] as String?,
    format: j['format'] as String?,
    plannedFor: parseDate(j['planned_for']),
    assigneeId: j['assignee_id'] as String?,
    assigneeName: j['assignee_name'] as String?,
    sourceTrendId: j['source_trend_id'] as String?,
    sourceTrendTitle: j['source_trend_title'] as String?,
    sourceMediaId: j['source_media_id'] as String?,
    sourceMediaCaption: j['source_media_caption'] as String?,
    publishedMediaId: j['published_media_id'] as String?,
    publishedPermalink: j['published_permalink'] as String?,
  );

  /// Reihenfolge der Status im Kanban.
  static const statuses = ['idea', 'in_progress', 'ready', 'published', 'discarded'];
  static const formats = ['reel', 'carousel', 'image', 'story'];

  final String id;
  final String title;
  final String note;
  final String status;
  final List<String> tags;
  final List<Attachment> attachments;

  /// Neueste Version zuerst.
  final List<Suggestion> suggestions;
  final DateTime updatedAt;
  final String? accountId;
  final String? nicheId;
  final String? format;
  final DateTime? plannedFor;
  final String? assigneeId;
  final String? assigneeName;
  final String? sourceTrendId;
  final String? sourceTrendTitle;
  final String? sourceMediaId;
  final String? sourceMediaCaption;
  final String? publishedMediaId;
  final String? publishedPermalink;

  /// Der ausgewählte Vorschlag, sonst der neueste.
  Suggestion? get activeSuggestion => suggestions.where((s) => s.isSelected).firstOrNull ?? suggestions.firstOrNull;

  /// Volltextsuche über Titel, Notiz, Tags und Vorschlag.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final s = activeSuggestion;
    final haystack = [
      title,
      note,
      ...tags,
      if (s != null) ...[s.caption, s.cta, ...s.hooks, ...s.outline],
    ].join(' ').toLowerCase();
    return q.split(RegExp(r'\s+')).every(haystack.contains);
  }
}

/// Filter und Sortierung der Ideenliste.
class IdeaFilter {
  const IdeaFilter({this.query = '', this.accountId, this.nicheId, this.format, this.status, this.tag, this.sortByPlanned = false});

  final String query;
  final String? accountId;
  final String? nicheId;
  final String? format;
  final String? status;
  final String? tag;
  final bool sortByPlanned;

  /// Anzahl gesetzter Filter (ohne Suche und Account-Kontext).
  int get activeCount => [nicheId, format, status, tag].where((v) => v != null).length;

  List<Idea> apply(Iterable<Idea> ideas) {
    final result = ideas.where((i) {
      if (accountId != null && i.accountId != accountId) return false;
      if (nicheId != null && i.nicheId != nicheId) return false;
      if (format != null && i.format != format) return false;
      if (status != null && i.status != status) return false;
      if (tag != null && !i.tags.contains(tag)) return false;
      return i.matches(query);
    }).toList();
    if (sortByPlanned) {
      // Ideen ohne Termin ans Ende.
      result.sort((a, b) {
        if (a.plannedFor == null && b.plannedFor == null) return b.updatedAt.compareTo(a.updatedAt);
        if (a.plannedFor == null) return 1;
        if (b.plannedFor == null) return -1;
        return a.plannedFor!.compareTo(b.plannedFor!);
      });
    } else {
      result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }
    return result;
  }
}

enum Freshness { fresh, older, stale }

class Trend {
  Trend({
    required this.id,
    required this.title,
    required this.summary,
    required this.reason,
    required this.sourceName,
    required this.sourceType,
    required this.nicheIds,
    required this.fetchedAt,
    this.sourceUrl,
    this.publishedAt,
    this.signalValue,
    this.signalUnit,
    this.createdByName,
  });

  factory Trend.fromJson(Map<String, dynamic> j) => Trend(
    id: j['id'] as String,
    title: j['title'] as String,
    summary: (j['summary'] ?? '') as String,
    reason: (j['reason'] ?? '') as String,
    sourceName: (j['source_name'] ?? '') as String,
    sourceType: (j['source_type'] ?? 'manual') as String,
    nicheIds: stringList(j['niche_ids']),
    fetchedAt: parseDate(j['fetched_at']) ?? DateTime.now(),
    sourceUrl: j['source_url'] as String?,
    publishedAt: parseDate(j['published_at']),
    signalValue: j['signal_value'] as num?,
    signalUnit: j['signal_unit'] as String?,
    createdByName: j['created_by_name'] as String?,
  );

  final String id;
  final String title;
  final String summary;
  final String reason;
  final String sourceName;
  final String sourceType;
  final List<String> nicheIds;
  final DateTime fetchedAt;
  final String? sourceUrl;
  final DateTime? publishedAt;
  final num? signalValue;
  final String? signalUnit;
  final String? createdByName;

  /// Maßgebliches Datum: Veröffentlichung, sonst Abruf.
  DateTime get date => publishedAt ?? fetchedAt;

  /// aktuell (< 7 Tage), älter (7–30 Tage), veraltet (> 30 Tage).
  Freshness freshness(DateTime now) {
    final days = now.difference(date).inDays;
    if (days < AppConfig.trendFreshDays) return Freshness.fresh;
    if (days <= AppConfig.trendOldDays) return Freshness.older;
    return Freshness.stale;
  }
}

class TrendSource {
  TrendSource({required this.id, required this.type, required this.name, this.url, this.nicheId, this.lastSuccessAt, this.lastError});

  factory TrendSource.fromJson(Map<String, dynamic> j) => TrendSource(
    id: j['id'] as String,
    type: j['type'] as String,
    name: j['name'] as String,
    url: j['url'] as String?,
    nicheId: j['niche_id'] as String?,
    lastSuccessAt: parseDate(j['last_success_at']),
    lastError: j['last_error'] as String?,
  );

  final String id;
  final String type;
  final String name;
  final String? url;
  final String? nicheId;
  final DateTime? lastSuccessAt;
  final String? lastError;

  bool get isDisturbed => lastError != null;
}

class ScheduledPost {
  ScheduledPost({
    required this.id,
    required this.accountId,
    required this.format,
    required this.caption,
    required this.scheduledFor,
    required this.status,
    this.ideaId,
    this.ideaTitle,
    this.permalink,
    this.errorMessage,
  });

  factory ScheduledPost.fromJson(Map<String, dynamic> j) => ScheduledPost(
    id: j['id'] as String,
    accountId: j['account_id'] as String,
    format: j['format'] as String,
    caption: (j['caption'] ?? '') as String,
    scheduledFor: parseDate(j['scheduled_for']) ?? DateTime.now(),
    status: j['status'] as String,
    ideaId: j['idea_id'] as String?,
    ideaTitle: j['idea_title'] as String?,
    permalink: j['published_permalink'] as String?,
    errorMessage: j['error_message'] as String?,
  );

  final String id;
  final String accountId;

  /// `post`, `reel` oder `carousel`.
  final String format;
  final String caption;
  final DateTime scheduledFor;

  /// `draft` (nur Planung), `scheduled`, `publishing`, `published`, `failed`.
  final String status;
  final String? ideaId;
  final String? ideaTitle;
  final String? permalink;
  final String? errorMessage;

  bool get canMove => status == 'draft' || status == 'scheduled' || status == 'failed';

  /// Kurzer Titel für Kalenderzellen.
  String label(String fallback) {
    final text = (ideaTitle?.isNotEmpty ?? false) ? ideaTitle! : caption.replaceAll('\n', ' ').trim();
    return text.isEmpty ? fallback : text;
  }
}

/// Verschiebt einen Termin auf einen anderen Tag und behält die Uhrzeit.
DateTime moveToDay(DateTime original, DateTime day) => DateTime(day.year, day.month, day.day, original.hour, original.minute);

/// Veränderung in Prozent gegenüber dem Vorzeitraum (null, wenn nicht berechenbar).
double? percentChange(num? current, num? previous) {
  if (current == null || previous == null || previous == 0) return null;
  return (current - previous) / previous * 100;
}
