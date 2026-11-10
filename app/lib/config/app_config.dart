import 'package:flutter/foundation.dart';

/// Zentrale technische Einstellungen der App.
///
/// Texte stehen in `app_texts.dart`, Farben und Abstände in `app_theme.dart`.
class AppConfig {
  AppConfig._();

  /// Adresse des Servers, z. B. `https://content-hub.example.com`.
  ///
  /// Beim Bauen setzen mit `--dart-define=BACKEND_URL=https://…`.
  /// Bleibt der Wert leer, nimmt die Web-App die Adresse, von der sie
  /// geladen wurde (der Server liefert die Web-App selbst aus).
  static const String _backendUrl = String.fromEnvironment('BACKEND_URL');

  static String get backendUrl {
    if (_backendUrl.isNotEmpty) return _backendUrl;
    if (kIsWeb) return Uri.base.origin;
    return '';
  }

  /// URL-Schema, mit dem der Server die iOS-App nach dem Instagram-Login
  /// wieder öffnet (muss zu `ios/Runner/Info.plist` und zur Server-Einstellung
  /// `APP_CALLBACK_URL=contenthub://oauth` passen).
  static const String callbackScheme = 'contenthub';

  /// Zeitlimit für normale Anfragen an den Server.
  static const Duration requestTimeout = Duration(seconds: 30);

  /// Zeitlimit für langsame Anfragen (KI-Vorschlag, Uploads, Sync).
  static const Duration slowRequestTimeout = Duration(minutes: 4);

  // ---------------------------------------------------------------------
  // Schalter für Funktionen, die eine Meta-Freigabe (App Review) brauchen.
  // Laut Spezifikation werden sie einzeln aktiviert, sobald die Freigabe
  // vorliegt. `false` zeigt statt der Funktion einen Hinweis.
  // ---------------------------------------------------------------------
  static const bool featurePublishing = true;
  static const bool featureComments = true;
  static const bool featureHashtags = true;
  static const bool featureCompetitors = true;

  // ---------------------------------------------------------------------
  // Grenzen aus der Spezifikation (der Server setzt sie zusätzlich durch).
  // ---------------------------------------------------------------------
  static const int maxAccounts = 10;
  static const int maxCarouselItems = 10;
  static const int maxSuggestedHashtags = 5;

  /// Frische-Grenzen für Trends in Tagen: aktuell < 7, älter 7–30, veraltet > 30.
  static const int trendFreshDays = 7;
  static const int trendOldDays = 30;

  /// Anzahl Trends auf der Heute-Seite.
  static const int todayTrendCount = 3;

  /// Zeiträume der Statistik-Seite in Tagen.
  static const List<int> statsPeriods = [7, 28, 90];

  /// Daten gelten ab diesem Alter als veraltet (Hinweis auf der Heute-Seite).
  static const Duration staleAfter = Duration(hours: 36);

  /// Ab dieser Breite zeigt die App eine Seitenleiste statt der Tab-Leiste.
  static const double wideLayoutBreakpoint = 900;

  /// Höchstbreite des Inhalts auf großen Bildschirmen.
  static const double maxContentWidth = 980;
}
