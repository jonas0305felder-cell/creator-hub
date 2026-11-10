import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';

/// Zugang zu einem Instagram-Account für API-Aufrufe.
class IgAccess {
  IgAccess({
    required this.loginType,
    required this.token,
    required this.igUserId,
  });

  /// `instagram` (Instagram Login) oder `facebook` (Facebook Login).
  final String loginType;
  final String token;
  final String igUserId;

  bool get isFacebook => loginType == 'facebook';
}

class TokenResult {
  TokenResult({
    required this.accessToken,
    required this.expiresAt,
    this.igUserId,
    this.scopes = '',
  });

  final String accessToken;
  final DateTime? expiresAt;
  final String? igUserId;
  final String scopes;
}

/// Über Facebook Login gefundener Instagram-Account (hängt an einer Seite).
class FacebookLinkedAccount {
  FacebookLinkedAccount({
    required this.pageId,
    required this.igUserId,
    required this.username,
  });

  final String pageId;
  final String igUserId;
  final String username;
}

/// Fehler der Graph API.
class InstagramApiException implements Exception {
  InstagramApiException(this.message, {this.code, this.subcode, this.status});

  final String message;
  final int? code;
  final int? subcode;
  final int? status;

  /// Token abgelaufen oder Zugriff entzogen (Code 190).
  bool get isAuthError => code == 190 || code == 102;

  /// Fehlende Berechtigung (Code 10 oder 200–299).
  bool get isPermissionError =>
      code == 10 || (code != null && code! >= 200 && code! < 300);

  /// Limit erreicht (z. B. Rate-Limit oder Hashtag-Kontingent).
  bool get isLimitError => code == 4 || code == 17 || code == 32 || code == 613 || code == 9;

  @override
  String toString() => 'InstagramApiException($code/$subcode): $message';
}

/// Schnittstelle zu Instagram. In Tests durch eine Attrappe ersetzt.
abstract class InstagramApi {
  Uri authorizeUrl({
    required String loginType,
    required String state,
    required String redirectUri,
  });

  Future<TokenResult> exchangeCode({
    required String loginType,
    required String code,
    required String redirectUri,
  });

  Future<List<FacebookLinkedAccount>> facebookAccounts(String userToken);

  Future<TokenResult> refreshToken(String loginType, String token);

  Future<Map<String, dynamic>> profile(IgAccess access);

  Future<List<Map<String, dynamic>>> recentMedia(IgAccess access, {int limit = 50});

  Future<Map<String, num?>> mediaInsights(
    IgAccess access,
    String mediaId, {
    required String productType,
    required String mediaType,
  });

  /// Kennzahlen eines Tages (Zeitzone UTC) als Gesamtwert.
  Future<Map<String, num?>> accountDayInsights(IgAccess access, DateTime day);

  Future<List<Map<String, dynamic>>> stories(IgAccess access);

  Future<Map<String, num?>> storyInsights(IgAccess access, String mediaId);

  Future<List<Map<String, dynamic>>> comments(IgAccess access, String mediaId);

  Future<String> replyToComment(IgAccess access, String commentId, String message);

  Future<void> hideComment(IgAccess access, String commentId, bool hide);

  Future<String> createContainer(IgAccess access, Map<String, String> params);

  Future<String> containerStatus(IgAccess access, String containerId);

  Future<String> publishContainer(IgAccess access, String containerId);

  Future<Map<String, dynamic>> mediaById(IgAccess access, String mediaId);

  /// Verbleibende Veröffentlichungen in 24 Stunden (`null` = unbekannt).
  Future<({int used, int limit})?> publishingLimit(IgAccess access);

  Future<String> hashtagId(IgAccess access, String hashtag);

  Future<List<Map<String, dynamic>>> hashtagMedia(
    IgAccess access,
    String hashtagId, {
    required bool top,
  });

  Future<Map<String, dynamic>> businessDiscovery(IgAccess access, String username);
}

