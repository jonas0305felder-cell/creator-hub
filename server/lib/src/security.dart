import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// Kryptografie-Helfer: Passwörter, Sitzungs-Tokens, Token-Verschlüsselung.
class Security {
  Security(String base64Key)
    : _key = base64Key.isEmpty ? null : SecretKey(base64Decode(base64Key)) {
    if (_key != null && base64Decode(base64Key).length != 32) {
      throw ArgumentError('TOKEN_ENCRYPTION_KEY muss 32 Byte (Base64) haben.');
    }
  }

  final SecretKey? _key;
  static final _random = Random.secure();
  static final _aes = AesGcm.with256bits();
  static final _pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 210000,
    bits: 256,
  );

  /// Zufällige, URL-sichere Zeichenkette (z. B. für Sitzungen, state, Codes).
  static String randomToken([int bytes = 32]) {
    final values = List<int>.generate(bytes, (_) => _random.nextInt(256));
    return base64Url.encode(values).replaceAll('=', '');
  }

  /// Kurzer, gut abtippbarer Code für Einladungen.
  static String inviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(8, (_) => chars[_random.nextInt(chars.length)]).join();
  }

  static Future<String> sha256Hex(String input) async {
    final hash = await Sha256().hash(utf8.encode(input));
    return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Passwort-Hash im Format `pbkdf2$<iterationen>$<salt>$<hash>`.
  static Future<String> hashPassword(String password) async {
    final salt = List<int>.generate(16, (_) => _random.nextInt(256));
    final key = await _pbkdf2.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    final bytes = await key.extractBytes();
    return 'pbkdf2\$210000\$${base64Encode(salt)}\$${base64Encode(bytes)}';
  }

  static Future<bool> verifyPassword(String password, String stored) async {
    final parts = stored.split(r'$');
    if (parts.length != 4 || parts[0] != 'pbkdf2') return false;
    final kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: int.parse(parts[1]),
      bits: 256,
    );
    final key = await kdf.deriveKeyFromPassword(
      password: password,
      nonce: base64Decode(parts[2]),
    );
    final bytes = await key.extractBytes();
    final expected = base64Decode(parts[3]);
    if (bytes.length != expected.length) return false;
    var diff = 0;
    for (var i = 0; i < bytes.length; i++) {
      diff |= bytes[i] ^ expected[i];
    }
    return diff == 0;
  }

  /// Verschlüsselt ein Instagram-Token mit AES-256-GCM.
  /// Ergebnis: Base64 aus Nonce + Chiffretext + MAC.
  Future<String> encrypt(String plain) async {
    final key = _requireKey();
    final box = await _aes.encrypt(utf8.encode(plain), secretKey: key);
    return base64Encode(box.concatenation());
  }

  Future<String> decrypt(String encoded) async {
    final key = _requireKey();
    final box = SecretBox.fromConcatenation(
      base64Decode(encoded),
      nonceLength: _aes.nonceLength,
      macLength: _aes.macAlgorithm.macLength,
    );
    return utf8.decode(await _aes.decrypt(box, secretKey: key));
  }

  /// HMAC-SHA256 als Hex (für signierte Medien-URLs).
  static Future<String> hmacHex(String secret, String message) async {
    final mac = await Hmac.sha256().calculateMac(
      utf8.encode(message),
      secretKey: SecretKey(utf8.encode(secret)),
    );
    return mac.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// HMAC-SHA256 als Bytes (für Metas signed_request).
  static Future<List<int>> hmacBytes(String secret, List<int> message) async {
    final mac = await Hmac.sha256().calculateMac(
      message,
      secretKey: SecretKey(utf8.encode(secret)),
    );
    return mac.bytes;
  }

  SecretKey _requireKey() {
    final key = _key;
    if (key == null) {
      throw StateError(
        'TOKEN_ENCRYPTION_KEY fehlt. Ohne Schlüssel speichert der Server keine Instagram-Tokens.',
      );
    }
    return key;
  }
}
