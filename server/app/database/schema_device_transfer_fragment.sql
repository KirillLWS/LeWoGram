-- Запросы на смену / добавление устройства (идемпотентно).

PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS device_transfer_requests (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    mode TEXT NOT NULL,
    req_device_fingerprint TEXT NOT NULL,
    req_device_model TEXT,
    req_device_os TEXT,
    req_ip_address TEXT,
    req_geo_lat REAL,
    req_geo_lng REAL,
    req_geo_accuracy_m REAL,
    reason TEXT NOT NULL,
    status TEXT NOT NULL,
    decided_by INTEGER,
    decision_note TEXT,
    revoke_old_devices INTEGER NOT NULL DEFAULT 0 CHECK (revoke_old_devices IN (0, 1)),
    short_code TEXT NOT NULL,
    short_code_hash TEXT NOT NULL,
    poll_access_token TEXT,
    poll_refresh_token TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    decided_at TEXT,
    expires_at TEXT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users (id),
    FOREIGN KEY (decided_by) REFERENCES users (id)
);

CREATE INDEX IF NOT EXISTS ix_dtr_status_user ON device_transfer_requests (status, user_id);
