-- Модерация: жалобы, история разборов, санкции (подключается координатором к основной схеме / миграциям).

PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------------------
-- Жалобы пользователей (user / profile / message)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS reports (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    reporter_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    target_type TEXT NOT NULL CHECK (target_type IN ('user', 'profile', 'message')),
    target_user_id INTEGER REFERENCES users (id) ON DELETE SET NULL,
    target_message_id INTEGER REFERENCES messages (id) ON DELETE SET NULL,
    reason_code TEXT NOT NULL DEFAULT 'other',
    description TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'open' CHECK (
        status IN ('open', 'in_review', 'resolved', 'rejected', 'dismissed')
    ),
    resolution_note TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    resolved_at TEXT,
    resolved_by INTEGER REFERENCES users (id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS report_resolution_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    report_id INTEGER NOT NULL REFERENCES reports (id) ON DELETE CASCADE,
    actor_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    action TEXT NOT NULL CHECK (
        action IN ('created', 'note', 'status_change', 'resolve', 'reject', 'dismiss')
    ),
    from_status TEXT,
    to_status TEXT,
    note TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS user_sanctions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    sanction_type TEXT NOT NULL CHECK (
        sanction_type IN ('warning', 'mute', 'ban', 'shadow_ban', 'other')
    ),
    reason TEXT,
    report_id INTEGER REFERENCES reports (id) ON DELETE SET NULL,
    created_by INTEGER NOT NULL REFERENCES users (id) ON DELETE RESTRICT,
    is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
    starts_at TEXT NOT NULL DEFAULT (datetime('now')),
    ends_at TEXT,
    revoked_at TEXT,
    revoked_by INTEGER REFERENCES users (id) ON DELETE SET NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_reports_status_created ON reports (status, created_at);
CREATE INDEX IF NOT EXISTS idx_reports_reporter ON reports (reporter_id);
CREATE INDEX IF NOT EXISTS idx_reports_target_user ON reports (target_user_id);
CREATE INDEX IF NOT EXISTS idx_reports_target_message ON reports (target_message_id);
CREATE INDEX IF NOT EXISTS idx_report_history_report ON report_resolution_history (report_id, created_at);
CREATE INDEX IF NOT EXISTS idx_sanctions_user_active ON user_sanctions (user_id, is_active);
CREATE INDEX IF NOT EXISTS idx_sanctions_type ON user_sanctions (sanction_type, is_active);
