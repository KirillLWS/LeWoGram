-- Финальная схема SQLite LeWoGram.
-- PRAGMA в начале; булевы поля — INTEGER 0/1 + CHECK; created_at где указано — DEFAULT (datetime('now')).

PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------------------
-- Пользователи и связанные сущности
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    login TEXT NOT NULL COLLATE NOCASE,
    username TEXT COLLATE NOCASE,
    display_name TEXT,
    password_hash TEXT NOT NULL,
    device_fingerprint TEXT,
    email TEXT UNIQUE,
    phone TEXT UNIQUE,
    birth_date TEXT,
    avatar_path TEXT,
    about TEXT NOT NULL DEFAULT '',
    is_online INTEGER NOT NULL DEFAULT 0 CHECK (is_online IN (0, 1)),
    is_blocked INTEGER NOT NULL DEFAULT 0 CHECK (is_blocked IN (0, 1)),
    account_status TEXT NOT NULL DEFAULT 'active',
    ban_until TEXT,
    ban_reason TEXT NOT NULL DEFAULT '',
    staff_ban INTEGER NOT NULL DEFAULT 0 CHECK (staff_ban IN (0, 1)),
    must_change_password INTEGER NOT NULL DEFAULT 0 CHECK (must_change_password IN (0, 1)),
    notification_token TEXT,
    last_device_model TEXT,
    last_device_os TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    last_seen_at TEXT
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_login ON users(login COLLATE NOCASE);

CREATE TABLE IF NOT EXISTS invite_links (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    token TEXT NOT NULL UNIQUE,
    created_by INTEGER NOT NULL REFERENCES users (id) ON DELETE RESTRICT,
    expires_at TEXT,
    used_at TEXT,
    used_by INTEGER REFERENCES users (id) ON DELETE SET NULL,
    is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1))
);

CREATE TABLE IF NOT EXISTS login_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER REFERENCES users (id) ON DELETE SET NULL,
    device_fingerprint TEXT,
    ip_address TEXT,
    logged_in_at TEXT NOT NULL DEFAULT (datetime('now')),
    success INTEGER NOT NULL CHECK (success IN (0, 1))
);

CREATE TABLE IF NOT EXISTS recovery_requests (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    requested_at TEXT NOT NULL DEFAULT (datetime('now')),
    status TEXT NOT NULL DEFAULT 'pending'
);

