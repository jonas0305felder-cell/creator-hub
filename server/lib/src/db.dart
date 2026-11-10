import 'package:postgres/postgres.dart';

/// Schlanker Zugriff auf PostgreSQL.
///
/// Alle Abfragen nutzen benannte Parameter (`@name`), Ergebnisse kommen als
/// `Map<String, dynamic>` je Zeile zurück.
class Db {
  Db(this._executor);

  /// Öffnet einen Verbindungs-Pool aus einer URL wie
  /// `postgresql://user:pass@localhost:5432/contenthub?sslmode=disable`.
  factory Db.connect(String url) => Db(Pool.withUrl(url));

  final SessionExecutor _executor;
  Session? _session;

  Future<List<Map<String, dynamic>>> query(
    String sql, [
    Map<String, Object?> params = const {},
  ]) async {
    final Result result;
    if (_session != null) {
      result = await _session!.execute(Sql.named(sql), parameters: params);
    } else {
      result = await (_executor as Session).execute(
        Sql.named(sql),
        parameters: params,
      );
    }
    return [for (final row in result) row.toColumnMap()];
  }

  Future<Map<String, dynamic>?> one(
    String sql, [
    Map<String, Object?> params = const {},
  ]) async {
    final rows = await query(sql, params);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> exec(String sql, [Map<String, Object?> params = const {}]) =>
      query(sql, params);

  /// Führt [fn] in einer Transaktion aus.
  Future<T> tx<T>(Future<T> Function(Db db) fn) {
    if (_session != null) return fn(this);
    return _executor.runTx((session) {
      final inner = Db(_executor).._session = session;
      return fn(inner);
    });
  }

  Future<void> close() => _executor.close();

  /// Legt Tabellen an bzw. bringt sie auf den aktuellen Stand.
  Future<void> migrate() async {
    await exec('CREATE TABLE IF NOT EXISTS schema_version (version int NOT NULL)');
    final row = await one('SELECT max(version) AS v FROM schema_version');
    final current = (row?['v'] as int?) ?? 0;
    for (var i = current; i < migrations.length; i++) {
      await tx((db) async {
        for (final statement in migrations[i].split(';\n')) {
          if (statement.trim().isEmpty) continue;
          await db.exec(statement);
        }
        await db.exec('INSERT INTO schema_version (version) VALUES (@v)', {
          'v': i + 1,
        });
      });
    }
  }
}

/// Datenbankschema nach Abschnitt 6 der Spezifikation.
/// Neue Änderungen immer als weiteren Eintrag anhängen, nie bestehende ändern.
const migrations = <String>[
  r'''
CREATE TABLE workspaces (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text NOT NULL UNIQUE,
  name text NOT NULL,
  auth_provider text NOT NULL DEFAULT 'email',
  password_hash text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE memberships (
  workspace_id uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role text NOT NULL CHECK (role IN ('owner','member')),
  PRIMARY KEY (workspace_id, user_id)
);
CREATE TABLE sessions (
  token_hash text PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL
);
CREATE TABLE invites (
  code text PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  created_by uuid REFERENCES users(id) ON DELETE SET NULL,
  expires_at timestamptz NOT NULL,
  used_by uuid REFERENCES users(id) ON DELETE SET NULL
);
CREATE TABLE instagram_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  ig_user_id text,
  username text NOT NULL,
  account_type text NOT NULL CHECK (account_type IN ('business','creator','manual')),
  profile_picture_url text,
  color text NOT NULL DEFAULT '#6C4CF1',
  tone text NOT NULL DEFAULT '',
  audience_note text NOT NULL DEFAULT '',
  language text NOT NULL DEFAULT 'de',
  connection_status text NOT NULL DEFAULT 'connected'
    CHECK (connection_status IN ('connected','expiring','disconnected','manual','syncing')),
  followers_count int,
  media_count int,
  last_synced_at timestamptz,
  last_sync_error text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX instagram_accounts_ig_user ON instagram_accounts (ig_user_id) WHERE ig_user_id IS NOT NULL;
CREATE TABLE instagram_credentials (
  account_id uuid PRIMARY KEY REFERENCES instagram_accounts(id) ON DELETE CASCADE,
  encrypted_access_token text NOT NULL,
  token_expires_at timestamptz,
  granted_scopes text NOT NULL DEFAULT '',
  login_type text NOT NULL CHECK (login_type IN ('instagram','facebook')),
  facebook_page_id text,
  last_refreshed_at timestamptz
);
CREATE TABLE oauth_states (
  state text PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  workspace_id uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  login_type text NOT NULL,
  account_id uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE oauth_results (
  code text PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  account_id uuid,
  error text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE niches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  name text NOT NULL,
  keywords jsonb NOT NULL DEFAULT '[]',
  language text NOT NULL DEFAULT 'de',
  region text NOT NULL DEFAULT 'DE'
);
CREATE TABLE account_niches (
  account_id uuid NOT NULL REFERENCES instagram_accounts(id) ON DELETE CASCADE,
  niche_id uuid NOT NULL REFERENCES niches(id) ON DELETE CASCADE,
  is_primary boolean NOT NULL DEFAULT false,
  PRIMARY KEY (account_id, niche_id)
);
CREATE TABLE account_daily_metrics (
  account_id uuid NOT NULL REFERENCES instagram_accounts(id) ON DELETE CASCADE,
  date date NOT NULL,
  metric text NOT NULL,
  value bigint,
  fetched_at timestamptz NOT NULL,
  PRIMARY KEY (account_id, date, metric)
);
CREATE TABLE follower_snapshots (
  account_id uuid NOT NULL REFERENCES instagram_accounts(id) ON DELETE CASCADE,
  date date NOT NULL,
  followers_count int NOT NULL,
  fetched_at timestamptz NOT NULL,
  PRIMARY KEY (account_id, date)
);
CREATE TABLE media (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL REFERENCES instagram_accounts(id) ON DELETE CASCADE,
  ig_media_id text NOT NULL,
  media_type text NOT NULL,
  media_product_type text NOT NULL,
  caption text,
  permalink text,
  thumbnail_url text,
  posted_at timestamptz,
  UNIQUE (account_id, ig_media_id)
);
CREATE TABLE media_metrics (
  media_id uuid NOT NULL REFERENCES media(id) ON DELETE CASCADE,
  metric text NOT NULL,
  value double precision,
  fetched_at timestamptz NOT NULL,
  PRIMARY KEY (media_id, metric)
);
CREATE TABLE story_metric_snapshots (
  media_id uuid NOT NULL REFERENCES media(id) ON DELETE CASCADE,
  captured_at timestamptz NOT NULL,
  metric text NOT NULL,
  value double precision,
  PRIMARY KEY (media_id, captured_at, metric)
);
CREATE TABLE comments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  media_id uuid NOT NULL REFERENCES media(id) ON DELETE CASCADE,
  ig_comment_id text NOT NULL UNIQUE,
  parent_comment_id text,
  author_username text NOT NULL,
  text text NOT NULL,
  created_at timestamptz NOT NULL,
  is_hidden boolean NOT NULL DEFAULT false,
  is_own boolean NOT NULL DEFAULT false,
  replied_by_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
  replied_at timestamptz,
  fetched_at timestamptz NOT NULL
);
CREATE TABLE trend_sources (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid REFERENCES workspaces(id) ON DELETE CASCADE,
  type text NOT NULL CHECK (type IN ('google_trends','rss','manual','hashtag','provider')),
  name text NOT NULL,
  url text,
  niche_id uuid REFERENCES niches(id) ON DELETE CASCADE,
  refresh_interval_hours int NOT NULL DEFAULT 12,
  last_success_at timestamptz,
  last_attempt_at timestamptz,
  last_error text
);
CREATE TABLE trends (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_id uuid NOT NULL REFERENCES trend_sources(id) ON DELETE CASCADE,
  external_id text,
  title text NOT NULL,
  summary text NOT NULL DEFAULT '',
  reason text NOT NULL DEFAULT '',
  source_url text,
  published_at timestamptz,
  fetched_at timestamptz NOT NULL DEFAULT now(),
  valid_until timestamptz,
  signal_value double precision,
  signal_unit text,
  created_by uuid REFERENCES users(id) ON DELETE SET NULL,
  listed boolean NOT NULL DEFAULT true,
  UNIQUE (source_id, external_id)
);
CREATE TABLE trend_niches (
  trend_id uuid NOT NULL REFERENCES trends(id) ON DELETE CASCADE,
  niche_id uuid NOT NULL REFERENCES niches(id) ON DELETE CASCADE,
  relevance_score double precision NOT NULL DEFAULT 1,
  PRIMARY KEY (trend_id, niche_id)
);
CREATE TABLE ideas (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  account_id uuid REFERENCES instagram_accounts(id) ON DELETE SET NULL,
  niche_id uuid REFERENCES niches(id) ON DELETE SET NULL,
  title text NOT NULL,
  note text NOT NULL DEFAULT '',
  format text CHECK (format IN ('reel','carousel','image','story')),
  status text NOT NULL DEFAULT 'idea'
    CHECK (status IN ('idea','in_progress','ready','published','discarded')),
  tags jsonb NOT NULL DEFAULT '[]',
  planned_for timestamptz,
  assignee_id uuid REFERENCES users(id) ON DELETE SET NULL,
  source_trend_id uuid REFERENCES trends(id) ON DELETE SET NULL,
  source_media_id uuid REFERENCES media(id) ON DELETE SET NULL,
  published_media_id uuid REFERENCES media(id) ON DELETE SET NULL,
  created_by uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE idea_attachments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  idea_id uuid NOT NULL REFERENCES ideas(id) ON DELETE CASCADE,
  type text NOT NULL CHECK (type IN ('image','audio','link','text')),
  storage_key text,
  url text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE content_suggestions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  idea_id uuid NOT NULL REFERENCES ideas(id) ON DELETE CASCADE,
  version int NOT NULL,
  format text,
  format_reason text NOT NULL DEFAULT '',
  hooks jsonb NOT NULL DEFAULT '[]',
  outline jsonb NOT NULL DEFAULT '[]',
  cta text NOT NULL DEFAULT '',
  caption_draft text NOT NULL DEFAULT '',
  hashtags jsonb NOT NULL DEFAULT '[]',
  model text NOT NULL DEFAULT '',
  prompt_context_hash text NOT NULL DEFAULT '',
  created_by uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  is_selected boolean NOT NULL DEFAULT false,
  UNIQUE (idea_id, version)
);
CREATE TABLE scheduled_posts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL REFERENCES instagram_accounts(id) ON DELETE CASCADE,
  idea_id uuid REFERENCES ideas(id) ON DELETE SET NULL,
  suggestion_id uuid REFERENCES content_suggestions(id) ON DELETE SET NULL,
  format text NOT NULL CHECK (format IN ('post','reel','carousel')),
  caption text NOT NULL DEFAULT '',
  scheduled_for timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'scheduled'
    CHECK (status IN ('draft','scheduled','publishing','published','failed')),
  ig_container_id text,
  published_media_id uuid REFERENCES media(id) ON DELETE SET NULL,
  published_permalink text,
  error_message text,
  created_by uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE scheduled_post_media (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  scheduled_post_id uuid NOT NULL REFERENCES scheduled_posts(id) ON DELETE CASCADE,
  position int NOT NULL,
  storage_key text NOT NULL,
  public_url_expires_at timestamptz,
  mime_type text NOT NULL
);
CREATE TABLE competitor_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL REFERENCES instagram_accounts(id) ON DELETE CASCADE,
  username text NOT NULL,
  ig_user_id text,
  added_by uuid REFERENCES users(id) ON DELETE SET NULL,
  last_error text,
  UNIQUE (account_id, username)
);
CREATE TABLE competitor_snapshots (
  competitor_id uuid NOT NULL REFERENCES competitor_accounts(id) ON DELETE CASCADE,
  date date NOT NULL,
  followers_count int,
  media_count int,
  avg_likes double precision,
  avg_comments double precision,
  fetched_at timestamptz NOT NULL,
  PRIMARY KEY (competitor_id, date)
);
CREATE TABLE hashtag_watches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL REFERENCES instagram_accounts(id) ON DELETE CASCADE,
  hashtag text NOT NULL,
  ig_hashtag_id text,
  first_queried_at timestamptz NOT NULL DEFAULT now(),
  active boolean NOT NULL DEFAULT true,
  UNIQUE (account_id, hashtag)
);
CREATE TABLE notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  account_id uuid REFERENCES instagram_accounts(id) ON DELETE CASCADE,
  kind text NOT NULL,
  title text NOT NULL,
  body text NOT NULL DEFAULT '',
  target text,
  created_at timestamptz NOT NULL DEFAULT now(),
  read_at timestamptz
);
CREATE TABLE audit_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid REFERENCES workspaces(id) ON DELETE CASCADE,
  user_id uuid REFERENCES users(id) ON DELETE SET NULL,
  action text NOT NULL,
  target text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE deletion_requests (
  confirmation_code text PRIMARY KEY,
  ig_user_id text,
  status text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE job_runs (
  name text PRIMARY KEY,
  last_run_at timestamptz NOT NULL
)
''',
];
