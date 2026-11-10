import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

/// Ein Eintrag aus einem RSS- oder Atom-Feed.
class FeedItem {
  FeedItem({
    required this.id,
    required this.title,
    required this.link,
    required this.summary,
    required this.publishedAt,
  });

  final String id;
  final String title;
  final String? link;
  final String summary;
  final DateTime? publishedAt;
}

/// Liest RSS-2.0- und Atom-Feeds (Trendquelle laut Spezifikation 7.4).
class RssService {
  RssService([http.Client? client]) : _http = client ?? http.Client();

  final http.Client _http;

  Future<List<FeedItem>> fetch(String url) async {
    final response = await _http
        .get(Uri.parse(url), headers: {'user-agent': 'ContentHub-Feedreader/1.0'})
        .timeout(const Duration(seconds: 20));
    if (response.statusCode >= 400) {
      throw Exception('Feed antwortet mit Status ${response.statusCode}');
    }
    return parse(response.body);
  }

  static List<FeedItem> parse(String xmlText) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(xmlText);
    } on XmlException {
      throw Exception('Feed ist kein gültiges RSS/Atom.');
    }
    final items = <FeedItem>[];
    for (final item in doc.findAllElements('item')) {
      final title = _text(item, 'title');
      if (title.isEmpty) continue;
      final link = _text(item, 'link');
      final guid = _text(item, 'guid');
      items.add(
        FeedItem(
          id: guid.isNotEmpty ? guid : (link.isNotEmpty ? link : title),
          title: title,
          link: link.isEmpty ? null : link,
          summary: _clean(_text(item, 'description')),
          publishedAt: parseDate(_text(item, 'pubDate').isNotEmpty ? _text(item, 'pubDate') : _text(item, 'dc:date')),
        ),
      );
    }
    for (final entry in doc.findAllElements('entry')) {
      final title = _text(entry, 'title');
      if (title.isEmpty) continue;
      final linkEl = entry.findElements('link').where((l) => l.getAttribute('rel') != 'self').firstOrNull;
      final link = linkEl?.getAttribute('href');
      final id = _text(entry, 'id');
      final date = _text(entry, 'published').isNotEmpty ? _text(entry, 'published') : _text(entry, 'updated');
      items.add(
        FeedItem(
          id: id.isNotEmpty ? id : (link ?? title),
          title: title,
          link: link,
          summary: _clean(_text(entry, 'summary').isNotEmpty ? _text(entry, 'summary') : _text(entry, 'content')),
          publishedAt: parseDate(date),
        ),
      );
    }
    return items;
  }

  static String _text(XmlElement parent, String name) =>
      parent.findElements(name).firstOrNull?.innerText.trim() ?? '';

  static String _clean(String html) {
    final text = html
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return text.length > 400 ? '${text.substring(0, 397)}…' : text;
  }

  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  /// Versteht ISO 8601 (Atom) und RFC 822 (RSS), z. B.
  /// `Tue, 10 Nov 2026 06:00:00 +0100`.
  static DateTime? parseDate(String value) {
    if (value.isEmpty) return null;
    final iso = DateTime.tryParse(value);
    if (iso != null) return iso.toUtc();
    final m = RegExp(
      r'(\d{1,2})\s+([A-Za-z]{3})\w*\s+(\d{2,4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([+-]\d{4}|[A-Z]{1,4})?',
    ).firstMatch(value);
    if (m == null) return null;
    final month = _months[m.group(2)!.toLowerCase()];
    if (month == null) return null;
    var year = int.parse(m.group(3)!);
    if (year < 100) year += 2000;
    var date = DateTime.utc(
      year,
      month,
      int.parse(m.group(1)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.parse(m.group(6) ?? '0'),
    );
    final zone = m.group(7);
    if (zone != null && (zone.startsWith('+') || zone.startsWith('-'))) {
      final sign = zone.startsWith('-') ? -1 : 1;
      final hours = int.parse(zone.substring(1, 3));
      final minutes = int.parse(zone.substring(3, 5));
      date = date.subtract(Duration(minutes: sign * (hours * 60 + minutes)));
    }
    return date;
  }
}
