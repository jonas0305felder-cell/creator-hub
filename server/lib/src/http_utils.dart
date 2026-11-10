import 'dart:convert';

import 'package:shelf/shelf.dart';

/// Fehler, der als JSON mit passendem HTTP-Status an die App geht.
///
/// [code] ist maschinenlesbar (die App übersetzt ihn in einen deutschen
/// Hinweis), [message] ist eine deutsche Erklärung für Menschen.
class ApiError implements Exception {
  ApiError(this.status, this.code, this.message);

  final int status;
  final String code;
  final String message;

  static ApiError badRequest(String message) =>
      ApiError(400, 'bad_request', message);
  static ApiError unauthorized() =>
      ApiError(401, 'unauthorized', 'Bitte erneut anmelden.');
  static ApiError forbidden(String message) =>
      ApiError(403, 'forbidden', message);
  static ApiError notFound([String what = 'Eintrag']) =>
      ApiError(404, 'not_found', '$what nicht gefunden.');
  static ApiError notConfigured(String what) => ApiError(
    503,
    'not_configured',
    '$what ist auf dem Server noch nicht eingerichtet.',
  );

  @override
  String toString() => 'ApiError($status, $code, $message)';
}

/// Angemeldete Person für die aktuelle Anfrage.
class AuthContext {
  AuthContext({
    required this.userId,
    required this.workspaceId,
    required this.role,
  });

  final String userId;
  final String workspaceId;
  final String role;

  bool get isOwner => role == 'owner';

  void requireOwner() {
    if (!isOwner) {
      throw ApiError.forbidden('Nur die Owner-Rolle darf das.');
    }
  }
}

const _jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

Response jsonOk(Object? body, {int status = 200}) =>
    Response(status, body: jsonEncode(body, toEncodable: _encode), headers: _jsonHeaders);

Response jsonError(ApiError e) => Response(
  e.status,
  body: jsonEncode({'error': e.code, 'message': e.message}),
  headers: _jsonHeaders,
);

Object? _encode(Object? value) {
  if (value is DateTime) return value.toUtc().toIso8601String();
  return value.toString();
}

/// Liest den JSON-Body einer Anfrage als Map.
Future<Map<String, dynamic>> readJson(Request request) async {
  final text = await request.readAsString();
  if (text.trim().isEmpty) return {};
  try {
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) return decoded;
  } on FormatException {
    // fällt unten durch
  }
  throw ApiError.badRequest('Ungültige Anfrage (JSON erwartet).');
}

AuthContext authOf(Request request) {
  final ctx = request.context['auth'];
  if (ctx is AuthContext) return ctx;
  throw ApiError.unauthorized();
}

/// Kleine Helfer zum sicheren Auslesen von Feldern.
extension JsonFields on Map<String, dynamic> {
  String reqString(String key, {int maxLength = 5000}) {
    final value = this[key];
    if (value is! String || value.trim().isEmpty) {
      throw ApiError.badRequest('Feld „$key“ fehlt.');
    }
    if (value.length > maxLength) {
      throw ApiError.badRequest('Feld „$key“ ist zu lang.');
    }
    return value.trim();
  }

  String? optString(String key, {int maxLength = 20000}) {
    final value = this[key];
    if (value == null) return null;
    if (value is! String) throw ApiError.badRequest('Feld „$key“ ist ungültig.');
    if (value.length > maxLength) {
      throw ApiError.badRequest('Feld „$key“ ist zu lang.');
    }
    return value;
  }

  DateTime? optDate(String key) {
    final value = this[key];
    if (value == null || value == '') return null;
    final parsed = value is String ? DateTime.tryParse(value) : null;
    if (parsed == null) throw ApiError.badRequest('Datum „$key“ ist ungültig.');
    return parsed.toUtc();
  }

  List<String> stringList(String key) {
    final value = this[key];
    if (value == null) return const [];
    if (value is! List) throw ApiError.badRequest('Feld „$key“ muss eine Liste sein.');
    return [for (final v in value) v.toString()];
  }

  String? oneOf(String key, Set<String> allowed) {
    final value = this[key];
    if (value == null) return null;
    if (value is! String || !allowed.contains(value)) {
      throw ApiError.badRequest('Wert für „$key“ ist ungültig.');
    }
    return value;
  }
}

/// Wandelt eine DB-Zeile in JSON-taugliche Werte um.
Map<String, dynamic> rowJson(Map<String, dynamic> row) => {
  for (final e in row.entries)
    e.key: e.value is DateTime ? (e.value as DateTime).toUtc().toIso8601String() : e.value,
};
