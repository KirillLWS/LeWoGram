import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:lewogram_client/core/network/api_client.dart';

/// Инициализация FCM и регистрация токена на backend ([POST /push/token]).
///
/// На платформах без Firebase (или без `google-services.json`) вызов может
/// завершиться ошибкой — она перехватывается, приложение продолжает работу.
class PushService {
  PushService._();

  /// Запрос прав, получение FCM token, отправка на сервер, подписка на foreground-сообщения.
  static Future<void> initAndGetToken(ApiClient apiClient) async {
    try {
      final messaging = FirebaseMessaging.instance;

      // Android 13+ / iOS — запрос показа уведомлений.
      await messaging.requestPermission();

      final token = await messaging.getToken();
      if (token != null && token.trim().isNotEmpty) {
        await apiClient.sendPushToken(token.trim());
      }

      // Пока только лог; позже можно связать с локальными уведомлениями / навигацией.
      FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
        debugPrint(
          '[FCM foreground] title=${msg.notification?.title} '
          'body=${msg.notification?.body}',
        );
      });
    } catch (e, st) {
      debugPrint('PushService.initAndGetToken: $e\n$st');
    }
  }
}
