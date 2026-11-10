import '../config.dart';
import '../http_utils.dart';
import '../instagram/instagram_api.dart';
import 'services.dart';

/// Veröffentlicht Posts, Reels und Karussells (Spezifikation 4.6).
class PublishService {
  PublishService(this.s);

  final Services s;

  /// Wie oft der Container-Status abgefragt wird, bevor aufgegeben wird.
  int statusAttempts = 60;
  Duration statusInterval = const Duration(seconds: 5);

  /// Vorab-Prüfung der Formatregeln. Liefert eine Liste von Problemen.
  static List<String> validate(String format, List<String> mimeTypes) {
    final problems = <String>[];
    bool isImage(String m) => m.startsWith('image/');
    bool isVideo(String m) => m.startsWith('video/');
    switch (format) {
      case 'post':
        if (mimeTypes.length != 1) {
          problems.add('Ein Post braucht genau ein Bild.');
        } else if (mimeTypes.first != 'image/jpeg') {
          problems.add('Einzelbilder müssen im Format JPEG vorliegen.');
        }
      case 'reel':
        if (mimeTypes.length != 1 || !isVideo(mimeTypes.first)) {
          problems.add('Ein Reel braucht genau ein Video (MP4 oder MOV).');
        }
      case 'carousel':
        if (mimeTypes.length < 2) problems.add('Ein Karussell braucht mindestens 2 Medien.');
        if (mimeTypes.length > AppLimits.maxCarouselItems) {
          problems.add('Ein Karussell darf höchstens ${AppLimits.maxCarouselItems} Medien enthalten.');
        }
        for (final m in mimeTypes) {
          if (isImage(m) && m != 'image/jpeg') {
            problems.add('Bilder im Karussell müssen im Format JPEG vorliegen.');
            break;
          }
          if (!isImage(m) && !isVideo(m)) {
            problems.add('Im Karussell sind nur Bilder und Videos erlaubt.');
            break;
          }
        }
      default:
        problems.add('Unbekanntes Format.');
    }
    return problems;
  }

  /// Verbleibendes Tageslimit eines Accounts.
  ///
  /// Der aktuelle Wert kommt von Instagram (`content_publishing_limit`),
  /// weil die Dokumentation 50 und 100 nennt (Spezifikation 7.5). Ist er
  /// nicht abrufbar, ist `limit` null und nur die eigene Zählung bekannt.
  Future<Map<String, dynamic>> limit(String accountId) async {
    final own = await s.db.one(
      '''SELECT count(*)::int AS n FROM scheduled_posts
         WHERE account_id = @a AND status = 'published' AND scheduled_for > @t''',
      {'a': accountId, 't': s.now().subtract(const Duration(hours: 24))},
    );
    final ownCount = own?['n'] as int? ?? 0;
    try {
      final access = await s.access(accountId);
      final result = await s.instagram.publishingLimit(access);
      if (result != null) {
        return {'used': result.used, 'limit': result.limit, 'remaining': result.limit - result.used, 'source': 'instagram'};
      }
    } catch (_) {
      // Limit nicht abrufbar: nur eigene Zählung zurückgeben.
    }
    return {'used': ownCount, 'limit': null, 'remaining': null, 'source': 'own_count'};
  }

