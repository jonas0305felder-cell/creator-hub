import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/session_store.dart';

/// Zentraler Zustand: Sitzung, Accounts, Nischen, Ideen und der aktive
/// Account-Kontext, dem Statistiken, Trends und Ideen folgen.
class AppState extends ChangeNotifier {
  AppState({required this.api, required this.store}) {
    api.onSessionExpired = _sessionExpired;
  }

  final ApiClient api;
  final SessionStore store;

  /// true, bis beim Start geprüft wurde, ob eine Sitzung vorliegt.
  bool starting = true;
  bool get signedIn => api.token != null && me != null;

  Map<String, dynamic>? me;
  List<Account> accounts = [];
  List<Niche> niches = [];
  List<Idea> ideas = [];
  List<Map<String, dynamic>> members = [];
  int unreadNotifications = 0;

  /// Fehler beim Laden der Grunddaten (für den Fehlerzustand der Startseite).
  ApiException? loadError;

  /// Aktiver Account; `null` bedeutet „Alle Accounts“.
  String? activeAccountId;

  Account? get activeAccount => accountById(activeAccountId);
  bool get isOwner => me?['role'] == 'owner';
  String get userId => (me?['user']?['id'] ?? '') as String;
  Map<String, dynamic> get serverSetup => Map<String, dynamic>.from((me?['server'] as Map?) ?? const {});

  Account? accountById(String? id) => accounts.where((a) => a.id == id).firstOrNull;
  Niche? nicheById(String? id) => niches.where((n) => n.id == id).firstOrNull;
  Idea? ideaById(String? id) => ideas.where((i) => i.id == id).firstOrNull;

  /// Nischen des aktiven Kontexts: die des Accounts, sonst alle.
  List<String> get contextNicheIds => activeAccount?.nicheIds ?? {for (final a in accounts) ...a.nicheIds}.toList();

  // -------------------------------------------------------------------
  // Sitzung
  // -------------------------------------------------------------------

  Future<void> start() async {
    api.token = await store.readToken();
    activeAccountId = await store.readActiveAccount();
    if (api.token != null) {
      try {
        await _loadAll();
      } on ApiException catch (e) {
        // Unvollständig geladen: Fehlerzustand mit „Erneut versuchen“ zeigen.
        if (!e.isUnauthorized) {
          loadError = e;
          me = null;
        }
      }
    }
    starting = false;
    notifyListeners();
  }

  Future<void> signIn(String email, String password) async {
    final result = await api.post('/api/auth/login', {'email': email, 'password': password});
    await _afterAuth(result['token'] as String);
  }

  Future<void> register({required String email, required String name, required String password, String? inviteCode}) async {
    final result = await api.post('/api/auth/register', {
      'email': email,
      'name': name,
      'password': password,
      if (inviteCode != null && inviteCode.trim().isNotEmpty) 'invite_code': inviteCode.trim(),
    });
    await _afterAuth(result['token'] as String);
  }

  Future<void> _afterAuth(String token) async {
    api.token = token;
    await store.writeToken(token);
    loadError = null;
    await _loadAll();
    notifyListeners();
  }

  Future<void> signOut() async {
    try {
      await api.post('/api/auth/logout');
    } on ApiException {
      // Auch ohne Serverantwort lokal abmelden.
    }
    await _clear();
  }

  Future<void> deleteAccountAndData() async {
    await api.delete('/api/me');
    await _clear();
  }

  void _sessionExpired() => _clear();

  Future<void> _clear() async {
    api.token = null;
    me = null;
    accounts = [];
    niches = [];
    ideas = [];
    members = [];
    activeAccountId = null;
    await store.writeToken(null);
    await store.writeActiveAccount(null);
    notifyListeners();
  }

  // -------------------------------------------------------------------
  // Grunddaten
  // -------------------------------------------------------------------

