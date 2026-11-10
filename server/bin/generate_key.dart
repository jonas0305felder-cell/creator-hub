import 'dart:convert';
import 'dart:math';

/// Gibt einen neuen Schlüssel für TOKEN_ENCRYPTION_KEY aus (32 Byte, Base64).
void main() {
  final random = Random.secure();
  print(base64Encode(List<int>.generate(32, (_) => random.nextInt(256))));
}