/// Echte Umsetzung gegen graph.instagram.com bzw. graph.facebook.com.
///
/// Geschrieben nach der Meta-Dokumentation (Stand 10.11.2026, v25.0). Mangels
/// Meta-App noch nicht gegen echte Accounts getestet (Spike laut
/// Spezifikation Abschnitt 8, Punkt 5).
class GraphInstagramApi implements InstagramApi {
  GraphInstagramApi(this._config, [http.Client? client])
    : _http = client ?? http.Client();

  final Config _config;
  final http.Client _http;

  static const instagramScopes = [
    'instagram_business_basic',
    'instagram_business_manage_insights',
    'instagram_business_content_publish',
    'instagram_business_manage_comments',
  ];

  static const facebookScopes = [
    'instagram_basic',
    'instagram_manage_insights',
    'instagram_content_publish',
    'instagram_manage_comments',
    'pages_show_list',
    'pages_read_engagement',
    'business_management',
  ];

  String get _v => _config.graphApiVersion;

  String _base(IgAccess a) => a.isFacebook
      ? 'https://graph.facebook.com/$_v'
      : 'https://graph.instagram.com/$_v';

  @override
  Uri authorizeUrl({
    required String loginType,
    required String state,
    required String redirectUri,
  }) {
    if (loginType == 'facebook' && _config.unifiedLogin) {
      // Unified Login: Berechtigungen stehen in der Konfiguration (config_id),
      // nicht im Parameter scope.
      return Uri.https('www.facebook.com', '/dialog/oauth', {
        'client_id': _config.facebookAppId,
        'config_id': _config.facebookConfigId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'state': state,
        // Zeigt die Anmeldung erneut an (anderen Account wählen).
        'prompt': 'login',
      });
    }
    if (loginType == 'facebook') {
      return Uri.https('www.facebook.com', '/$_v/dialog/oauth', {
        'client_id': _config.facebookAppId,
        'redirect_uri': redirectUri,
        'state': state,
        'response_type': 'code',
        'scope': facebookScopes.join(','),
      });
    }
    return Uri.https('www.instagram.com', '/oauth/authorize', {
      'client_id': _config.instagramAppId,
      'redirect_uri': redirectUri,
      'state': state,
      'response_type': 'code',
      'scope': instagramScopes.join(','),
      // Zeigt die Anmeldung erneut an, damit ein anderer Account gewählt
      // werden kann (Spezifikation 4.1, „Anderen Account verwenden“).
      'force_reauth': 'true',
    });
  }

  @override
  Future<TokenResult> exchangeCode({
    required String loginType,
    required String code,
    required String redirectUri,
  }) async {
    if (loginType == 'facebook' && _config.unifiedLogin) {
      // Liefert ein System-User-Token des Business-Portfolios; die Laufzeit
      // legt die Konfiguration fest (Standard: läuft nicht ab).
      final json = await _getJson(
        Uri.https('graph.facebook.com', '/$_v/oauth/access_token', {
          'client_id': _config.facebookAppId,
          'client_secret': _config.facebookAppSecret,
          'redirect_uri': redirectUri,
          'code': code,
        }),
      );
      return _token(json);
    }
    if (loginType == 'facebook') {
      final short = await _getJson(
        Uri.https('graph.facebook.com', '/$_v/oauth/access_token', {
          'client_id': _config.facebookAppId,
          'client_secret': _config.facebookAppSecret,
          'redirect_uri': redirectUri,
          'code': code,
        }),
      );
      final long = await _getJson(
        Uri.https('graph.facebook.com', '/$_v/oauth/access_token', {
          'grant_type': 'fb_exchange_token',
          'client_id': _config.facebookAppId,
          'client_secret': _config.facebookAppSecret,
          'fb_exchange_token': short['access_token'] as String,
        }),
      );
      return _token(long);
    }
    // Instagram Login: Code (1 h gültig) -> kurzlebiges Token -> 60-Tage-Token.
    final response = await _http.post(
      Uri.https('api.instagram.com', '/oauth/access_token'),
      body: {
        'client_id': _config.instagramAppId,
        'client_secret': _config.instagramAppSecret,
        'grant_type': 'authorization_code',
        'redirect_uri': redirectUri,
        'code': code,
      },
    );
    final short = _decode(response);
    final data = short['data'] is List ? (short['data'] as List).first as Map<String, dynamic> : short;
    final long = await _getJson(
      Uri.https('graph.instagram.com', '/access_token', {
        'grant_type': 'ig_exchange_token',
        'client_secret': _config.instagramAppSecret,
        'access_token': data['access_token'] as String,
      }),
    );
    final permissions = data['permissions'];
    return TokenResult(
      accessToken: long['access_token'] as String,
      expiresAt: _expiry(long['expires_in']),
      igUserId: data['user_id']?.toString(),
      scopes: permissions is List ? permissions.join(',') : (permissions?.toString() ?? ''),
    );
  }

