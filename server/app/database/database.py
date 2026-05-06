"""
Единая точка доступа к SQLite для LeWoGram.

Все SQL сосредоточен здесь: при переходе на PostgreSQL меняется в основном этот модуль
(и драйвер), вызовы из auth/messages/admin остаются теми же по смыслу.
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any, Sequence

import aiosqlite

logger = logging.getLogger(__name__)

_SCHEMA_PATH = Path(__file__).resolve().parent / "schema.sql"


def _row_to_dict(row: aiosqlite.Row) -> dict[str, Any]:
    """Преобразует строку aiosqlite.Row в обычный dict для API сервисов."""
    return {key: row[key] for key in row.keys()}


class Database:
    """
    Асинхронная обёртка над SQLite (aiosqlite).

    Подключение открывается на время операции в каждом методе — для ~30 пользователей
    этого достаточно; позже можно добавить пул или одно долгоживущее соединение.
    """

    def __init__(self, db_path: str | Path) -> None:
        self._db_path = Path(db_path)

    @property
    def db_path(self) -> Path:
        """Путь к файлу SQLite (низкоуровневые модули: friends, roles, …)."""
        return self._db_path

    async def init_db(self) -> None:
        """Создаёт каталог для файла БД, применяет schema.sql и безопасные миграции."""
        self._db_path.parent.mkdir(parents=True, exist_ok=True)
        sql = _SCHEMA_PATH.read_text(encoding="utf-8")
        async with aiosqlite.connect(self._db_path) as db:
            await db.executescript(sql)
            await db.commit()
        await self._migrate_users_username()
        await self._migrate_invite_link_extras()
        await self._migrate_users_recovery_phrase()
        from app.database.roles_migrations import apply_roles_migrations

        await apply_roles_migrations(self._db_path)
        from app.database.push_migrations import apply_push_migrations

        await apply_push_migrations(self._db_path)
        from app.database.friends_migrations import apply_friends_migrations

        await apply_friends_migrations(self._db_path)
        from app.database.auth_sessions_migrations import apply_auth_sessions_migrations

        await apply_auth_sessions_migrations(self._db_path)
        from app.database.device_transfer_migrations import apply_device_transfer_migrations

        await apply_device_transfer_migrations(self._db_path)
        from app.database.user_moderation_migrations import apply_user_moderation_migrations

        await apply_user_moderation_migrations(self._db_path)
        from app.database.support_diagnostics_migrations import apply_support_diagnostics_migrations

        await apply_support_diagnostics_migrations(self._db_path)
        from app.database.support_access_migrations import apply_support_access_migrations

        await apply_support_access_migrations(self._db_path)
        from app.database.support_chat_migrations import apply_support_chat_migrations

        await apply_support_chat_migrations(self._db_path)
        from app.database.user_audit_migrations import apply_user_audit_migrations

        await apply_user_audit_migrations(self._db_path)
        from app.database.reports_migrations import apply_all_reports_migrations

        await apply_all_reports_migrations(self._db_path)
        from app.database.live_geo_migrations import apply_live_geo_migrations

        await apply_live_geo_migrations(self._db_path)
        from app.database.support_tickets_migrations import apply_support_tickets_migrations

        await apply_support_tickets_migrations(self._db_path)
        await self._migrate_chats_timeline_index()
        logger.info("База инициализирована: %s", self._db_path)

    async def _migrate_chats_timeline_index(self) -> None:
        """Индекс для списка чатов владельца (ORDER BY created_at / updated_at)."""
        async with aiosqlite.connect(self._db_path) as db:
            await db.execute(
                "CREATE INDEX IF NOT EXISTS idx_chats_created_at ON chats(created_at)",
            )
            await db.execute(
                "CREATE INDEX IF NOT EXISTS idx_chats_updated_at ON chats(updated_at)",
            )
            await db.commit()

    async def _migrate_users_username(self) -> None:
        """
        Добавляет колонку users.username при отсутствии, заполняет из login,
        создаёт уникальный индекс COLLATE NOCASE (идемпотентно).
        """
        async with aiosqlite.connect(self._db_path) as db:
            async with db.execute("PRAGMA table_info(users)") as cur:
                cols = {str(row[1]) for row in await cur.fetchall()}
            if "username" not in cols:
                await db.execute(
                    "ALTER TABLE users ADD COLUMN username TEXT COLLATE NOCASE",
                )
                await db.commit()
            await db.execute(
                """
                UPDATE users
                SET username = login
                WHERE username IS NULL OR trim(username) = ''
                """,
            )
            await db.commit()
            await db.execute(
                """
                CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username_unique
                ON users(username COLLATE NOCASE)
                """,
            )
            await db.commit()

    async def _migrate_invite_link_extras(self) -> None:
        """
        Добавляет note, created_at (и max_uses для будущего) в invite_links без потери строк.
        """
        async with aiosqlite.connect(self._db_path) as db:
            async with db.execute("PRAGMA table_info(invite_links)") as cur:
                cols = {str(row[1]) for row in await cur.fetchall()}
            if "note" not in cols:
                await db.execute("ALTER TABLE invite_links ADD COLUMN note TEXT")
            if "created_at" not in cols:
                await db.execute("ALTER TABLE invite_links ADD COLUMN created_at TEXT")
            if "max_uses" not in cols:
                await db.execute("ALTER TABLE invite_links ADD COLUMN max_uses INTEGER")
            await db.commit()
            await db.execute(
                """
                UPDATE invite_links
                SET created_at = datetime('now')
                WHERE created_at IS NULL OR trim(created_at) = ''
                """,
            )
            await db.commit()

    async def _migrate_users_recovery_phrase(self) -> None:
        """Колонка recovery_phrase_hash для BIP39-фразы (опционально при регистрации)."""
        async with aiosqlite.connect(self._db_path) as db:
            async with db.execute("PRAGMA table_info(users)") as cur:
                cols = {str(row[1]) for row in await cur.fetchall()}
            if "recovery_phrase_hash" not in cols:
                await db.execute(
                    "ALTER TABLE users ADD COLUMN recovery_phrase_hash TEXT",
                )
                await db.commit()

    async def get_user_by_login(self, login: str) -> dict[str, Any] | None:
        async with aiosqlite.connect(self._db_path) as db:
            db.row_factory = aiosqlite.Row
            async with db.execute(
                "SELECT * FROM users WHERE login = ? COLLATE NOCASE",
                (login.strip(),),
            ) as cur:
                row = await cur.fetchone()
        return _row_to_dict(row) if row else None

    async def get_user_by_id(self, user_id: int) -> dict[str, Any] | None:
        async with aiosqlite.connect(self._db_path) as db:
            db.row_factory = aiosqlite.Row
            async with db.execute(
                "SELECT * FROM users WHERE id = ?",
                (user_id,),
            ) as cur:
                row = await cur.fetchone()
        return _row_to_dict(row) if row else None

    async def clear_expired_temp_ban(self, user_id: int) -> None:
        """Снимает истёкший temp_banned (включая staff-временную блокировку)."""
        async with aiosqlite.connect(self._db_path) as db:
            await db.execute(
                """
                UPDATE users
                SET account_status = 'active',
                    is_blocked = 0,
                    ban_until = NULL,
                    ban_reason = '',
                    staff_ban = 0
                WHERE id = ?
                  AND account_status = 'temp_banned'
                  AND ban_until IS NOT NULL
                  AND trim(ban_until) != ''
                  AND datetime(ban_until) <= datetime('now')
                """,
                (user_id,),
            )
            await db.commit()

    async def list_users_for_staff(
        self,
        *,
        limit: int = 50,
        offset: int = 0,
        query: str | None = None,
    ) -> tuple[list[dict[str, Any]], int]:
        lim = max(1, min(limit, 200))
        off = max(0, offset)
        where = "1=1"
        params: list[Any] = []
        if query and query.strip():
            esc = self._escape_like_pattern(query.strip())
            pat = f"%{esc}%"
            where = """(
                login COLLATE NOCASE LIKE ? ESCAPE '\\'
                OR (username IS NOT NULL AND username COLLATE NOCASE LIKE ? ESCAPE '\\')
                OR (display_name IS NOT NULL AND display_name COLLATE NOCASE LIKE ? ESCAPE '\\')
            )"""
            params.extend([pat, pat, pat])
        count_sql = f"SELECT COUNT(*) FROM users WHERE {where}"
        list_sql = f"""
            SELECT id, login, username, display_name, avatar_path,
                   account_status, ban_until, ban_reason, staff_ban,
                   is_blocked, created_at, last_seen_at
            FROM users
            WHERE {where}
            ORDER BY id ASC
            LIMIT ? OFFSET ?
        """
        async with aiosqlite.connect(self._db_path) as db:
            db.row_factory = aiosqlite.Row
            async with db.execute(count_sql, params) as cur:
                row = await cur.fetchone()
                total = int(row[0]) if row and row[0] is not None else 0
            qparams = [*params, lim, off]
            async with db.execute(list_sql, qparams) as cur:
                rows = await cur.fetchall()
        return [_row_to_dict(r) for r in rows], total

    async def staff_set_perm_ban(self, user_id: int, reason: str) -> None:
        """Staff-бан: только поля аккаунта; связи friends не трогаем."""
        r = (reason or "").strip()
        async with aiosqlite.connect(self._db_path) as db:
            await db.execute(
                """
                UPDATE users
                SET staff_ban = 1,
                    account_status = 'banned',
                    is_blocked = 1,
                    ban_until = NULL,
                    ban_reason = ?
                WHERE id = ?
                """,
                (r, user_id),
            )
            await db.commit()

    async def staff_set_temp_ban(self, user_id: int, reason: str, ban_until_utc: str) -> None:
        r = (reason or "").strip()
        async with aiosqlite.connect(self._db_path) as db:
            await db.execute(
                """
                UPDATE users
                SET staff_ban = 1,
                    account_status = 'temp_banned',
                    is_blocked = 1,
                    ban_until = ?,
                    ban_reason = ?
                WHERE id = ?
                """,
                (ban_until_utc, r, user_id),
            )
            await db.commit()

    async def staff_unban(self, user_id: int) -> None:
        """Снимает staff-блокировку; при активной санкции ban оставляет аккаунт заблокированным."""
        import app.database.db_reports as db_reports

        n = await db_reports.count_active_bans_for_user(self, user_id)
        async with aiosqlite.connect(self._db_path) as db:
            if n > 0:
                await db.execute(
                    """
                    UPDATE users
                    SET staff_ban = 0,
                        account_status = 'banned',
                        is_blocked = 1,
                        ban_until = NULL
                    WHERE id = ?
                    """,
                    (user_id,),
                )
            else:
                await db.execute(
                    """
                    UPDATE users
                    SET staff_ban = 0,
                        account_status = 'active',
                        is_blocked = 0,
                        ban_until = NULL,
                        ban_reason = ''
                    WHERE id = ?
                    """,
                    (user_id,),
                )
            await db.commit()

    async def list_user_roles(self, user_id: int) -> list[str]:
        from app.database import db_roles

        return await db_roles.list_user_roles(self._db_path, user_id)

    async def rbac_user_has_any_role(
        self, user_id: int, required_roles: frozenset[str] | Sequence[str]
    ) -> bool:
        from app.database import db_roles

        return await db_roles.rbac_user_has_any_role(
            self._db_path, user_id, required_roles
        )

    async def get_role_change_history(
        self,
        *,
        target_user_id: int | None = None,
        limit: int = 200,
    ) -> list[dict[str, Any]]:
        from app.database import db_roles

        return await db_roles.fetch_role_history(
            self._db_path,
            target_user_id=target_user_id,
            limit=limit,
        )

    async def is_username_taken(self, username: str, exclude_user_id: int | None = None) -> bool:
        u = username.strip()
        sql = """
            SELECT 1 FROM users
            WHERE username IS NOT NULL AND username = ? COLLATE NOCASE
        """
        params: list[Any] = [u]
        if exclude_user_id is not None:
            sql += " AND id != ?"
            params.append(exclude_user_id)
        sql += " LIMIT 1"
        async with aiosqlite.connect(self._db_path) as db:
            async with db.execute(sql, params) as cur:
                row = await cur.fetchone()
        return row is not None

    async def patch_user_me(
        self,
        user_id: int,
        *,
        display_name: str | None = None,
        username: str | None = None,
        about: str | None = None,
    ) -> None:
        parts: list[str] = []
        params: list[Any] = []
        if display_name is not None:
            parts.append("display_name = ?")
            params.append(display_name)
        if username is not None:
            parts.append("username = ?")
            params.append(username)
        if about is not None:
            parts.append("about = ?")
            params.append(about)
        if not parts:
            return
        params.append(user_id)
        sql = f"UPDATE users SET {', '.join(parts)} WHERE id = ?"
        async with aiosqlite.connect(self._db_path) as db:
            await db.execute(sql, params)
            await db.commit()

    @staticmethod
    def _escape_like_pattern(q: str) -> str:
        return q.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")

    async def search_users(
        self,
        query: str,
        exclude_user_id: int,
        limit: int = 50,
    ) -> list[dict[str, Any]]:
        esc = self._escape_like_pattern(query.strip())
        pattern = f"%{esc}%"
        lim = max(1, min(limit, 100))
        sql = """
            SELECT id, username, display_name, about, avatar_path
            FROM users
            WHERE id != ?
              AND is_blocked = 0
              AND (
                (username IS NOT NULL AND username COLLATE NOCASE LIKE ? ESCAPE '\\')
                OR (display_name IS NOT NULL AND display_name COLLATE NOCASE LIKE ? ESCAPE '\\')
              )
            ORDER BY username COLLATE NOCASE
            LIMIT ?
        """
        async with aiosqlite.connect(self._db_path) as db:
            db.row_factory = aiosqlite.Row
            async with db.execute(
                sql,
                (exclude_user_id, pattern, pattern, lim),
            ) as cur:
                rows = await cur.fetchall()
        return [_row_to_dict(r) for r in rows]

    async def get_user_public_profile(self, user_id: int) -> dict[str, Any] | None:
        async with aiosqlite.connect(self._db_path) as db:
            db.row_factory = aiosqlite.Row
            async with db.execute(
                """
                SELECT id, username, display_name, about, avatar_path, is_blocked,
                       account_status, ban_until, ban_reason
                FROM users WHERE id = ?
                """,
                (user_id,),
            ) as cur:
                row = await cur.fetchone()
        return _row_to_dict(row) if row else None

    async def list_all_chats_for_owner(
        self, *, limit: int = 50, offset: int = 0
    ) -> list[dict[str, Any]]:
        lim = max(1, min(limit, 100))
        off = max(0, offset)
        async with aiosqlite.connect(self._db_path) as db:
            db.row_factory = aiosqlite.Row
            async with db.execute(
                """
                SELECT id, type, title, created_by, created_at, updated_at
                FROM chats
                ORDER BY COALESCE(updated_at, created_at) DESC, id DESC
                LIMIT ? OFFSET ?
                """,
                (lim, off),
            ) as cur:
                rows = await cur.fetchall()
        return [_row_to_dict(r) for r in rows]

    async def create_user(
        self,
        login: str,
        password_hash: str,
        fingerprint: str | None,
        display_name: str | None = None,
        recovery_phrase_hash: str | None = None,
    ) -> int:
        login_clean = login.strip()
        async with aiosqlite.connect(self._db_path) as db:
            if recovery_phrase_hash is not None:
                cursor = await db.execute(
                    """
                    INSERT INTO users (
                        login, username, password_hash, device_fingerprint,
                        display_name, recovery_phrase_hash
                    )
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    (login_clean, login_clean, password_hash, fingerprint, display_name, recovery_phrase_hash),
                )
            else:
                cursor = await db.execute(
                    """
                    INSERT INTO users (login, username, password_hash, device_fingerprint, display_name)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    (login_clean, login_clean, password_hash, fingerprint, display_name),
                )
            await db.commit()
            new_id = int(cursor.lastrowid)
        from app.database.db_roles import ensure_default_user_role

        await ensure_default_user_role(self._db_path, new_id)
        logger.debug("Создан пользователь id=%s login=%s", new_id, login_clean)
        return new_id

    async def update_last_seen(self, user_id: int) -> None:
        async with aiosqlite.connect(self._db_path) as db:
            await db.execute(
                "UPDATE users SET last_seen_at = datetime('now') WHERE id = ?",
                (user_id,),
            )
            await db.commit()

    async def create_user_settings(self, user_id: int) -> None:
        async with aiosqlite.connect(self._db_path) as db:
            await db.execute(
                "INSERT OR IGNORE INTO user_settings (user_id) VALUES (?)",
                (user_id,),
            )
            await db.commit()

    async def update_user_device(
        self,
        user_id: int,
        device_model: str | None,
        device_os: str | None,
    ) -> None:
        parts: list[str] = []
        params: list[Any] = []
        if device_model is not None:
            parts.append("last_device_model = ?")
            params.append(device_model)
        if device_os is not None:
            parts.append("last_device_os = ?")
            params.append(device_os)
        if not parts:
            return
        params.append(user_id)
        sql = f"UPDATE users SET {', '.join(parts)} WHERE id = ?"
        async with aiosqlite.connect(self._db_path) as db:
            await db.execute(sql, params)
            await db.commit()

    async def bind_user_fingerprint_if_missing(self, user_id: int, fingerprint: str) -> None:
        async with aiosqlite.connect(self._db_path) as db:
            await db.execute(
                """
                UPDATE users
                SET device_fingerprint = ?
                WHERE id = ? AND (device_fingerprint IS NULL OR device_fingerprint = '')
                """,
                (fingerprint, user_id),
            )
            await db.commit()

    async def update_user_password(self, user_id: int, password_hash: str) -> None:
        async with aiosqlite.connect(self._db_path) as db:
            await db.execute(
                """
                UPDATE users
                SET password_hash = ?, must_change_password = 0
                WHERE id = ?
                """,
                (password_hash, user_id),
            )
            await db.commit()

    async def create_invite(
        self,
        token: str,
        created_by: int,
        expires_at: str | None,
        *,
        note: str | None = None,
    ) -> int:
        async with aiosqlite.connect(self._db_path) as db:
            cur = await db.execute(
                """
                INSERT INTO invite_links (token, created_by, expires_at, note, created_at)
                VALUES (?, ?, ?, ?, datetime('now'))
                """,
                (token, created_by, expires_at, note),
            )
            await db.commit()
            return int(cur.lastrowid)

    async def list_invite_links(self, limit: int = 100) -> list[dict[str, Any]]:
        """Список инвайтов для админки (новые сверху)."""
        async with aiosqlite.connect(self._db_path) as db:
            db.row_factory = aiosqlite.Row
            async with db.execute(
                """
                SELECT
                    il.id,
                    il.token,
                    il.created_by AS created_by_user_id,
                    il.expires_at,
                    il.used_at,
                    il.is_active,
                    il.note,
                    il.created_at
                FROM invite_links il
                ORDER BY il.id DESC
                LIMIT ?
                """,
                (limit,),
            ) as cur:
                rows = await cur.fetchall()
        out: list[dict[str, Any]] = []
        for row in rows:
            d = _row_to_dict(row)
            out.append(
                {
                    "id": int(d["id"]),
                    "token": str(d["token"]),
                    "is_active": bool(int(d.get("is_active", 1))),
                    "used_at": d.get("used_at"),
                    "expires_at": d.get("expires_at"),
                    "created_at": d.get("created_at"),
                    "created_by_user_id": int(d["created_by_user_id"]),
                    "note": d.get("note"),
                }
            )
        return out

    async def get_invite_by_token(self, token: str) -> dict[str, Any] | None:
        async with aiosqlite.connect(self._db_path) as db:
            db.row_factory = aiosqlite.Row
            async with db.execute(
                "SELECT * FROM invite_links WHERE token = ?",
                (token,),
            ) as cur:
                row = await cur.fetchone()
        return _row_to_dict(row) if row else None

    async def use_invite(self, token: str, used_by_user_id: int) -> bool:
        async with aiosqlite.connect(self._db_path) as db:
            cur = await db.execute(
                """
                UPDATE invite_links
                SET used_at = datetime('now'), used_by = ?, is_active = 0
                WHERE token = ? AND is_active = 1 AND used_at IS NULL
                """,
                (used_by_user_id, token),
            )
            await db.commit()
            return cur.rowcount > 0

    async def add_login_log(
        self,
        user_id: int | None,
        device_fingerprint: str | None,
        ip_address: str | None,
        success: bool,
    ) -> int:
        val = 1 if success else 0
        async with aiosqlite.connect(self._db_path) as db:
            cur = await db.execute(
                """
                INSERT INTO login_logs (user_id, device_fingerprint, ip_address, success)
                VALUES (?, ?, ?, ?)
                """,
                (user_id, device_fingerprint, ip_address, val),
            )
            await db.commit()
            return int(cur.lastrowid)

    async def create_recovery_request(self, user_id: int) -> int:
        raise NotImplementedError("recovery_requests")

    async def set_master_key_hash(self, key_hash: str) -> None:
        raise NotImplementedError("master_keys")

    async def verify_master_key_hash(self, candidate_hash: str) -> bool:
        raise NotImplementedError("master_keys")

    async def insert_message(
        self,
        sender_id: int,
        message_type: str,
        text: str | None = None,
        file_path: str | None = None,
        file_name: str | None = None,
        file_size: int | None = None,
        duration_sec: int | None = None,
        thumbnail_path: str | None = None,
    ) -> int:
        raise NotImplementedError("insert_message: устаревшая сигнатура, используйте create_message")

    async def list_messages(
        self,
        *,
        limit: int = 50,
        offset: int = 0,
    ) -> list[dict[str, Any]]:
        raise NotImplementedError("list_messages: используйте get_messages(chat_id, ...)")

    async def add_user_avatar(self, user_id: int, file_path: str) -> int:
        """Добавляет строку в user_avatars (если таблица есть), помечает текущей; обновляет users.avatar_path."""
        async with aiosqlite.connect(self._db_path) as db:
            async with db.execute(
                """
                SELECT 1 FROM sqlite_master
                WHERE type = 'table' AND name = 'user_avatars'
                """,
            ) as cur:
                has_table = (await cur.fetchone()) is not None
            if has_table:
                await db.execute(
                    "UPDATE user_avatars SET is_current = 0 WHERE user_id = ?",
                    (user_id,),
                )
                cur = await db.execute(
                    """
                    INSERT INTO user_avatars (user_id, file_path, is_current)
                    VALUES (?, ?, 1)
                    """,
                    (user_id, file_path),
                )
                new_id = int(cur.lastrowid)
            else:
                new_id = 0
            await db.execute(
                "UPDATE users SET avatar_path = ? WHERE id = ?",
                (file_path, user_id),
            )
            await db.commit()
        return new_id

    async def get_user_avatars(self, user_id: int) -> list[dict[str, Any]]:
        async with aiosqlite.connect(self._db_path) as db:
            db.row_factory = aiosqlite.Row
            async with db.execute(
                "SELECT * FROM user_avatars WHERE user_id = ? ORDER BY id DESC",
                (user_id,),
            ) as cur:
                rows = await cur.fetchall()
        return [_row_to_dict(r) for r in rows]

    async def set_current_avatar(self, user_id: int, avatar_id: int) -> None:
        async with aiosqlite.connect(self._db_path) as db:
            await db.execute(
                "UPDATE user_avatars SET is_current = 0 WHERE user_id = ?",
                (user_id,),
            )
            await db.execute(
                """
                UPDATE user_avatars SET is_current = 1
                WHERE id = ? AND user_id = ?
                """,
                (avatar_id, user_id),
            )
            async with db.execute(
                "SELECT file_path FROM user_avatars WHERE id = ? AND user_id = ?",
                (avatar_id, user_id),
            ) as cur:
                row = await cur.fetchone()
            if row and row[0]:
                await db.execute(
                    "UPDATE users SET avatar_path = ? WHERE id = ?",
                    (row[0], user_id),
                )
            await db.commit()

    async def get_user_settings(self, user_id: int) -> dict[str, Any] | None:
        raise NotImplementedError("user_settings")

    async def update_user_settings(self, user_id: int, **kwargs: Any) -> None:
        raise NotImplementedError("user_settings")

    async def log_event(
        self,
        user_id: int,
        event_type: str,
        event_data: str,
        ip: str | None,
        device: str | None,
    ) -> int:
        async with aiosqlite.connect(self._db_path) as db:
            cur = await db.execute(
                """
                INSERT INTO user_analytics (user_id, event_type, event_data, ip_address, device_model)
                VALUES (?, ?, ?, ?, ?)
                """,
                (user_id, event_type, event_data, ip, device),
            )
            await db.commit()
            return int(cur.lastrowid)

    async def create_chat(self, type: str, title: str | None, created_by: int) -> int:
        async with aiosqlite.connect(self._db_path) as db:
            cur = await db.execute(
                """
                INSERT INTO chats (type, title, created_by)
                VALUES (?, ?, ?)
                """,
                (type, title, created_by),
            )
            await db.commit()
            return int(cur.lastrowid)

    async def get_chat(self, chat_id: int) -> dict[str, Any] | None:
        async with aiosqlite.connect(self._db_path) as db:
            db.row_factory = aiosqlite.Row
            async with db.execute("SELECT * FROM chats WHERE id = ?", (chat_id,)) as cur:
                row = await cur.fetchone()
        return _row_to_dict(row) if row else None

    async def get_user_chats(self, user_id: int) -> list[dict[str, Any]]:
        async with aiosqlite.connect(self._db_path) as db:
            db.row_factory = aiosqlite.Row
            async with db.execute(
                """
                SELECT c.*, cm.role AS my_role, cm.can_write AS my_can_write,
                       (SELECT u.id
                        FROM chat_members m2
                        INNER JOIN users u ON u.id = m2.user_id
                        WHERE m2.chat_id = c.id AND c.type = 'direct' AND m2.user_id != ?
                        LIMIT 1) AS direct_peer_id,
                       (SELECT u.login
                        FROM chat_members m2
                        INNER JOIN users u ON u.id = m2.user_id
                        WHERE m2.chat_id = c.id AND c.type = 'direct' AND m2.user_id != ?
                        LIMIT 1) AS direct_peer_login,
                       (SELECT u.username
                        FROM chat_members m2
                        INNER JOIN users u ON u.id = m2.user_id
                        WHERE m2.chat_id = c.id AND c.type = 'direct' AND m2.user_id != ?
                        LIMIT 1) AS direct_peer_username,
                       (SELECT u.display_name
                        FROM chat_members m2
                        INNER JOIN users u ON u.id = m2.user_id
                        WHERE m2.chat_id = c.id AND c.type = 'direct' AND m2.user_id != ?
                        LIMIT 1) AS direct_peer_display_name
                FROM chats c
                INNER JOIN chat_members cm ON cm.chat_id = c.id AND cm.user_id = ?
                WHERE c.is_archived = 0
                ORDER BY c.updated_at DESC
                """,
                (user_id, user_id, user_id, user_id, user_id),
            ) as cur:
                rows = await cur.fetchall()
        return [_row_to_dict(r) for r in rows]

    async def get_direct_chat_peer_user(
        self,
        chat_id: int,
        viewer_user_id: int,
    ) -> dict[str, Any] | None:
        """Для direct: второй участник (не viewer); login и display_name для подписи в списке."""
        async with aiosqlite.connect(self._db_path) as db:
            db.row_factory = aiosqlite.Row
            async with db.execute(
                """
                SELECT u.id, u.login, u.username, u.display_name
                FROM chat_members m
                INNER JOIN users u ON u.id = m.user_id
                INNER JOIN chats c ON c.id = m.chat_id AND c.type = 'direct'
                WHERE m.chat_id = ? AND m.user_id != ?
                LIMIT 1
                """,
                (chat_id, viewer_user_id),
            ) as cur:
                row = await cur.fetchone()
        return _row_to_dict(row) if row else None

    async def update_chat_metadata(
        self,
        chat_id: int,
        *,
        title: str,
        description: str | None = None,
        update_description: bool = False,
    ) -> None:
        """
        Обновляет title; description — только если update_description=True
        (None тогда значит очистить поле).
        """
        title_clean = title.strip()
        async with aiosqlite.connect(self._db_path) as db:
            if update_description:
                await db.execute(
                    """
                    UPDATE chats
                    SET title = ?, description = ?, updated_at = datetime('now')
                    WHERE id = ?
                    """,
                    (title_clean, description, chat_id),
                )
            else:
                await db.execute(
                    """
                    UPDATE chats
                    SET title = ?, updated_at = datetime('now')
                    WHERE id = ?
                    """,
                    (title_clean, chat_id),
                )
            await db.commit()

    async def find_direct_chat_id_between(self, user_id_a: int, user_id_b: int) -> int | None:
        async with aiosqlite.connect(self._db_path) as db:
            db.row_factory = aiosqlite.Row
            async with db.execute(
                """
                SELECT c.id AS chat_id
                FROM chats c
                WHERE c.type = 'direct'
                  AND c.is_archived = 0
                  AND (SELECT COUNT(*) FROM chat_members m WHERE m.chat_id = c.id) = 2
                  AND EXISTS (
                      SELECT 1 FROM chat_members m1
                      WHERE m1.chat_id = c.id AND m1.user_id = ?
                  )
                  AND EXISTS (
                      SELECT 1 FROM chat_members m2
                      WHERE m2.chat_id = c.id AND m2.user_id = ?
                  )
                LIMIT 1
                """,
                (user_id_a, user_id_b),
            ) as cur:
                row = await cur.fetchone()
        if row is None:
            return None
        return int(row["chat_id"])

    async def add_chat_member(
        self,
        chat_id: int,
        user_id: int,
        role: str = "member",
        can_write: int = 1,
    ) -> int:
        async with aiosqlite.connect(self._db_path) as db:
            cur = await db.execute(
                """
                INSERT INTO chat_members (chat_id, user_id, role, can_write)
                VALUES (?, ?, ?, ?)
                """,
                (chat_id, user_id, role, can_write),
            )
            await db.execute(
                """
                UPDATE chats
                SET members_count = members_count + 1,
                    updated_at = datetime('now')
                WHERE id = ?
                """,
                (chat_id,),
            )
        await db.commit()
        return int(cur.lastrowid)

    async def add_chat_member_if_absent(
        self,
        chat_id: int,
        user_id: int,
        role: str = "member",
        can_write: int = 1,
    ) -> bool:
        """True если участник добавлен; False если уже был."""
        async with aiosqlite.connect(self._db_path) as db:
            async with db.execute(
                """
                SELECT 1 FROM chat_members WHERE chat_id = ? AND user_id = ?
                """,
                (chat_id, user_id),
            ) as cur:
                if await cur.fetchone() is not None:
                    return False
            await db.execute(
                """
                INSERT INTO chat_members (chat_id, user_id, role, can_write)
                VALUES (?, ?, ?, ?)
                """,
                (chat_id, user_id, role, can_write),
            )
            await db.execute(
                """
                UPDATE chats
                SET members_count = members_count + 1,
                    updated_at = datetime('now')
                WHERE id = ?
                """,
                (chat_id,),
            )
            await db.commit()
            return True

    async def get_chat_member(self, chat_id: int, user_id: int) -> dict[str, Any] | None:
        async with aiosqlite.connect(self._db_path) as db:
            db.row_factory = aiosqlite.Row
            async with db.execute(
                """
                SELECT * FROM chat_members
                WHERE chat_id = ? AND user_id = ?
                """,
                (chat_id, user_id),
            ) as cur:
                row = await cur.fetchone()
        return _row_to_dict(row) if row else None

    async def list_chat_member_user_ids(self, chat_id: int) -> list[int]:
        """Все user_id в чате (для рассылки push остальным участникам)."""
        async with aiosqlite.connect(self._db_path) as db:
            async with db.execute(
                "SELECT user_id FROM chat_members WHERE chat_id = ?",
                (chat_id,),
            ) as cur:
                rows = await cur.fetchall()
        return [int(r[0]) for r in rows]

    async def save_user_push_token(self, user_id: int, token: str) -> None:
        """Сохраняет FCM registration token (см. app.database.db_push)."""
        from app.database import db_push

        await db_push.save_push_token(self._db_path, user_id, token)

    async def get_user_push_tokens(self, user_id: int) -> list[str]:
        """Список FCM-токенов пользователя."""
        from app.database import db_push

        return await db_push.get_user_push_tokens(self._db_path, user_id)

    async def remove_push_token(self, token: str) -> None:
        """Удаляет токен устройства (невалидный ответ FCM)."""
        from app.database import db_push

        await db_push.remove_push_token(self._db_path, token)

    async def remove_chat_member(self, chat_id: int, user_id: int) -> None:
        raise NotImplementedError("chat_members: удаление участника")

    async def create_message(
        self,
        chat_id: int,
        sender_id: int,
        type: str,
        text: str | None = None,
        **kwargs: Any,
    ) -> int:
        reply_to_id = kwargs.get("reply_to_id")
        async with aiosqlite.connect(self._db_path) as db:
            cur = await db.execute(
                """
                INSERT INTO messages (chat_id, sender_id, type, text, reply_to_id)
                VALUES (?, ?, ?, ?, ?)
                """,
                (chat_id, sender_id, type, text, reply_to_id),
            )
            await db.execute(
                "UPDATE chats SET updated_at = datetime('now') WHERE id = ?",
                (chat_id,),
            )
            await db.commit()
            return int(cur.lastrowid)

    async def get_messages(
        self,
        chat_id: int,
        limit: int = 50,
        before_id: int | None = None,
    ) -> list[dict[str, Any]]:
        if before_id is not None:
            sql = """
                SELECT * FROM messages
                WHERE chat_id = ? AND is_deleted = 0 AND id < ?
                ORDER BY id DESC
                LIMIT ?
            """
            params: tuple[Any, ...] = (chat_id, before_id, limit)
        else:
            sql = """
                SELECT * FROM messages
                WHERE chat_id = ? AND is_deleted = 0
                ORDER BY id DESC
                LIMIT ?
            """
            params = (chat_id, limit)

        async with aiosqlite.connect(self._db_path) as db:
            db.row_factory = aiosqlite.Row
            async with db.execute(sql, params) as cur:
                rows = await cur.fetchall()
        out = [_row_to_dict(r) for r in rows]
        out.reverse()
        return out

    async def get_message_by_id(self, message_id: int) -> dict[str, Any] | None:
        async with aiosqlite.connect(self._db_path) as db:
            db.row_factory = aiosqlite.Row
            async with db.execute(
                "SELECT * FROM messages WHERE id = ?",
                (message_id,),
            ) as cur:
                row = await cur.fetchone()
        return _row_to_dict(row) if row else None

    async def get_last_message_for_chat(self, chat_id: int) -> dict[str, Any] | None:
        """Последнее неудалённое сообщение в чате (для превью в списке)."""
        async with aiosqlite.connect(self._db_path) as db:
            db.row_factory = aiosqlite.Row
            async with db.execute(
                """
                SELECT id, text, created_at
                FROM messages
                WHERE chat_id = ? AND is_deleted = 0
                ORDER BY id DESC
                LIMIT 1
                """,
                (chat_id,),
            ) as cur:
                row = await cur.fetchone()
        return _row_to_dict(row) if row else None

    async def get_unread_count(self, chat_id: int, user_id: int) -> int:
        """
        Число входящих непрочитанных: сообщения не от этого пользователя,
        без записи в message_reads.
        """
        async with aiosqlite.connect(self._db_path) as db:
            async with db.execute(
                """
                SELECT COUNT(*) AS c
                FROM messages m
                WHERE m.chat_id = ?
                  AND m.is_deleted = 0
                  AND COALESCE(m.sender_id, -1) != ?
                  AND NOT EXISTS (
                      SELECT 1 FROM message_reads r
                      WHERE r.message_id = m.id AND r.user_id = ?
                  )
                """,
                (chat_id, user_id, user_id),
            ) as cur:
                row = await cur.fetchone()
        return int(row[0]) if row and row[0] is not None else 0

    async def mark_read(self, message_id: int, user_id: int) -> None:
        """Отметить одно сообщение прочитанным (идемпотентно)."""
        async with aiosqlite.connect(self._db_path) as db:
            await db.execute(
                """
                INSERT OR IGNORE INTO message_reads (message_id, user_id)
                VALUES (?, ?)
                """,
                (message_id, user_id),
            )
            await db.commit()

    async def mark_chat_read_up_to(self, chat_id: int, user_id: int, message_id: int) -> None:
        """Прочитать все сообщения чата с id <= message_id (пакетно в message_reads)."""
        async with aiosqlite.connect(self._db_path) as db:
            await db.execute(
                """
                INSERT OR IGNORE INTO message_reads (message_id, user_id)
                SELECT m.id, ?
                FROM messages m
                WHERE m.chat_id = ?
                  AND m.id <= ?
                  AND m.is_deleted = 0
                """,
                (user_id, chat_id, message_id),
            )
            await db.commit()

    async def update_last_read_message(self, user_id: int, message_id: int) -> None:
        """Обновить user_settings.last_read_message_id (глобальный указатель «до какого id дочитал»)."""
        await self.create_user_settings(user_id)
        async with aiosqlite.connect(self._db_path) as db:
            await db.execute(
                """
                UPDATE user_settings
                SET last_read_message_id = ?
                WHERE user_id = ?
                """,
                (message_id, user_id),
            )
            await db.commit()

    async def add_reaction(self, message_id: int, user_id: int, emoji: str) -> int:
        raise NotImplementedError("message_reactions")

    async def update_profile(
        self,
        user_id: int,
        display_name: str | None,
        about: str | None,
        email: str | None,
        phone: str | None,
    ) -> None:
        raise NotImplementedError("users: профиль")

    async def update_online_status(self, user_id: int, is_online: bool) -> None:
        raise NotImplementedError("users: онлайн")

    async def submit_report(
        self,
        user_id: int | None,
        title: str,
        description: str | None,
        logs_path: str | None,
        app_version: str | None,
        device_model: str | None,
        device_os: str | None,
    ) -> int:
        raise NotImplementedError("app_reports")

    async def get_reports(self, status: str | None = None) -> list[dict[str, Any]]:
        raise NotImplementedError("app_reports")

    async def update_report(
        self,
        report_id: int,
        status: str,
        admin_note: str | None,
    ) -> None:
        raise NotImplementedError("app_reports")

    async def add_app_version(
        self,
        version_code: int,
        version_name: str,
        apk_path: str,
        changelog: str | None,
        is_forced: bool,
        min_version_code: int,
    ) -> int:
        raise NotImplementedError("app_versions")

    async def get_latest_version(self) -> dict[str, Any] | None:
        raise NotImplementedError("app_versions")

    async def get_version(self, version_code: int) -> dict[str, Any] | None:
        raise NotImplementedError("app_versions")

    async def start_network_session(
        self,
        user_id: int,
        connection_type: str,
        carrier_name: str | None,
        carrier_country: str | None,
        ip: str | None,
        city: str | None,
    ) -> int:
        raise NotImplementedError("network_sessions")

    async def end_network_session(
        self,
        session_id: int,
        bytes_sent: int,
        bytes_received: int,
        messages_sent: int,
    ) -> None:
        raise NotImplementedError("network_sessions")

    async def get_network_stats(self, user_id: int) -> dict[str, Any]:
        raise NotImplementedError("network_sessions")

    async def start_activity(self, user_id: int, screen: str) -> int:
        raise NotImplementedError("user_activity_periods")

    async def end_activity(self, activity_id: int, duration_sec: int) -> None:
        raise NotImplementedError("user_activity_periods")

    async def get_activity_stats(
        self,
        user_id: int,
        date_from: str,
        date_until: str,
    ) -> dict[str, Any]:
        raise NotImplementedError("user_activity_periods")

    async def create_notification_schedule(self, user_id: int, type: str, **kwargs: Any) -> int:
        raise NotImplementedError("notification_schedules")

    async def get_notification_schedules(self, user_id: int) -> list[dict[str, Any]]:
        raise NotImplementedError("notification_schedules")

    async def toggle_notification_schedule(self, schedule_id: int, is_active: bool) -> None:
        raise NotImplementedError("notification_schedules")

    async def delete_notification_schedule(self, schedule_id: int) -> None:
        raise NotImplementedError("notification_schedules")

    async def get_yearly_stats(self, user_id: int, year: int) -> dict[str, Any]:
        raise NotImplementedError("get_yearly_stats")
