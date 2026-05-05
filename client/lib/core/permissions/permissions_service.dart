import 'dart:io' show Platform;

import 'package:permission_handler/permission_handler.dart' as ph;

/// Разрешения приложения (маппинг в [ph.Permission]).
enum AppPermission {
  camera,
  microphone,
  photos,
  location,
  notifications,
}

/// Запрос и проверка разрешений через [permission_handler].
class PermissionsService {
  ph.Permission _toNative(AppPermission p) {
    switch (p) {
      case AppPermission.camera:
        return ph.Permission.camera;
      case AppPermission.microphone:
        return ph.Permission.microphone;
      case AppPermission.photos:
        if (Platform.isAndroid) {
          // Android 13+ (API 33): READ_MEDIA_IMAGES через Permission.photos;
          // на более старых версиях пакет маппит на хранилище.
          return ph.Permission.photos;
        }
        return ph.Permission.photos;
      case AppPermission.location:
        return ph.Permission.locationWhenInUse;
      case AppPermission.notifications:
        return ph.Permission.notification;
    }
  }

  /// Запросить разрешение; `true`, если выдано или ограниченно (iOS photos).
  Future<bool> request(AppPermission p) async {
    final perm = _toNative(p);
    final status = await perm.request();
    return status.isGranted || status.isLimited;
  }

  /// Текущее состояние: выдано или ограниченно.
  Future<bool> status(AppPermission p) async {
    final perm = _toNative(p);
    final s = await perm.status;
    return s.isGranted || s.isLimited;
  }

  Future<void> openAppSettings() => ph.openAppSettings();
}