  @override
  Future<List<FacebookLinkedAccount>> facebookAccounts(String userToken) async {
    if (_config.unifiedLogin) {
      // Unified Login: freigegebene Instagram-Accounts ohne Facebook-Seite.
      final json = await _getJson(
        Uri.https('graph.facebook.com', '/$_v/me/assigned_instagram_accounts', {
          'fields': 'id,username',
          'access_token': userToken,
        }),
      );
      return [
        for (final ig in (json['data'] as List? ?? const []))
          FacebookLinkedAccount(
            pageId: '',
            igUserId: (ig as Map<String, dynamic>)['id'].toString(),
            username: (ig['username'] ?? '').toString(),
          ),
      ];
    }
    final json = await _getJson(
      Uri.https('graph.facebook.com', '/$_v/me/accounts', {
        'fields': 'id,name,instagram_business_account{id,username}',
        'access_token': userToken,
      }),
    );
    final result = <FacebookLinkedAccount>[];
    for (final page in (json['data'] as List? ?? const [])) {
      final ig = (page as Map<String, dynamic>)['instagram_business_account'];
      if (ig is Map<String, dynamic>) {
        result.add(
          FacebookLinkedAccount(
            pageId: page['id'].toString(),
            igUserId: ig['id'].toString(),
            username: (ig['username'] ?? '').toString(),
          ),
        );
      }
    }
    return result;
  }

  @override
  Future<TokenResult> refreshToken(String loginType, String token) async {
    if (loginType == 'facebook' && _config.unifiedLogin) {
      // System-User-Tokens lassen sich nicht per fb_exchange_token verlängern.
      // Läuft eines ab, meldet die App „neu verbinden“.
      throw InstagramApiException('Token kann nicht verlängert werden.', code: 190);
    }
    if (loginType == 'facebook') {
      final json = await _getJson(
        Uri.https('graph.facebook.com', '/$_v/oauth/access_token', {
          'grant_type': 'fb_exchange_token',
          'client_id': _config.facebookAppId,
          'client_secret': _config.facebookAppSecret,
          'fb_exchange_token': token,
        }),
      );
      return _token(json);
    }
    final json = await _getJson(
      Uri.https('graph.instagram.com', '/refresh_access_token', {
        'grant_type': 'ig_refresh_token',
        'access_token': token,
      }),
    );
    return _token(json);
  }

  @override
  Future<Map<String, dynamic>> profile(IgAccess a) {
    final fields = a.isFacebook
        ? 'id,username,profile_picture_url,followers_count,media_count'
        : 'user_id,username,account_type,profile_picture_url,followers_count,media_count';
    return _get(a, a.isFacebook ? '/${a.igUserId}' : '/me', {'fields': fields});
  }

  @override
  Future<List<Map<String, dynamic>>> recentMedia(IgAccess a, {int limit = 50}) async {
    final json = await _get(a, '/${a.igUserId}/media', {
      'fields':
          'id,caption,media_type,media_product_type,permalink,thumbnail_url,media_url,timestamp,like_count,comments_count',
      'limit': '$limit',
    });
    return _list(json);
  }

