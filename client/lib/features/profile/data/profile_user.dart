/// Текущий пользователь из [GET /auth/me] и поля для экрана профиля.
class ProfileUser {
  const ProfileUser({
    required this.id,
    required this.login,
    this.displayName,
    this.about,
    this.avatarUrl,
    this.avatarExists,
    String? username,
  }) : _usernameField = username;

  final int id;
  final String login;
  final String? displayName;
  final String? about;

  /// URL или относительный путь к аватару ([avatar_path] / [avatar_url] из API).
  final String? avatarUrl;

  /// Из API ([avatar_exists]): `false` — файла нет, не грузить по старому пути.
  final bool? avatarExists;

  final String? _usernameField;

  /// Публичный ник; в API пока совпадает с [login], при появлении поля `username` в JSON подхватится.
  String get username {
    final u = _usernameField?.trim();
    if (u != null && u.isNotEmpty) return u;
    return login;
  }

  /// Имя для аватара и заголовка.
  String get primaryLabel {
    final n = displayName?.trim();
    if (n != null && n.isNotEmpty) return n;
    return login;
  }

  factory ProfileUser.fromJson(Map<String, dynamic> json) {
    final aboutRaw = json['about'];
    final unameRaw = json['username'];
    final uname = unameRaw is String ? unameRaw.trim() : null;
    final existsRaw = json['avatar_exists'];
    bool? avatarExists;
    if (existsRaw is bool) {
      avatarExists = existsRaw;
    } else if (existsRaw is num) {
      avatarExists = existsRaw != 0;
    }

    return ProfileUser(
      id: (json['id'] as num?)?.toInt() ?? 0,
      login: json['login'] as String,
      displayName: json['display_name'] as String?,
      about: aboutRaw is String ? aboutRaw : null,
      avatarUrl: _readOptionalString(json['avatar_url']) ??
          _readOptionalString(json['avatar_path']) ??
          _readOptionalString(json['avatar']),
      avatarExists: avatarExists,
      username: uname != null && uname.isNotEmpty ? uname : null,
    );
  }

  static String? _readOptionalString(Object? v) {
    if (v is String) {
      final t = v.trim();
      return t.isEmpty ? null : t;
    }
    return null;
  }
}
