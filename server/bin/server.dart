import 'dart:io';

import 'package:content_hub_server/server.dart';
import 'package:shelf/shelf_io.dart' as io;

/// Startet den Content-Hub-Server.
/// Einstellungen kommen aus Umgebungsvariablen, siehe `.env.example`.
Future<void> main() async {
  final config = Config.fromEnvironment();
  final db = Db.connect(config.databaseUrl);
  await db.migrate();

  final services = Services(
    config: config,
    db: db,
    security: Security(config.tokenEncryptionKey),
    instagram: GraphInstagramApi(config),
    ai: ClaudeAiService(config),
    rss: RssService(),
    storage: MediaStorage(
      dir: config.storageDir,
      baseUrl: config.publicBaseUrl,
      // Signaturschlüssel für Medien-Links wird aus dem Hauptschlüssel abgeleitet.
      secret: config.tokenEncryptionKey.isEmpty ? Security.randomToken() : config.tokenEncryptionKey,
    ),
  );
  final sync = SyncService(services);
  final publisher = PublishService(services);

  final server = await io.serve(buildHandler(services, sync, publisher), InternetAddress.anyIPv4, config.port);
  stdout.writeln('Content-Hub-Server läuft auf Port ${server.port}');
  stdout.writeln('  Instagram Login: ${config.instagramLoginConfigured ? 'eingerichtet' : 'nicht eingerichtet'}');
  stdout.writeln('  Facebook Login:  ${config.facebookLoginConfigured ? 'eingerichtet' : 'nicht eingerichtet'}');
  stdout.writeln('  KI-Vorschläge:   ${config.aiConfigured ? 'eingerichtet' : 'nicht eingerichtet'}');

  if (config.enableScheduler) Scheduler(services, sync, publisher).start();
}