  @override
  Future<Map<String, num?>> mediaInsights(
    IgAccess a,
    String mediaId, {
    required String productType,
    required String mediaType,
  }) async {
    final metrics = ['reach', 'views', 'likes', 'comments', 'shares', 'saved', 'total_interactions'];
    if (productType == 'REELS') metrics.add('ig_reels_avg_watch_time');
    final json = await _get(a, '/$mediaId/insights', {'metric': metrics.join(',')});
    return _insightValues(json);
  }

  @override
  Future<Map<String, num?>> accountDayInsights(IgAccess a, DateTime day) async {
    final since = DateTime.utc(day.year, day.month, day.day);
    final until = since.add(const Duration(days: 1));
    final json = await _get(a, '/${a.igUserId}/insights', {
      'metric':
          'reach,views,accounts_engaged,total_interactions,likes,comments,shares,saves,follows_and_unfollows,profile_links_taps',
      'period': 'day',
      'metric_type': 'total_value',
      'since': '${since.millisecondsSinceEpoch ~/ 1000}',
      'until': '${until.millisecondsSinceEpoch ~/ 1000}',
    });
    final values = <String, num?>{};
    for (final item in _list(json)) {
      final name = item['name'] as String;
      final total = item['total_value'];
      if (name == 'follows_and_unfollows' && total is Map) {
        // Aufgeteilt nach follow_type in breakdowns.
        num? follows;
        num? unfollows;
        for (final b in (total['breakdowns'] as List? ?? const [])) {
          for (final r in ((b as Map)['results'] as List? ?? const [])) {
            final dims = (r as Map)['dimension_values'] as List? ?? const [];
            if (dims.contains('FOLLOWER')) follows = r['value'] as num?;
            if (dims.contains('NON_FOLLOWER')) unfollows = r['value'] as num?;
          }
        }
        values['follows'] = follows;
        values['unfollows'] = unfollows;
      } else if (total is Map) {
        values[name] = total['value'] as num?;
      }
    }
    return values;
  }

  @override
  Future<List<Map<String, dynamic>>> stories(IgAccess a) async {
    final json = await _get(a, '/${a.igUserId}/stories', {
      'fields': 'id,media_type,media_product_type,permalink,thumbnail_url,media_url,timestamp,caption',
    });
    return _list(json);
  }

  @override
  Future<Map<String, num?>> storyInsights(IgAccess a, String mediaId) async {
    final json = await _get(a, '/$mediaId/insights', {
      'metric': 'reach,views,replies,navigation,follows,profile_visits,shares,total_interactions',
    });
    return _insightValues(json);
  }

  @override
  Future<List<Map<String, dynamic>>> comments(IgAccess a, String mediaId) async {
    final json = await _get(a, '/$mediaId/comments', {
      'fields': 'id,text,username,timestamp,hidden,replies{id,text,username,timestamp,hidden}',
      'limit': '50',
    });
    return _list(json);
  }

  @override
  Future<String> replyToComment(IgAccess a, String commentId, String message) async {
    final json = await _post(a, '/$commentId/replies', {'message': message});
    return json['id'].toString();
  }

  @override
  Future<void> hideComment(IgAccess a, String commentId, bool hide) async {
    await _post(a, '/$commentId', {'hide': hide ? 'true' : 'false'});
  }

  @override
  Future<String> createContainer(IgAccess a, Map<String, String> params) async {
    final json = await _post(a, '/${a.igUserId}/media', params);
    return json['id'].toString();
  }

  @override
  Future<String> containerStatus(IgAccess a, String containerId) async {
    final json = await _get(a, '/$containerId', {'fields': 'status_code'});
    return (json['status_code'] ?? 'IN_PROGRESS').toString();
  }

  @override
  Future<String> publishContainer(IgAccess a, String containerId) async {
    final json = await _post(a, '/${a.igUserId}/media_publish', {'creation_id': containerId});
    return json['id'].toString();
  }

  @override
  Future<Map<String, dynamic>> mediaById(IgAccess a, String mediaId) => _get(a, '/$mediaId', {
    'fields': 'id,caption,media_type,media_product_type,permalink,thumbnail_url,media_url,timestamp',
  });

