# Content-Hub

Content-App für mehrere Instagram-Accounts: Statistiken, Trends nach Nische,
Ideen mit KI-Umsetzungsvorschlag, Redaktionskalender, Veröffentlichen,
Story-Sicherung, Hashtag-Beobachtung, Wettbewerber und Kommentare.
Grundlage ist die vereinbarte Spezifikation.

Die App ist mit Flutter gebaut. Derzeit läuft sie als **Web-App** im Browser.
Derselbe Code wird später die **iPhone-App**.

## 1. Was im Projekt steckt

| Ordner | Inhalt |
|---|---|
| `app/` | Flutter-App (Web, später iOS) |
| `server/` | Backend in Dart: Datenbank, Instagram-Anbindung, KI, Hintergrundjobs |
| `.github/workflows/` | Tests bei jedem Push, unsignierte iOS-App-Datei auf Knopfdruck |
| `Dockerfile`, `docker-compose.yml` | Server und Web-App zusammen auf einem eigenen Server starten |

### App (`app/lib/`)

| Datei | Aufgabe |
|---|---|
| `main.dart` | Start, Anmelde-Weiche |
| `config/app_texts.dart` | **alle sichtbaren Texte** |
| `config/app_theme.dart` | **Farben, Abstände, Rundungen** |
| `config/app_config.dart` | Server-Adresse, Funktionsschalter, Grenzen |
| `models/models.dart` | Datenklassen, Ideen-Filter, Trend-Frische |
| `services/api_client.dart` | Verbindung zum Server |
| `services/session_store.dart` | Sitzung sicher speichern |
| `services/voice_recorder.dart` | Sprachnotizen aufnehmen |
| `state/app_state.dart` | gemeinsamer Zustand, aktiver Account |
| `widgets/` | Bausteine: Lade-/Leer-/Fehlerzustand, Kacheln, Diagramm, Account-Wechsel |
| `screens/today_screen.dart` | Tab „Heute“, Benachrichtigungen |
| `screens/stats_screen.dart` | Tab „Statistiken“ |
| `screens/stats_detail_screens.dart` | Beitragsdetail, Story-Statistik, Wettbewerber |
| `screens/trends_screen.dart` | Tab „Trends“, Trenddetail, Quellen, Hashtags |
| `screens/plan_screen.dart` | Tab „Planen“: Ideen als Liste und Kanban |
| `screens/calendar_view.dart` | Redaktionskalender (Monat, Woche, Liste, Ziehen) |
| `screens/idea_detail_screen.dart` | Ideendetail, Anhänge, Umsetzungsvorschlag |
| `screens/publish_sheet.dart` | Veröffentlichen und Einplanen |
| `screens/quick_idea_sheet.dart` | Schnell-Idee (Plus-Knopf) |
| `screens/more_screen.dart` | Tab „Mehr“: Nischen, Team, Datenschutz |
| `screens/accounts_screen.dart` | Accounts verbinden, einrichten, trennen |
| `screens/comments_screen.dart` | Kommentar-Eingang |
| `screens/auth_screen.dart`, `home_shell.dart` | Anmeldung, Tab-Leiste bzw. Seitenleiste |

### Server (`server/`)

| Datei | Aufgabe |
|---|---|
| `bin/server.dart` | Start: Datenbank vorbereiten, Server und Hintergrundjobs starten |
| `lib/server.dart` | Routen, Anmeldung, CORS, Auslieferung der Web-App |
| `lib/src/config.dart` | Einstellungen aus `.env`, feste Grenzen |
| `lib/src/db.dart` | Datenbank und Tabellen (werden beim Start angelegt) |
| `lib/src/security.dart` | Passwörter, Sitzungen, Token-Verschlüsselung, signierte Links |
| `lib/src/instagram/instagram_api.dart` | Instagram Graph API |
| `lib/src/services/` | Synchronisation, Veröffentlichen, KI-Vorschläge, RSS |
| `lib/src/scheduler.dart` | Hintergrundjobs (minütlich) |
| `lib/src/routes/` | Endpunkte für Konto/Team, Accounts, Statistiken, Inhalte |
| `test/` | Tests mit nachgebautem Instagram und nachgebauter KI |

### Abhängigkeiten

App: `http`, `shared_preferences`, `flutter_secure_storage`, `flutter_web_auth_2` (Instagram-Login im Fenster),
`url_launcher`, `share_plus` (Teilen, Export), `image_picker` (Fotos, Medien), `record` (Sprachnotiz),
`audioplayers` (Sprachnotiz abspielen), `intl` und `flutter_localizations` (deutsche Datums- und Zahlenformate).

Server: `shelf`, `shelf_router`, `shelf_static`, `postgres`, `http`, `cryptography`, `xml` (RSS).

## 2. Annahmen

Diese Punkte ließ die Spezifikation offen. Ich habe sie so gelöst:

