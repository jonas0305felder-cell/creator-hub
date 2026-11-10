import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Merkt sich Sitzung und Bedien-Einstellungen auf dem Gerät.
abstract class SessionStore {
  Future<String?> readToken();
  Future<void> writeToken(String? token);
  Future<String?> readActiveAccount();
  Future<void> writeActiveAccount(String? accountId);
}

/// Sitzungs-Token im iOS-Schlüsselbund bzw. im geschützten Browser-Speicher,
/// der zuletzt gewählte Account in den normalen Einstellungen.
class DeviceSessionStore implements SessionStore {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'session_token';
  static const _accountKey = 'active_account';

  @override
  Future<String?> readToken() async {
    try {
      return await _storage.read(key: _tokenKey);
    } catch (_) {
      return null; // z. B. gelöschter Browser-Speicher: neu anmelden
    }
  }

  @override
  Future<void> writeToken(String? token) async {
    if (token == null) {
      await _storage.delete(key: _tokenKey);
    } else {
      await _storage.write(key: _tokenKey, value: token);
    }
  }

  @override
  Future<String?> readActiveAccount() async => (await SharedPreferences.getInstance()).getString(_accountKey);

  @override
  Future<void> writeActiveAccount(String? accountId) async {
    final prefs = await SharedPreferences.getInstance();
    if (accountId == null) {
      await prefs.remove(_accountKey);
    } else {
      await prefs.setString(_accountKey, accountId);
    }
  }
}

/// Speicher nur im Arbeitsspeicher (für Tests).
class MemorySessionStore implements SessionStore {
  String? token;
  String? account;

  @override
  Future<String?> readToken() async => token;
  @override
  Future<void> writeToken(String? value) async => token = value;
  @override
  Future<String?> readActiveAccount() async => account;
  @override
  Future<void> writeActiveAccount(String? value) async => account = value;
}