  @override
  Future<({int used, int limit})?> publishingLimit(IgAccess a) async {
    final json = await _get(a, '/${a.igUserId}/content_publishing_limit', {
      'fields': 'quota_usage,config',
    });
    final data = _list(json);
    if (data.isEmpty) return null;
    final used = (data.first['quota_usage'] as num?)?.toInt();
    final total = ((data.first['config'] as Map?)?['quota_total'] as num?)?.toInt();
    if (used == null || total == null) return null;
    return (used: used, limit: total);
  }

  @override
  Future<String> hashtagId(IgAccess a, String hashtag) async {
    final json = await _get(a, '/ig_hashtag_search', {'user_id': a.igUserId, 'q': hashtag});
    final data = _list(json);
    if (data.isEmpty) throw InstagramApiException('Hashtag nicht gefunden.');
    return data.first['id'].toString();
  }

  @override
  Future<List<Map<String, dynamic>>> hashtagMedia(IgAccess a, String hashtagId, {required bool top}) async {
    final json = await _get(a, '/$hashtagId/${top ? 'top_media' : 'recent_media'}', {
      'user_id': a.igUserId,
      'fields': 'id,caption,media_type,permalink,like_count,comments_count,timestamp',
      'limit': '25',
    });
    return _list(json);
  }

  @override
  Future<Map<String, dynamic>> businessDiscovery(IgAccess a, String username) async {
    final json = await _get(a, '/${a.igUserId}', {
      'fields':
          'business_discovery.username($username){id,username,followers_count,media_count,media.limit(12){like_count,comments_count,timestamp}}',
    });
    final bd = json['business_discovery'];
    if (bd is! Map<String, dynamic>) {
      throw InstagramApiException('Account nicht gefunden oder nicht professionell.');
    }
    return bd;
  }

  // ---------------------------------------------------------------------

  Future<Map<String, dynamic>> _get(IgAccess a, String path, Map<String, String> query) =>
      _getJson(Uri.parse('${_base(a)}$path').replace(queryParameters: {...query, 'access_token': a.token}));

  Future<Map<String, dynamic>> _post(IgAccess a, String path, Map<String, String> body) async {
    final response = await _http.post(
      Uri.parse('${_base(a)}$path'),
      body: {...body, 'access_token': a.token},
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async => _decode(await _http.get(uri));

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> json;
    try {
      json = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw InstagramApiException('Unerwartete Antwort von Instagram.', status: response.statusCode);
    }
    final error = json['error'];
    if (error is Map) {
      throw InstagramApiException(
        (error['message'] ?? 'Instagram-Fehler').toString(),
        code: (error['code'] as num?)?.toInt(),
        subcode: (error['error_subcode'] as num?)?.toInt(),
        status: response.statusCode,
      );
    }
    if (response.statusCode >= 400) {
      throw InstagramApiException('Instagram-Fehler ${response.statusCode}', status: response.statusCode);
    }
    return json;
  }

  static List<Map<String, dynamic>> _list(Map<String, dynamic> json) => [
    for (final e in (json['data'] as List? ?? const [])) e as Map<String, dynamic>,
  ];

  static Map<String, num?> _insightValues(Map<String, dynamic> json) {
    final out = <String, num?>{};
    for (final item in _list(json)) {
      final values = item['values'] as List?;
      final total = item['total_value'];
      num? value;
      if (values != null && values.isNotEmpty) value = (values.last as Map)['value'] as num?;
      if (value == null && total is Map) value = total['value'] as num?;
      out[item['name'] as String] = value;
    }
    return out;
  }

  static TokenResult _token(Map<String, dynamic> json) => TokenResult(
    accessToken: json['access_token'] as String,
    expiresAt: _expiry(json['expires_in']),
  );

  static DateTime? _expiry(Object? expiresIn) {
    final seconds = expiresIn is num ? expiresIn.toInt() : int.tryParse('$expiresIn');
    if (seconds == null || seconds <= 0) return null;
    return DateTime.now().toUtc().add(Duration(seconds: seconds));
  }
}
