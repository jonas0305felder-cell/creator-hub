import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../config/app_texts.dart';

/// Fehler einer Server-Anfrage mit deutschem Hinweis für die Oberfläche.
class ApiException implements Exception {
  ApiException(this.code, this.message, {this.status});

  /// Maschinenlesbarer Code, z. B. `facebook_login_required`.
  final String code;
  final String message;
  final int? status;

  bool get isUnauthorized => status == 401 && code == 'unauthorized';
  bool get isNotConfigured => code == 'not_configured';

  @override
  String toString() => message;
}

/// Spricht mit dem Content-Hub-Server (JSON über HTTPS).
class ApiClient {
  ApiClient({http.Client? client, String? baseUrl}) : _http = client ?? http.Client(), baseUrl = baseUrl ?? AppConfig.backendUrl;

  final http.Client _http;
  final String baseUrl;

  /// Sitzungs-Token der angemeldeten Person.
  String? token;

  /// Wird aufgerufen, wenn der Server die Sitzung nicht mehr kennt.
  void Function()? onSessionExpired;

  Map<String, String> _headers([String? contentType]) => {
    if (token != null) 'authorization': 'Bearer $token',
    'content-type': ?contentType,
  };

  Uri _uri(String path, [Map<String, String?>? query]) {
    if (baseUrl.isEmpty) throw ApiException('no_backend', T.errorNoBackend);
    final cleaned = {
      for (final e in (query ?? const <String, String?>{}).entries)
        if (e.value != null) e.key: e.value!,
    };
    return Uri.parse('$baseUrl$path').replace(queryParameters: cleaned.isEmpty ? null : cleaned);
  }

  Future<dynamic> get(String path, {Map<String, String?>? query, bool slow = false}) =>
      _send(() => _http.get(_uri(path, query), headers: _headers()), slow);

  Future<dynamic> post(String path, [Object? body, bool slow = false]) =>
      _send(() => _http.post(_uri(path), headers: _headers('application/json'), body: jsonEncode(body ?? const {})), slow);

  Future<dynamic> patch(String path, Object body) =>
      _send(() => _http.patch(_uri(path), headers: _headers('application/json'), body: jsonEncode(body)), false);

  Future<dynamic> delete(String path, {Map<String, String?>? query}) =>
      _send(() => _http.delete(_uri(path, query), headers: _headers()), false);

  /// Lädt eine Datei als Rohdaten hoch.
  Future<dynamic> upload(String path, Uint8List bytes, String mimeType) =>
      _send(() => _http.post(_uri(path), headers: _headers(mimeType), body: bytes), true);

  /// Liefert die rohe Antwort (für den Datenexport).
  Future<Uint8List> download(String path) async {
    final response = await _raw(() => _http.get(_uri(path), headers: _headers()), true);
    return response.bodyBytes;
  }

  Future<dynamic> _send(Future<http.Response> Function() request, bool slow) async {
    final response = await _raw(request, slow);
    if (response.bodyBytes.isEmpty) return null;
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  Future<http.Response> _raw(Future<http.Response> Function() request, bool slow) async {
    final http.Response response;
    try {
      response = await request().timeout(slow ? AppConfig.slowRequestTimeout : AppConfig.requestTimeout);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException('timeout', T.errorTimeout);
    } catch (_) {
      throw ApiException('network', T.errorNetwork);
    }
    if (response.statusCode < 400) return response;
    String code = 'server_error';
    String message = T.errorUnknown;
    try {
      final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      code = (json['error'] ?? code).toString();
      message = (json['message'] ?? message).toString();
    } catch (_) {
      // Antwort ohne JSON: allgemeiner Hinweis.
    }
    final error = ApiException(code, message, status: response.statusCode);
    if (error.isUnauthorized) onSessionExpired?.call();
    throw error;
  }
}
