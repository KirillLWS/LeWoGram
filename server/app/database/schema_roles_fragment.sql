-- Additive roles / ownership (idempotent: IF NOT EXISTS, no DROP of data).
-- COORDINATOR: append to main schema or run via roles_migrations after base schema.

PRAGMA foreign_keys = ON;

-- One row per (user, role). Multiple owners allowed.
CREATE TABLE IF NOT EXISTS user_roles (
    user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('user', 'admin', 'chief_admin', 'developer', 'owner')),
    PRIMARY KEY (user_id, role)
);

CREATE INDEX IF NOT EXISTS idx_user_roles_user_id ON user_roles (user_id);
CREATE INDEX IF NOT EXISTS idx_user_roles_role ON user_roles (role);

-- Grant/revoke audit (admin + owner flows).
CREATE TABLE IF NOT EXISTS role_change_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    target_user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    actor_user_id INTEGER REFERENCES users (id) ON DELETE SET NULL,
    role TEXT NOT NULL,
    action TEXT NOT NULL CHECK (action IN ('grant', 'revoke')),
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_role_change_history_target ON role_change_history (
    target_user_id,
    created_at DESC
);
CREATE INDEX IF NOT EXISTS idx_role_change_history_created ON role_change_history (created_at DESC);

-- Singleton: initial owner token consumed once; stores SHA-256 hex of token used at claim time.
CREATE TABLE IF NOT EXISTS owner_claim_tokens (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    token_hash TEXT NOT NULL UNIQUE,
    claimed_at TEXT NOT NULL DEFAULT (datetime('now')),
    claimed_by_user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE RESTRICT
);
