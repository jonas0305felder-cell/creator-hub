import 'dart:io';

/// Alle Einstellungen des Servers kommen aus Umgebungsvariablen.
/// Eine Vorlage mit Erklärungen steht in `server/.env.example`.
class Config {
  Config({
    required this.port,
    required this.databaseUrl,
    required this.publicBaseUrl,
    required this.appCallbackUrl,
    required this.tokenEncryptionKey,
    required this.storageDir,
    required this.webDir,
    required this.instagramAppId,
    required this.instagramAppSecret,
    required this.facebookAppId,
    required this.facebookAppSecret,
    required this.graphApiVersion,
    required this.aiApiKey,
    required this.aiModel,
    required this.enableScheduler,
  });

  /// Port, auf dem der Server lauscht.
  final int port;

  /// PostgreSQL-Verbindung, z. B.
  /// `postgresql://contenthub:geheim@localhost:5432/contenthub?sslmode=disable`.
  final String databaseUrl;

  /// Öffentliche HTTPS-Adresse dieses Servers (für OAuth-Redirect und
  /// öffentliche Medien-URLs beim Veröffentlichen).
  final String publicBaseUrl;

  /// Wohin der Server nach dem Instagram-Login zurückspringt. Für die
  /// Web-App eine Seite des Servers selbst, für iOS `contenthub://oauth`.
  final String appCallbackUrl;

  /// 32 Byte als Base64 für AES-256-GCM-Verschlüsselung der Instagram-Tokens.
  final String tokenEncryptionKey;

  /// Ordner für hochgeladene Medien und Anhänge.
  final String storageDir;

  /// Ordner mit der gebauten Web-App (`flutter build web`), leer = keine.
  final String webDir;

  final String instagramAppId;
  final String instagramAppSecret;
  final String facebookAppId;
  final String facebookAppSecret;

  /// Graph-API-Version laut Spezifikation (geprüft am 10.11.2026: v25.0).
  final String graphApiVersion;

  /// Schlüssel für den KI-Anbieter (Umsetzungsvorschläge).
  final String aiApiKey;
  final String aiModel;

  /// Hintergrundjobs (Sync, Veröffentlichen, Trends) an/aus.
  final bool enableScheduler;

  bool get instagramLoginConfigured =>
      instagramAppId.isNotEmpty && instagramAppSecret.isNotEmpty;
  bool get facebookLoginConfigured =>
      facebookAppId.isNotEmpty && facebookAppSecret.isNotEmpty;
  bool get aiConfigured => aiApiKey.isNotEmpty;

  /// Liest Umgebungsvariablen; eine Datei `.env` im Arbeitsordner ergänzt
  /// fehlende Werte (Zeilen `NAME=Wert`, `#` leitet Kommentare ein).
  static Config fromEnvironment([Map<String, String>? env]) {
    final e = env ?? {..._readDotEnv(), ...Platform.environment};
    String get(String key, [String fallback = '']) {
      final value = e[key];
      return (value == null || value.trim().isEmpty) ? fallback : value.trim();
    }

    final port = int.tryParse(get('PORT', '8080')) ?? 8080;
    final base = get('PUBLIC_BASE_URL', 'http://localhost:$port');
    return Config(
      port: port,
      databaseUrl: get(
        'DATABASE_URL',
        'postgresql://contenthub:contenthub@localhost:5432/contenthub?sslmode=disable',
      ),
      publicBaseUrl: base.endsWith('/') ? base.substring(0, base.length - 1) : base,
      appCallbackUrl: get('APP_CALLBACK_URL', '$base/oauth-fertig'),
      tokenEncryptionKey: get('TOKEN_ENCRYPTION_KEY'),
      storageDir: get('STORAGE_DIR', 'storage'),
      webDir: get('WEB_DIR', '../app/build/web'),
      instagramAppId: get('INSTAGRAM_APP_ID'),
      instagramAppSecret: get('INSTAGRAM_APP_SECRET'),
      facebookAppId: get('FACEBOOK_APP_ID'),
      facebookAppSecret: get('FACEBOOK_APP_SECRET'),
      graphApiVersion: get('GRAPH_API_VERSION', 'v25.0'),
      aiApiKey: get('AI_API_KEY'),
      aiModel: get('AI_MODEL', 'claude-opus-5-5'),
      enableScheduler: get('ENABLE_SCHEDULER', 'true') == 'true',
    );
  }
}

Map<String, String> _readDotEnv() {
  final file = File('.env');
  if (!file.existsSync()) return {};
  final values = <String, String>{};
  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#') || !trimmed.contains('=')) continue;
    final index = trimmed.indexOf('=');
    values[trimmed.substring(0, index).trim()] = trimmed.substring(index + 1).trim();
  }
  return values;
}

/// Feste Grenzen aus der Spezifikation (serverseitig durchgesetzt).
class AppLimits {
  AppLimits._();

  /// Höchstzahl verbundener Accounts je Workspace.
  static const maxAccounts = 10;

  /// Höchstzahl Wettbewerber je Account.
  static const maxCompetitorsPerAccount = 10;

  /// Hashtag-Kontingent von Instagram: 30 Hashtags je 7 Tage und Account.
  static const hashtagQuota = 30;
  static const hashtagWindowDays = 7;

  /// Höchstzahl Medien in einem Karussell.
  static const maxCarouselItems = 10;

  /// Tage vor Token-Ablauf, ab denen „läuft bald ab“ gilt.
  static const tokenWarningDays = 14;

  /// Gültigkeit einer App-Sitzung.
  static const sessionDays = 60;

  /// Gültigkeit einer Team-Einladung.
  static const inviteDays = 7;
}