  Future<void> _loadAll() async {
    me = Map<String, dynamic>.from(await api.get('/api/me') as Map);
    await Future.wait([
      refreshAccounts(notify: false),
      refreshNiches(notify: false),
      refreshIdeas(notify: false),
      refreshTeam(notify: false),
      refreshNotifications(notify: false),
    ]);
  }

  /// Lädt alles neu (Pull-to-Refresh, „Erneut versuchen“).
  Future<void> reload() async {
    final wasSignedIn = me != null;
    try {
      await _loadAll();
      loadError = null;
    } on ApiException catch (e) {
      loadError = e;
      // Beim Start (noch keine Daten) bleibt der Fehlerzustand sichtbar.
      if (!wasSignedIn) me = null;
    }
    notifyListeners();
  }

  Future<void> refreshAccounts({bool notify = true}) async {
    final list = await api.get('/api/accounts') as List;
    accounts = [for (final a in list) Account.fromJson(Map<String, dynamic>.from(a as Map))];
    // Gemerkter Account existiert nicht mehr: zurück auf „Alle Accounts“.
    if (activeAccountId != null && accountById(activeAccountId) == null) {
      activeAccountId = null;
      await store.writeActiveAccount(null);
    }
    if (notify) notifyListeners();
  }

  Future<void> refreshNiches({bool notify = true}) async {
    final list = await api.get('/api/niches') as List;
    niches = [for (final n in list) Niche.fromJson(Map<String, dynamic>.from(n as Map))];
    if (notify) notifyListeners();
  }

  Future<void> refreshIdeas({bool notify = true}) async {
    final list = await api.get('/api/ideas') as List;
    ideas = [for (final i in list) Idea.fromJson(Map<String, dynamic>.from(i as Map))];
    if (notify) notifyListeners();
  }

  Future<void> refreshTeam({bool notify = true}) async {
    final team = await api.get('/api/team') as Map;
    members = [for (final m in team['members'] as List) Map<String, dynamic>.from(m as Map)];
    if (notify) notifyListeners();
  }

  Future<void> refreshNotifications({bool notify = true}) async {
    final list = await api.get('/api/notifications') as List;
    unreadNotifications = list.where((n) => (n as Map)['read_at'] == null).length;
    if (notify) notifyListeners();
  }

  // -------------------------------------------------------------------
  // Account-Kontext
  // -------------------------------------------------------------------

  Future<void> setActiveAccount(String? id) async {
    if (id == activeAccountId) return;
    activeAccountId = id;
    notifyListeners();
    await store.writeActiveAccount(id);
  }

  /// Nächster bzw. vorheriger Account (Wischen über die Kopfzeile).
  /// Reihenfolge: Alle Accounts, dann jeder Account.
  Future<void> cycleAccount(int direction) async {
    if (accounts.isEmpty) return;
    final order = <String?>[null, ...accounts.map((a) => a.id)];
    final index = order.indexOf(activeAccountId);
    await setActiveAccount(order[(index + direction) % order.length]);
  }

  // -------------------------------------------------------------------
  // Ideen
  // -------------------------------------------------------------------

  /// Übernimmt eine vom Server gelieferte Idee in die Liste.
  Idea putIdea(Object json) {
    final idea = Idea.fromJson(Map<String, dynamic>.from(json as Map));
    ideas = [idea, ...ideas.where((i) => i.id != idea.id)];
    notifyListeners();
    return idea;
  }

  Future<Idea> createIdea(Map<String, dynamic> fields) async => putIdea(await api.post('/api/ideas', fields));

  Future<Idea> updateIdea(String id, Map<String, dynamic> fields) async => putIdea(await api.patch('/api/ideas/$id', fields));

  Future<void> deleteIdea(String id) async {
    await api.delete('/api/ideas/$id');
    ideas = ideas.where((i) => i.id != id).toList();
    notifyListeners();
  }
}

/// Stellt den [AppState] allen Seiten bereit: `AppScope.of(context)`.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  /// Liefert den Zustand und baut das Widget bei Änderungen neu.
  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Liefert den Zustand ohne Neuaufbau (für Aktionen in Callbacks).
  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
