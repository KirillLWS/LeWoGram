/// Профиль текущего пользователя (ответ [GET /auth/me]).
class UserMe {
  UserMe({
    required this.id,
    required this.login,
    this.displayName,
  });

  final int id;
  final String login;
  final String? displayName;

  factory UserMe.fromJson(Map<String, dynamic> json) {
    return UserMe(
      id: (json['id'] as num).toInt(),
      login: json['login'] as String,
      displayName: json['display_name'] as String?,
    );
  }
}

/// Одна строка списка чатов (поля из API).
class ChatItem {
  ChatItem({
    required this.id,
    required this.type,
    this.title,
    this.displayTitle,
    this.displaySubtitle,
    this.avatarPath,
    this.peerLogin,
    this.peerDisplayName,
    this.peerUserId,
    this.lastMessageText,
    this.lastMessageCreatedAt,
    required this.unreadCount,
    this.myRole,
  });

  final int id;
  final String type;
  final String? title;

  /// Явное отображаемое имя с сервера ([display_title] в JSON), если есть.
  final String? displayTitle;

  /// Подзаголовок с сервера ([display_subtitle]), например для direct-чата.
  final String? displaySubtitle;

  /// Путь или URL аватара ([avatar_path] в JSON), если сервер прислал.
  final String? avatarPath;
  final String? peerLogin;
  final String? peerDisplayName;

  /// Собеседник в direct-чате ([peer_user_id] в JSON); для групп — null.
  final int? peerUserId;

  final String? lastMessageText;
  final String? lastMessageCreatedAt;
  final int unreadCount;
  final String? myRole;

  factory ChatItem.fromJson(Map<String, dynamic> json) {
    final rawDisplayTitle = json['display_title'];
    final displayTitle = rawDisplayTitle is String
        ? rawDisplayTitle
        : rawDisplayTitle?.toString();

    final rawAvatar = json['avatar_url'] ?? json['avatar_path'];
    final avatarPath = rawAvatar is String
        ? rawAvatar
        : rawAvatar?.toString();

    final rawPeerId = json['peer_user_id'];
    final peerUserId = rawPeerId is num ? rawPeerId.toInt() : null;

    return ChatItem(
      id: (json['id'] as num).toInt(),
      type: json['type'] as String,
      title: json['title'] as String?,
      displayTitle: displayTitle,
      displaySubtitle: json['display_subtitle'] as String?,
      avatarPath: avatarPath,
      peerLogin: json['peer_login'] as String?,
      peerDisplayName: json['peer_display_name'] as String?,
      peerUserId: peerUserId,
      lastMessageText: json['last_message_text'] as String?,
      lastMessageCreatedAt: json['last_message_created_at'] as String?,
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      myRole: json['my_role'] as String?,
    );
  }

  /// Заголовок для списка и AppBar: приоритет display_title → title → peer → запасной.
  String get resolvedTitle {
    final dt = displayTitle?.trim();
    if (dt != null && dt.isNotEmpty) return dt;
    final t = title?.trim();
    if (t != null && t.isNotEmpty) return t;
    final pd = peerDisplayName?.trim();
    if (pd != null && pd.isNotEmpty) return pd;
    final pl = peerLogin?.trim();
    if (pl != null && pl.isNotEmpty) return pl;
    return 'Чат #$id ($type)';
  }
}

/// Сообщение в истории переписки.
class MessageItem {
  MessageItem({
    required this.id,
    required this.chatId,
    this.senderId,
    required this.type,
    this.text,
    required this.createdAt,
  });

  final int id;
  final int chatId;
  final int? senderId;
  final String type;
  final String? text;
  final String createdAt;

  factory MessageItem.fromJson(Map<String, dynamic> json) {
    return MessageItem(
      id: (json['id'] as num).toInt(),
      chatId: (json['chat_id'] as num).toInt(),
      senderId: (json['sender_id'] as num?)?.toInt(),
      type: json['type'] as String,
      text: json['text'] as String?,
      createdAt: json['created_at'] as String,
    );
  }
}
