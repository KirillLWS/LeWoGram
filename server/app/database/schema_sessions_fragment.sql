-- Сессии устройств и refresh-токены (идемпотентно через apply_auth_sessions_migrations).

PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS auth_sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    refresh_token_hash TEXT NOT NULL UNIQUE,
    device_fingerprint TEXT NOT NULL,
    device_model TEXT,
    device_os TEXT,
    ip_address TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    last_used_at TEXT NOT NULL DEFAULT (datetime('now')),
    expires_at TEXT NOT NULL,
    revoked_at TEXT,
    FOREIGN KEY (user_id) REFERENCES users (id)
);

CREATE INDEX IF NOT EXISTS ix_auth_sessions_user ON auth_sessions (user_id);
