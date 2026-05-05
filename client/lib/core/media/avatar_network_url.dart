import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import 'package:lewogram_client/core/config/app_config.dart';

/// Полный `http`/`https` URL для загрузки аватара, или `null` для локального файла / отсутствия.
///
/// Относительные пути из API (`avatars/users/...`, `media/avatars/...`, `/media/avatars/...`)
/// собираются с [AppConfig.baseUrl] и префиксом монтирования статики `/media/`.
String? resolveAvatarImageUrl(String? path) {
  if (path == null) return null;
  final s = path.trim();
  if (s.isEmpty) return null;

  final uri = Uri.tryParse(s);
  if (uri != null &&
      uri.hasScheme &&
      (uri.scheme == 'http' || uri.scheme == 'https')) {
    return uri.toString();
  }
  if (s.startsWith('//')) {
    final u = Uri.tryParse('https:$s');
    if (u != null && u.hasScheme) return u.toString();
  }

  final base = AppConfig.baseUrl.replaceAll(RegExp(r'/+$'), '');

  // Абсолютный путь URL вида `/media/...` из API.
  if (s.startsWith('/') && !s.startsWith('//')) {
    if (s.startsWith('/media/')) {
      return Uri.parse('$base$s').toString();
    }
    return null;
  }
  if (s.length >= 2 && s[1] == ':') {
    return null;
  }

  var sub = s.startsWith('/') ? s.substring(1) : s;
  if (!sub.startsWith('media/')) {
    sub = 'media/$sub';
  }
  return Uri.parse('$base/$sub').toString();
}

/// Совместимость со старым именем; предпочтительно [resolveAvatarImageUrl].
String? resolveChatAvatarNetworkUrl(String? path) => resolveAvatarImageUrl(path);

void logAvatarLoadFailure(String url, Object error) {
  if (kDebugMode) {
    debugPrint('Avatar load failed: $url — $error');
  }
}