  /// Veröffentlicht einen geplanten Beitrag jetzt. Setzt den Status selbst.
  Future<void> publish(String postId) async {
    // Nur einmal starten, auch wenn Job und Nutzer gleichzeitig auslösen.
    final post = await s.db.one(
      '''UPDATE scheduled_posts SET status = 'publishing', error_message = NULL
         WHERE id = @id AND status IN ('scheduled','failed','draft') RETURNING *''',
      {'id': postId},
    );
    if (post == null) return;
    final accountId = post['account_id'] as String;
    final account = await s.db.one('SELECT workspace_id, username FROM instagram_accounts WHERE id = @a', {'a': accountId});
    try {
      final access = await s.access(accountId);
      final media = await s.db.query(
        'SELECT * FROM scheduled_post_media WHERE scheduled_post_id = @p ORDER BY position',
        {'p': postId},
      );
      final format = post['format'] as String;
      final problems = validate(format, [for (final m in media) m['mime_type'] as String]);
      if (problems.isNotEmpty) throw ApiError.badRequest(problems.join(' '));

      final limit = await s.instagram.publishingLimit(access);
      if (limit != null && limit.used >= limit.limit) {
        throw ApiError(429, 'publish_limit', 'Das Tageslimit dieses Accounts für Veröffentlichungen ist erreicht.');
      }

      // Medien für kurze Zeit öffentlich per URL bereitstellen.
      final expires = s.now().add(const Duration(hours: 2));
      final urls = <String>[];
      for (final m in media) {
        urls.add(await s.storage.signedUrl(m['storage_key'] as String, expires));
        await s.db.exec('UPDATE scheduled_post_media SET public_url_expires_at = @e WHERE id = @id', {
          'id': m['id'],
          'e': expires,
        });
      }

      final caption = post['caption'] as String;
      String containerId;
      if (format == 'post') {
        containerId = await s.instagram.createContainer(access, {'image_url': urls.first, 'caption': caption});
      } else if (format == 'reel') {
        containerId = await s.instagram.createContainer(access, {
          'media_type': 'REELS',
          'video_url': urls.first,
          'caption': caption,
        });
        await _waitUntilReady(access, containerId);
      } else {
        final children = <String>[];
        for (var i = 0; i < media.length; i++) {
          final isVideo = (media[i]['mime_type'] as String).startsWith('video/');
          final child = await s.instagram.createContainer(access, {
            'is_carousel_item': 'true',
            if (isVideo) 'media_type': 'VIDEO',
            if (isVideo) 'video_url': urls[i] else 'image_url': urls[i],
          });
          if (isVideo) await _waitUntilReady(access, child);
          children.add(child);
        }
        containerId = await s.instagram.createContainer(access, {
          'media_type': 'CAROUSEL',
          'children': children.join(','),
          'caption': caption,
        });
      }
      await s.db.exec('UPDATE scheduled_posts SET ig_container_id = @c WHERE id = @id', {'id': postId, 'c': containerId});

      final igMediaId = await s.instagram.publishContainer(access, containerId);
      final published = await s.instagram.mediaById(access, igMediaId);
      final mediaRow = await s.db.one(
        '''INSERT INTO media (account_id, ig_media_id, media_type, media_product_type, caption, permalink, thumbnail_url, posted_at)
           VALUES (@a, @ig, @type, @product, @caption, @link, @thumb, @now)
           ON CONFLICT (account_id, ig_media_id) DO UPDATE SET permalink = EXCLUDED.permalink
           RETURNING id''',
        {
          'a': accountId,
          'ig': igMediaId,
          'type': (published['media_type'] ?? (format == 'reel' ? 'VIDEO' : format == 'carousel' ? 'CAROUSEL_ALBUM' : 'IMAGE')).toString(),
          'product': format == 'reel' ? 'reels' : 'feed',
          'caption': caption,
          'link': published['permalink'],
          'thumb': published['thumbnail_url'] ?? published['media_url'],
          'now': s.now(),
        },
      );
      await s.db.exec(
        '''UPDATE scheduled_posts SET status = 'published', published_media_id = @m, published_permalink = @link
           WHERE id = @id''',
        {'id': postId, 'm': mediaRow!['id'], 'link': published['permalink']},
      );
      // Idee automatisch verknüpfen, damit die Performance zurückfließt.
      if (post['idea_id'] != null) {
        await s.db.exec(
          "UPDATE ideas SET status = 'published', published_media_id = @m, updated_at = @now WHERE id = @i",
          {'i': post['idea_id'], 'm': mediaRow['id'], 'now': s.now()},
        );
      }
      // Medien liegen nur bis zur Veröffentlichung auf dem Server (7.6).
      for (final m in media) {
        await s.storage.delete(m['storage_key'] as String);
      }
    } catch (e) {
      final message = switch (e) {
        ApiError() => e.message,
        InstagramApiException() => s.instagramError(e).message,
        _ => 'Unerwarteter Fehler: $e',
      };
      await s.db.exec("UPDATE scheduled_posts SET status = 'failed', error_message = @e WHERE id = @id", {
        'id': postId,
        'e': message,
      });
      if (account != null) {
        await s.notify(
          workspaceId: account['workspace_id'] as String,
          accountId: accountId,
          kind: 'publish_failed',
          title: 'Veröffentlichung bei @${account['username']} fehlgeschlagen',
          body: message,
          target: 'calendar',
        );
      }
    }
  }

  Future<void> _waitUntilReady(IgAccess access, String containerId) async {
    for (var i = 0; i < statusAttempts; i++) {
      final status = await s.instagram.containerStatus(access, containerId);
      if (status == 'FINISHED') return;
      if (status == 'ERROR' || status == 'EXPIRED') {
        throw ApiError(502, 'container_failed', 'Instagram konnte das Medium nicht verarbeiten ($status).');
      }
      await Future<void>.delayed(statusInterval);
    }
    throw ApiError(504, 'container_timeout', 'Instagram hat das Medium nicht rechtzeitig verarbeitet.');
  }

  /// Veröffentlicht alle fälligen geplanten Beiträge (läuft im Minutentakt).
  Future<void> publishDue() async {
    final due = await s.db.query(
      "SELECT id FROM scheduled_posts WHERE status = 'scheduled' AND scheduled_for <= @now ORDER BY scheduled_for LIMIT 10",
      {'now': s.now()},
    );
    for (final row in due) {
      await publish(row['id'] as String);
    }
  }
}
