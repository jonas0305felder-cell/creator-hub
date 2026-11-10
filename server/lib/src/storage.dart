import 'dart:io';

import 'security.dart';

/// Ablage für hochgeladene Medien (Ideen-Anhänge, Medien zum Veröffentlichen).
///
/// Dateien liegen im Ordner [dir]. Abrufbar sind sie nur über signierte,
/// zeitlich begrenzte URLs. Instagram verlangt beim Veröffentlichen eine
/// öffentlich erreichbare URL (Spezifikation 4.6).
class MediaStorage {
  MediaStorage({required this.dir, required this.baseUrl, required String secret})
    : _secret = 'media:$secret';

  final String dir;
  final String baseUrl;
  final String _secret;

  static const allowedTypes = {
    'image/jpeg': 'jpg',
    'image/png': 'png',
    'image/webp': 'webp',
    'image/heic': 'heic',
    'video/mp4': 'mp4',
    'video/quicktime': 'mov',
    'audio/mp4': 'm4a',
    'audio/aac': 'aac',
    'audio/mpeg': 'mp3',
    'audio/webm': 'webm',
    'audio/ogg': 'ogg',
    'audio/wav': 'wav',
  };

  /// Höchstgröße je Datei (Reels können groß sein).
  static const maxBytes = 300 * 1024 * 1024;

  Future<String> save(List<int> bytes, String mimeType) async {
    final ext = allowedTypes[mimeType];
    if (ext == null) throw ArgumentError('Dateityp $mimeType wird nicht unterstützt.');
    if (bytes.length > maxBytes) throw ArgumentError('Datei ist zu groß.');
    final key = '${Security.randomToken(18)}.$ext';
    final file = File('$dir/$key');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return key;
  }

  File? file(String key) {
    if (!RegExp(r'^[A-Za-z0-9_\-]+\.[a-z0-9]+$').hasMatch(key)) return null;
    final f = File('$dir/$key');
    return f.existsSync() ? f : null;
  }

  Future<void> delete(String key) async {
    final f = file(key);
    if (f != null) await f.delete();
  }

  /// Signierte URL, gültig bis [expires].
  Future<String> signedUrl(String key, DateTime expires) async {
    final exp = expires.toUtc().millisecondsSinceEpoch ~/ 1000;
    final sig = await Security.hmacHex(_secret, '$key:$exp');
    return '$baseUrl/media/$key?exp=$exp&sig=$sig';
  }

  Future<bool> verify(String key, String? exp, String? sig) async {
    final expSeconds = int.tryParse(exp ?? '');
    if (expSeconds == null || sig == null) return false;
    if (DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 > expSeconds) return false;
    final expected = await Security.hmacHex(_secret, '$key:$expSeconds');
    return expected == sig;
  }

  static String mimeFor(String key) {
    final ext = key.split('.').last;
    for (final e in allowedTypes.entries) {
      if (e.value == ext) return e.key;
    }
    return 'application/octet-stream';
  }
}
