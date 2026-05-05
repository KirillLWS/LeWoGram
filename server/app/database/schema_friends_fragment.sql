-- Друзья / заявки / блок (направленная запись from → to).
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS friendships (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    from_user_id INTEGER NOT NULL,
    to_user_id INTEGER NOT NULL,
    status TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (from_user_id) REFERENCES users (id),
    FOREIGN KEY (to_user_id) REFERENCES users (id),
    UNIQUE (from_user_id, to_user_id),
    CHECK (status IN ('pending', 'accepted', 'declined', 'blocked'))
);

CREATE INDEX IF NOT EXISTS ix_friendships_to_status
ON friendships (to_user_id, status);

CREATE INDEX IF NOT EXISTS ix_friendships_from_status
ON friendships (from_user_id, status);
