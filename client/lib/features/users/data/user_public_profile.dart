import 'user_search_result.dart';

/// Публичный профиль другого пользователя (ожидаемая форма JSON с API).
class UserPublicProfile {
  const UserPublicProfile({
    required this.id,
    required this.username,
    this.displayName,
    this.about,
    this.avatarPath,
    this.relationToMe,
    this.friendRequestId,
  });

  final int id;
  final String username;
  final String? displayName;
  final String? about;
  final String? avatarPath;

  /// Из [GET /users/{id}] при наличии (опционально).
  final String? relationToMe;
  final int? friendRequestId;

  factory UserPublicProfile.fromJson(Map<String, dynamic> json) {
    int? reqId;
    final fr = json['friend_request_id'];
    if (fr is num) reqId = fr.toInt();

    final rawPath = json['avatar_url'] as String? ?? json['avatar_path'] as String?;
    final trimmedPath = rawPath?.trim();
    final avatarPath =
        trimmedPath != null && trimmedPath.isNotEmpty ? trimmedPath : null;
    return UserPublicProfile(
      id: (json['id'] as num).toInt(),
      username: json['username'] as String? ?? '',
      displayName: json['display_name'] as String?,
      about: json['about'] as String?,
      avatarPath: avatarPath,
      relationToMe: json['relation_to_me'] as String?,
      friendRequestId: reqId,
    );
  }

  /// Собрать экран профиля из строки поиска, если отдельного запроса профиля нет.
  factory UserPublicProfile.fromSearchResult(UserSearchResult r) {
    return UserPublicProfile(
      id: r.id,
      username: r.username,
      displayName: r.displayName,
      about: r.about,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'display_name': displayName,
        'about': about,
        if (avatarPath != null) 'avatar_path': avatarPath,
        if (relationToMe != null) 'relation_to_me': relationToMe,
        if (friendRequestId != null) 'friend_request_id': friendRequestId,
      };
}