- Anmeldung mit E-Mail und Passwort. Mit Apple oder Google anmelden bräuchte zusätzliche Entwicklerkonten.
- Team-Einladung per Code, den der Owner weitergibt (für E-Mail-Versand fehlt ein Mail-Dienst).
- Hinweise erscheinen als Benachrichtigungen in der App. Push-Mitteilungen braucht später die iPhone-App mit Apple-Entwicklerkonto.
- Teilen aus anderen Apps in Content-Hub geht im Browser nicht. Links fügt man bis zur iPhone-App im Ideendetail ein.
- Google Trends ist nicht angebunden, weil es keinen gesicherten offiziellen Zugang gibt. Beobachtungen von dort erfasst man als eigene Beobachtung mit Link.
- KI-Anbieter ist Claude (Anthropic). Ohne Schlüssel zeigt die App einen Hinweis statt Vorschlägen.
- Top-Beiträge beobachteter Hashtags erscheinen automatisch in den Trends, aktuelle Beiträge erst nach „Als Trend übernehmen“.
- „Nur planen“ legt einen Kalendereintrag an, der nichts automatisch veröffentlicht.
- Jede Person gehört zu genau einem Workspace. Wer aus dem Team entfernt wird, dessen Konto wird gelöscht.
- Bei Facebook Login nimmt der Server den ersten verknüpften Instagram-Account, der noch nicht verbunden ist.
- Die Server-Einstellung `APP_CALLBACK_URL` gilt für Web **oder** iOS. Laufen später beide, braucht es zwei Server-Instanzen oder eine kleine Erweiterung.

## 3. Voraussetzungen

- Flutter 3.47 (enthält Dart 3.13): https://docs.flutter.dev/get-started/install/windows/web
- PostgreSQL 16: https://www.postgresql.org/download/windows/
- Google Chrome
- Für echte Instagram-Daten: eine Meta-App (siehe Abschnitt 6)
- Für KI-Vorschläge: ein API-Schlüssel von https://console.anthropic.com

## 4. Lokal starten (Windows, PowerShell)

```powershell
# 1. Datenbank anlegen (Passwort aus der PostgreSQL-Installation)
psql -U postgres -c "CREATE USER contenthub WITH PASSWORD 'geheim';"
psql -U postgres -c "CREATE DATABASE contenthub OWNER contenthub;"

# 2. Server einrichten
cd server
copy .env.example .env
#    In .env eintragen:
#    PUBLIC_BASE_URL=http://localhost:8080
#    DATABASE_URL=postgresql://contenthub:geheim@localhost:5432/contenthub?sslmode=disable
#    TOKEN_ENCRYPTION_KEY=<Ausgabe des nächsten Befehls>
dart run bin/generate_key.dart
dart pub get

# 3. Web-App bauen
cd ..\app
flutter pub get
flutter build web --release --no-web-resources-cdn

# 4. Server starten (liefert auch die Web-App aus)
cd ..\server
dart run bin/server.dart
```

Dann im Browser http://localhost:8080 öffnen und unter „Konto erstellen“ ein Konto anlegen.
Die Tabellen legt der Server beim ersten Start selbst an.

Zum Entwickeln mit Hot Reload (Server läuft dabei weiter):

```powershell
cd app
flutter run -d chrome --dart-define=BACKEND_URL=http://localhost:8080
```

## 5. Tests

```powershell
# App
cd app
flutter analyze
flutter test

# Server (eigene Test-Datenbank, wird bei jedem Lauf geleert)
psql -U postgres -c "CREATE DATABASE contenthub_test OWNER contenthub;"
cd server
$env:TEST_DATABASE_URL="postgresql://contenthub:geheim@localhost:5432/contenthub_test?sslmode=disable"
dart analyze
dart test --concurrency=1
```

## 6. Instagram anbinden (Meta-App)

Seit Oktober 2026 erlaubt Meta für neue Apps nur noch den **Unified Login**. Der Server unterstützt ihn
(Variable `FACEBOOK_CONFIG_ID`). Ältere Apps können weiter den Instagram-Login nutzen
(`INSTAGRAM_APP_ID`/`INSTAGRAM_APP_SECRET`).

Unified Login (neue Apps):

1. Ein Business-Portfolio anlegen (business.facebook.com) und die Meta-App diesem Portfolio zuordnen.
2. In der App: Anwendungsfälle → „Nachrichten und Inhalte auf Instagram verwalten“ → Anpassen →
   „API-Einrichtung mit Unified Login“ → neue Konfiguration erstellen (Token-Typ System-User,
   Ablauf „Nie“), Berechtigungen `instagram_basic`, `instagram_manage_insights`,
   `instagram_content_publish`, `instagram_manage_comments` wählen.
