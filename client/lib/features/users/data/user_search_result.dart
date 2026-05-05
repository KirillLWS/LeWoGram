/// Один элемент ответа поиска пользователей (ожидаемая форма JSON с API).
class UserSearchResult {
  const UserSearchResult({
    required this.id,
    required this.username,
    this.displayName,
    this.about,
  });

  final int id;
  final String username;
  final String? displayName;
  final String? about;

  factory UserSearchResult.fromJson(Map<String, dynamic> json) {
    return UserSearchResult(
      id: (json['id'] as num).toInt(),
      username: json['username'] as String? ?? '',
      displayName: json['display_name'] as String?,
      about: json['about'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'display_name': displayName,
        'about': about,
      };
}
