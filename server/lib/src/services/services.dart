import '../config.dart';
import '../db.dart';
import '../http_utils.dart';
import '../instagram/instagram_api.dart';
import '../security.dart';
import '../storage.dart';
import 'ai_service.dart';
import 'rss_service.dart';

/// Bündelt alle Abhängigkeiten, damit Routen und Jobs sie einfach finden.
class Services {
  Services({
    required this.config,
    required this.db,
    required this.security,
    required this.instagram,
    required this.ai,
    required this.rss,
    required this.storage,
    DateTime Function()? clock,
  }) : now = clock ?? (() => DateTime.now().toUtc());

  final Config config;
  final Db db;
  final Security security;
  final InstagramApi instagram;
  final AiService ai;
  final RssService rss;
  final MediaStorage storage;

  /// Aktuelle Zeit (in Tests austauschbar).
  final DateTime Function() now;

  /// Lädt und entschlüsselt den Instagram-Zugang eines Accounts.
  Future<IgAccess> access(String accountId) async {
    final row = await db.one(
      '''SELECT a.ig_user_id, c.encrypted_access_token, c.login_type
         FROM instagram_accounts a JOIN instagram_credentials c ON c.account_id = a.id
         WHERE a.id = @id''',
      {'id': accountId},
    );
    if (row == null) {
      throw ApiError(409, 'no_connection', 'Dieser Account ist nicht mit Instagram verbunden.');
    }
    return IgAccess(
      loginType: row['login_type'] as String,
      token: await security.decrypt(row['encrypted_access_token'] as String),
      igUserId: row['ig_user_id'] as String,
    );
  }

  /// Prüft, dass ein Account zum Workspace gehört, und liefert ihn.
  Future<Map<String, dynamic>> accountInWorkspace(String accountId, String workspaceId) async {
    final row = await db.one(
      'SELECT * FROM instagram_accounts WHERE id = @id AND workspace_id = @w',
      {'id': accountId, 'w': workspaceId},
    );
    if (row == null) throw ApiError.notFound('Account');
    return row;
  }

  /// Verlangt Facebook Login (Hashtags, Wettbewerber; Spezifikation 4.9).
  Future<IgAccess> facebookAccess(String accountId) async {
    final a = await access(accountId);
    if (!a.isFacebook) {
      throw ApiError(
        409,
        'facebook_login_required',
        'Diese Funktion gibt es nur für Accounts, die über Facebook Login bzw. Meta Unified Login verbunden sind.',
      );
    }
    return a;
  }

  Future<void> notify({
    required String workspaceId,
    String? accountId,
    required String kind,
    required String title,
    String body = '',
    String? target,
  }) => db.exec(
    '''INSERT INTO notifications (workspace_id, account_id, kind, title, body, target)
       VALUES (@w, @a, @k, @t, @b, @target)''',
    {'w': workspaceId, 'a': accountId, 'k': kind, 't': title, 'b': body, 'target': target},
  );

  Future<void> audit(String? workspaceId, String? userId, String action, [String? target]) => db.exec(
    'INSERT INTO audit_log (workspace_id, user_id, action, target) VALUES (@w, @u, @a, @t)',
    {'w': workspaceId, 'u': userId, 'a': action, 't': target},
  );

  /// Übersetzt Instagram-Fehler in verständliche API-Fehler.
  ApiError instagramError(InstagramApiException e) {
    if (e.isAuthError) {
      return ApiError(409, 'reconnect_required', 'Die Verbindung zu Instagram ist abgelaufen. Bitte neu verbinden.');
    }
    if (e.isPermissionError) {
      return ApiError(403, 'missing_permission', 'Instagram verweigert den Zugriff (fehlende Berechtigung oder Freigabe): ${e.message}');
    }
    if (e.isLimitError) {
      return ApiError(429, 'instagram_limit', 'Instagram-Limit erreicht. Bitte später erneut versuchen.');
    }
    return ApiError(502, 'instagram_error', 'Instagram meldet: ${e.message}');
  }
}