CREATE TABLE IF NOT EXISTS master_keys (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    key_hash TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- ---------------------------------------------------------------------------
-- Чаты
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS chats (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    type TEXT NOT NULL,
    title TEXT,
    description TEXT,
    avatar_path TEXT,
    created_by INTEGER REFERENCES users (id) ON DELETE SET NULL,
    is_archived INTEGER NOT NULL DEFAULT 0 CHECK (is_archived IN (0, 1)),
    members_count INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS chat_members (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    chat_id INTEGER NOT NULL REFERENCES chats (id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'member',
    can_write INTEGER NOT NULL DEFAULT 1 CHECK (can_write IN (0, 1)),
    joined_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE (chat_id, user_id)
);

CREATE TABLE IF NOT EXISTS chat_avatars (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    chat_id INTEGER NOT NULL REFERENCES chats (id) ON DELETE CASCADE,
    file_path TEXT NOT NULL,
    is_current INTEGER NOT NULL DEFAULT 1 CHECK (is_current IN (0, 1)),
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- ---------------------------------------------------------------------------
-- Сообщения (после chats и users)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    chat_id INTEGER NOT NULL REFERENCES chats (id) ON DELETE CASCADE,
    sender_id INTEGER REFERENCES users (id) ON DELETE SET NULL,
    type TEXT NOT NULL,
    text TEXT,
    file_path TEXT,
    file_name TEXT,
    file_size INTEGER,
    duration_sec INTEGER,
    thumbnail_path TEXT,
    reply_to_id INTEGER REFERENCES messages (id) ON DELETE SET NULL,
    is_deleted INTEGER NOT NULL DEFAULT 0 CHECK (is_deleted IN (0, 1)),
    is_edited INTEGER NOT NULL DEFAULT 0 CHECK (is_edited IN (0, 1)),
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    edited_at TEXT
);

CREATE TABLE IF NOT EXISTS message_reads (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    message_id INTEGER NOT NULL REFERENCES messages (id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    read_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE (message_id, user_id)
);

CREATE TABLE IF NOT EXISTS message_reactions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    message_id INTEGER NOT NULL REFERENCES messages (id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    emoji TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE (message_id, user_id, emoji)
);

-- ---------------------------------------------------------------------------
-- Профиль: аватарки (история), настройки (1:1), аналитика
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS user_avatars (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    file_path TEXT NOT NULL,
    is_current INTEGER NOT NULL DEFAULT 0 CHECK (is_current IN (0, 1)),
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS user_settings (
    user_id INTEGER PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    notifications_enabled INTEGER NOT NULL DEFAULT 1 CHECK (notifications_enabled IN (0, 1)),
    sound_enabled INTEGER NOT NULL DEFAULT 1 CHECK (sound_enabled IN (0, 1)),
    vibration_enabled INTEGER NOT NULL DEFAULT 1 CHECK (vibration_enabled IN (0, 1)),
    show_read_receipts INTEGER NOT NULL DEFAULT 1 CHECK (show_read_receipts IN (0, 1)),
    show_online_status INTEGER NOT NULL DEFAULT 1 CHECK (show_online_status IN (0, 1)),
    language TEXT NOT NULL DEFAULT 'ru',
    theme TEXT NOT NULL DEFAULT 'system',
    font_size TEXT NOT NULL DEFAULT 'medium',
    last_read_message_id INTEGER REFERENCES messages (id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS user_analytics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    event_type TEXT NOT NULL,
    event_data TEXT,
    ip_address TEXT,
    device_model TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- ---------------------------------------------------------------------------
-- Отчёты, OTA, сессии, активность, «не беспокоить»
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS app_reports (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER REFERENCES users (id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    description TEXT,
    app_version TEXT,
    device_model TEXT,
    device_os TEXT,
    logs_path TEXT,
    status TEXT NOT NULL DEFAULT 'new' CHECK (status IN ('new', 'read', 'fixed', 'wontfix')),
    admin_note TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS app_versions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    version_code INTEGER NOT NULL UNIQUE,
    version_name TEXT NOT NULL,
    apk_path TEXT NOT NULL,
    changelog TEXT,
    is_forced INTEGER NOT NULL DEFAULT 0 CHECK (is_forced IN (0, 1)),
    min_version_code INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    released_at TEXT
);

CREATE TABLE IF NOT EXISTS notification_schedules (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK (type IN ('manual', 'schedule', 'location')),
    is_active INTEGER NOT NULL DEFAULT 0 CHECK (is_active IN (0, 1)),
    time_from TEXT,
    time_until TEXT,
    days_of_week TEXT,
    latitude REAL,
    longitude REAL,
    radius_meters INTEGER,
    location_name TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS network_sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    connection_type TEXT NOT NULL CHECK (connection_type IN ('wifi', 'mobile', 'unknown')),
    carrier_name TEXT,
    carrier_country TEXT,
    ip_address TEXT,
    city TEXT,
    started_at TEXT NOT NULL DEFAULT (datetime('now')),
    ended_at TEXT,
    messages_sent INTEGER NOT NULL DEFAULT 0,
    bytes_sent INTEGER NOT NULL DEFAULT 0,
    bytes_received INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS user_activity_periods (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    started_at TEXT NOT NULL DEFAULT (datetime('now')),
    ended_at TEXT,
    duration_sec INTEGER,
    screen TEXT NOT NULL CHECK (screen IN ('chat', 'profile', 'admin', 'settings', 'channel'))
);

-- ---------------------------------------------------------------------------
-- Индексы
-- ---------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_messages_chat_created ON messages (chat_id, created_at);
CREATE INDEX IF NOT EXISTS idx_messages_sender ON messages (sender_id);
CREATE INDEX IF NOT EXISTS idx_chat_members_user ON chat_members (user_id);
CREATE INDEX IF NOT EXISTS idx_user_analytics_user_event ON user_analytics (user_id, event_type);
CREATE INDEX IF NOT EXISTS idx_login_logs_user ON login_logs (user_id);

CREATE INDEX IF NOT EXISTS idx_app_reports_user_status ON app_reports (user_id, status);
CREATE INDEX IF NOT EXISTS idx_app_reports_created ON app_reports (created_at);
CREATE INDEX IF NOT EXISTS idx_app_versions_code ON app_versions (version_code);
CREATE INDEX IF NOT EXISTS idx_network_sessions_user_started ON network_sessions (user_id, started_at);
CREATE INDEX IF NOT EXISTS idx_user_activity_user_started ON user_activity_periods (user_id, started_at);
CREATE INDEX IF NOT EXISTS idx_notification_schedules_user_type ON notification_schedules (user_id, type);

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username_unique ON users(username COLLATE NOCASE);