3. Als Weiterleitungs-URL der Konfiguration eintragen: `<PUBLIC_BASE_URL>/api/oauth/callback`.
4. In `server/.env` bzw. bei Render eintragen: `FACEBOOK_APP_ID` (App-ID), `FACEBOOK_APP_SECRET`
   (App-Geheimcode, unter App-Einstellungen → Allgemein) und `FACEBOOK_CONFIG_ID` (ID der Konfiguration).
5. Als Data-Deletion-Callback eintragen: `<PUBLIC_BASE_URL>/api/meta/data-deletion`.
6. In der App unter Mehr → Accounts → „Account verbinden“ → „Meta Login“ wählen.

Solange die App im Entwicklungsmodus ist, funktionieren nur Konten mit einer Rolle in der Meta-App
(Admin, Entwickler, Tester). Für alle anderen braucht es App Review und Business-Verifizierung.
Noch nicht mit einer echten Meta-App geprüft: der Unified-Login-Ablauf selbst sowie Statistik-,
Hashtag- und Veröffentlichungs-Endpunkte mit System-User-Tokens.

Instagram verlangt für den Login eine **HTTPS-Adresse**. Lokal geht das zum Beispiel mit einem Tunnel
(etwa Cloudflare Tunnel oder ngrok), dessen Adresse dann `PUBLIC_BASE_URL` ist.

## 7. Online stellen

Auf einem Linux-Server mit Docker:

```bash
cd app && flutter build web --release --no-web-resources-cdn && cd ..
cp server/.env.example server/.env   # Werte eintragen
DB_PASSWORD=ein-langes-passwort docker compose up -d --build
```

Davor gehört ein Webserver mit HTTPS (zum Beispiel Caddy), der auf Port 8080 weiterleitet.

## 8. iPhone-App (später)

Ohne Mac baut GitHub die App: Projekt in ein GitHub-Repository legen, dann unter
Actions → „iOS-App bauen (unsigniert)“ → „Run workflow“ die Server-Adresse eingeben.
Heraus kommt `content-hub-unsigned.ipa`. Ohne Apple-Entwicklerkonto lässt sie sich mit Sideloadly
und einer normalen Apple-ID installieren und läuft dann 7 Tage. In `server/.env` dafür
`APP_CALLBACK_URL=contenthub://oauth` setzen.

## 9. Anpassen

| Was | Wo |
|---|---|
| Texte | `app/lib/config/app_texts.dart` (Klasse `T`) |
| Farben, Account-Farbpalette | `app/lib/config/app_theme.dart` (`AppColors`) |
| Abstände, Rundungen | `app/lib/config/app_theme.dart` (`AppSpacing`) |
| Funktionen ein/aus (z. B. bis zur Meta-Freigabe) | `app/lib/config/app_config.dart` (`featurePublishing`, `featureComments`, `featureHashtags`, `featureCompetitors`) |
| Zeiträume, Trend-Frische, Breakpoint | `app/lib/config/app_config.dart` |
| Grenzen auf dem Server (Accounts, Wettbewerber, Hashtags) | `server/lib/src/config.dart` (`AppLimits`) |
| App-Name im Browser-Tab | `app/web/index.html`, `app/web/manifest.json` |
| App-Name auf dem iPhone | `app/ios/Runner/Info.plist` (`CFBundleDisplayName`) |
| KI-Anweisung | `server/lib/src/services/ai_service.dart` |

## 10. Was geprüft wurde und was nicht

Geprüft (am 10.11.2026):

- `flutter analyze` und `dart analyze`: keine Befunde.
- 18 App-Tests und 42 Server-Tests laufen durch. Die Server-Tests nutzen eine echte PostgreSQL-Datenbank,
  aber nachgebaute Instagram- und KI-Antworten.
- Web-App gebaut und mit Server im Browser (Chromium) durchgeklickt, als Handy (390 px) und als Desktop:
  Konto erstellen, Anmelden, Heute, Statistiken mit Testdaten, Account-Wechsel, Trends, Ideen,
  Schnell-Idee speichern, Ideendetail, Kalender Monat/Woche, Termin per Ziehen verschieben, Mehr, Accounts.

Nicht geprüft:

- Echte Instagram-Anbindung (Login, Statistiken, Veröffentlichen, Kommentare, Hashtags, Wettbewerber):
  dafür fehlt eine Meta-App. Der Code folgt der Graph-API-Dokumentation, kann aber beim ersten echten
  Lauf noch Anpassungen brauchen.
- Echte KI-Vorschläge: dafür fehlt ein API-Schlüssel.
- Sprachnotiz-Aufnahme, Foto-Auswahl und Datenexport im echten Browser mit Mikrofon und Dateidialog.
- Docker-Start und iOS-Build: hier gab es weder Docker noch einen Mac. Die iOS-App ist vorbereitet,
  aber noch nie gebaut worden.
