import 'package:content_hub_server/server.dart';

/// Attrappe für Instagram, damit Tests ohne Meta-App laufen.
class FakeInstagramApi implements InstagramApi {
  String loginUserId = '1001';
  String username = 'testaccount';
  int followers = 250;
  bool failAuth = false;
  int publishUsed = 0;
  int publishLimitTotal = 50;
  final created = <Map<String, String>>[];
  final replies = <String>[];
  final hidden = <String, bool>{};
  int hashtagLookups = 0;
  List<Map<String, dynamic>> commentList = [
    {'id': 'c1', 'text': 'Tolles Bild!', 'username': 'fan1', 'timestamp': '2026-11-09T10:00:00+0000', 'hidden': false},
  ];

  void _check() {
    if (failAuth) throw InstagramApiException('Token abgelaufen', code: 190);
  }

  @override
  Uri authorizeUrl({required String loginType, required String state, required String redirectUri}) =>
      Uri.parse('https://example.invalid/auth?state=$state&type=$loginType');

  @override
  Future<TokenResult> exchangeCode({required String loginType, required String code, required String redirectUri}) async {
    if (code == 'bad') throw InstagramApiException('Code ungültig', code: 100);
    return TokenResult(
      accessToken: 'token-$code',
      expiresAt: DateTime.now().toUtc().add(const Duration(days: 60)),
      igUserId: loginUserId,
      scopes: 'instagram_business_basic',
    );
  }

  @override
  Future<List<FacebookLinkedAccount>> facebookAccounts(String userToken) async => [
    FacebookLinkedAccount(pageId: 'page1', igUserId: loginUserId, username: username),
  ];

  @override
  Future<TokenResult> refreshToken(String loginType, String token) async {
    _check();
    return TokenResult(accessToken: '$token-r', expiresAt: DateTime.now().toUtc().add(const Duration(days: 60)));
  }

  @override
  Future<Map<String, dynamic>> profile(IgAccess access) async {
    _check();
    return {
      'user_id': access.igUserId.isEmpty ? loginUserId : access.igUserId,
      'username': username,
      'account_type': 'BUSINESS',
      'followers_count': followers,
      'media_count': 2,
    };
  }

  @override
  Future<List<Map<String, dynamic>>> recentMedia(IgAccess access, {int limit = 50}) async => [
    {'id': 'm1', 'caption': 'Erster Beitrag', 'media_type': 'IMAGE', 'media_product_type': 'FEED', 'permalink': 'https://instagram.com/p/m1', 'timestamp': _ago(2)},
    {'id': 'm2', 'caption': 'Ein Reel', 'media_type': 'VIDEO', 'media_product_type': 'REELS', 'permalink': 'https://instagram.com/p/m2', 'timestamp': _ago(4)},
  ];

  static String _ago(int days) => DateTime.now().toUtc().subtract(Duration(days: days)).toIso8601String();

  @override
  Future<Map<String, num?>> mediaInsights(IgAccess access, String mediaId, {required String productType, required String mediaType}) async =>
      mediaId == 'm1' ? {'reach': 100, 'likes': 10, 'saved': 2, 'views': null} : {'reach': 300, 'likes': 40, 'saved': 9, 'ig_reels_avg_watch_time': 4200};

  @override
  Future<Map<String, num?>> accountDayInsights(IgAccess access, DateTime day) async => {
    'reach': 50,
    'views': 80,
    'total_interactions': 7,
    // Fehlender Wert: muss fehlend bleiben und darf nicht als 0 erscheinen.
    'profile_links_taps': null,
  };

  @override
  Future<List<Map<String, dynamic>>> stories(IgAccess access) async => [
    {'id': 's1', 'media_type': 'IMAGE', 'timestamp': DateTime.now().toUtc().subtract(const Duration(hours: 3)).toIso8601String()},
  ];

  @override
  Future<Map<String, num?>> storyInsights(IgAccess access, String mediaId) async => {'reach': 33, 'replies': 1};

  @override
  Future<List<Map<String, dynamic>>> comments(IgAccess access, String mediaId) async => mediaId == 'm1' ? commentList : [];

  @override
  Future<String> replyToComment(IgAccess access, String commentId, String message) async {
    _check();
    replies.add('$commentId:$message');
    return 'reply-${replies.length}';
  }

  @override
  Future<void> hideComment(IgAccess access, String commentId, bool hide) async => hidden[commentId] = hide;

  @override
  Future<String> createContainer(IgAccess access, Map<String, String> params) async {
    _check();
    created.add(params);
    return 'container-${created.length}';
  }

  @override
  Future<String> containerStatus(IgAccess access, String containerId) async => 'FINISHED';

  @override
  Future<String> publishContainer(IgAccess access, String containerId) async {
    publishUsed++;
    return 'published-$containerId';
  }

  @override
  Future<Map<String, dynamic>> mediaById(IgAccess access, String mediaId) async => {
    'id': mediaId,
    'media_type': 'IMAGE',
    'permalink': 'https://instagram.com/p/$mediaId',
  };

  @override
  Future<({int used, int limit})?> publishingLimit(IgAccess access) async => (used: publishUsed, limit: publishLimitTotal);

  @override
  Future<String> hashtagId(IgAccess access, String hashtag) async {
    hashtagLookups++;
    return 'h-$hashtag';
  }

  @override
  Future<List<Map<String, dynamic>>> hashtagMedia(IgAccess access, String hashtagId, {required bool top}) async => [
    {'id': '${top ? 't' : 'r'}-$hashtagId', 'caption': 'Beitrag zu $hashtagId', 'media_type': 'IMAGE', 'permalink': 'https://instagram.com/p/x', 'like_count': top ? 900 : 12, 'timestamp': _ago(1)},
  ];

  @override
  Future<Map<String, dynamic>> businessDiscovery(IgAccess access, String username) async {
    if (username == 'gibtsnicht') throw InstagramApiException('not found', code: 100);
    return {
      'id': 'bd-$username',
      'username': username,
      'followers_count': 5000,
      'media_count': 120,
      'media': {
        'data': [
          {'like_count': 100, 'comments_count': 10},
          {'like_count': 200, 'comments_count': 20},
        ],
      },
    };
  }
}

/// Attrappe für den KI-Dienst.
class FakeAi implements AiService {
  int calls = 0;
  String? lastPart;
  Map<String, dynamic>? lastContext;

  @override
  Future<GeneratedSuggestion> generate(Map<String, dynamic> context, {String? part}) async {
    calls++;
    lastPart = part;
    lastContext = context;
    return GeneratedSuggestion(
      format: 'reel',
      formatReason: 'Reels liefen zuletzt am besten.',
      hooks: ['Hook A$calls', 'Hook B$calls', 'Hook C$calls'],
      outline: ['Szene 1', 'Szene 2', 'Szene 3'],
      cta: 'Speichern für später ($calls)',
      captionDraft: 'Caption $calls',
      hashtags: ['#eins', '#zwei'],
      model: 'fake-model',
    );
  }
}
