import 'user_search_result.dart';

/// Публичный профиль другого пользователя (ожидаемая форма JSON с API).
class UserPublicProfile {
  const UserPublicProfile({
    required this.id,
    required this.username,
    this.displayName,
    this.about,
  });

  final int id;
  final String username;
  final String? displayName;
  final String? about;

  factory UserPublicProfile.fromJson(Map<String, dynamic> json) {
    return UserPublicProfile(
      id: (json['id'] as num).toInt(),
      username: json['username'] as String? ?? '',
      displayName: json['display_name'] as String?,
      about: json['about'] as String?,
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
      };
}
