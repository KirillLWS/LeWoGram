import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:lewogram_client/core/config/app_config.dart';
import 'package:lewogram_client/core/storage/token_storage.dart';

/// Ошибка API или сети (не 401 «сессия»).
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// 401 с отправленным Bearer: токен очищен; UI может отправить на экран входа.
class UnauthorizedException implements Exception {
  UnauthorizedException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

typedef UnauthorizedCallback = void Function();

/// HTTP-клиент: база из [AppConfig.baseUrl], JWT из [TokenStorage].
class ApiClient {
  ApiClient({
    required TokenStorage tokenStorage,
    this.onUnauthorized,
    http.Client? httpClient,
  })  : _baseUrl = AppConfig.baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _tokenStorage = tokenStorage,
        _http = httpClient ?? http.Client();

  /// После сброса токена при 401 с Bearer (например навигация на `/login`).
  final UnauthorizedCallback? onUnauthorized;

  final String _baseUrl;
  final TokenStorage _tokenStorage;
  final http.Client _http;

  Uri _uri(String path, [Map<String, String>? query]) {
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$_baseUrl$p').replace(queryParameters: query);
  }

  String _extractErrorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'];
        if (detail is String) return detail;
        if (detail is List && detail.isNotEmpty) {
          final first = detail.first;
          if (first is Map && first['msg'] != null) {
            return first['msg'].toString();
          }
        }
      }
    } catch (_) {}
    return 'Ошибка сервера';
  }

  Future<Map<String, String>> _jsonHeaders({bool includeBearerIfPresent = false}) async {
    final h = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
    };
    if (includeBearerIfPresent) {
      final token = await _tokenStorage.readToken();
      if (token != null && token.isNotEmpty) {
        h['Authorization'] = 'Bearer $token';
      }
    }
    return h;
  }

  /// `true`, если в запрос ушёл заголовок Authorization (тогда 401 — сброс сессии).
  Future<void> _on401IfHadBearer(bool hadBearer, http.Response resp) async {
    if (resp.statusCode != 401) return;
    if (hadBearer) {
      await _tokenStorage.clearToken();
      onUnauthorized?.call();
      throw UnauthorizedException(
        _extractErrorMessage(resp.body),
        statusCode: 401,
      );
    }
    throw ApiException(
      _extractErrorMessage(resp.body),
      statusCode: 401,
    );
  }

  /// Вход; при успехе сохраняет `access_token` в [TokenStorage].
  Future<Map<String, dynamic>> login({
    required String login,
    required String password,
    required String deviceFingerprint,
    String? deviceModel,
    String? deviceOs,
  }) async {
    try {
      final uri = _uri('/auth/login');
      final bodyMap = <String, dynamic>{
        'login': login,
        'password': password,
        'device_fingerprint': deviceFingerprint,
        if (deviceModel != null && deviceModel.isNotEmpty)
          'device_model': deviceModel,
        if (deviceOs != null && deviceOs.isNotEmpty) 'device_os': deviceOs,
      };
      final headers = await _jsonHeaders(includeBearerIfPresent: false);
      final resp = await _http.post(
        uri,
        headers: headers,
        body: jsonEncode(bodyMap),
      );
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        throw ApiException(
          _extractErrorMessage(resp.body),
          statusCode: resp.statusCode,
        );
      }
      if (resp.statusCode != 200 && resp.statusCode != 201) {
        throw ApiException(
          _extractErrorMessage(resp.body),
          statusCode: resp.statusCode,
        );
      }
      final data =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final access = data['access_token'] as String?;
      if (access != null && access.isNotEmpty) {
        await _tokenStorage.saveToken(access);
      }
      return data;
    } on SocketException catch (e) {
      throw ApiException('Нет сети: ${e.message}');
    } on http.ClientException catch (e) {
      throw ApiException('Сеть: ${e.message}');
    } on FormatException catch (e) {
      throw ApiException('Неверный ответ сервера: ${e.message}');
    }
  }

  /// Регистрация по инвайту ([POST /auth/register]); при успехе сохраняет JWT.
  Future<Map<String, dynamic>> register({
    required String inviteToken,
    required String login,
    required String password,
    required String deviceFingerprint,
    String? displayName,
  }) async {
    try {
      final uri = _uri('/auth/register');
      final bodyMap = <String, dynamic>{
        'invite_token': inviteToken,
        'login': login,
        'password': password,
        'device_fingerprint': deviceFingerprint,
        if (displayName != null && displayName.trim().isNotEmpty)
          'display_name': displayName.trim(),
      };
      final headers = await _jsonHeaders(includeBearerIfPresent: false);
      final resp = await _http.post(
        uri,
        headers: headers,
        body: jsonEncode(bodyMap),
      );
      if (resp.statusCode != 200 && resp.statusCode != 201) {
        throw ApiException(
          _extractErrorMessage(resp.body),
          statusCode: resp.statusCode,
        );
      }
      final data =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final access = data['access_token'] as String?;
      if (access != null && access.isNotEmpty) {
        await _tokenStorage.saveToken(access);
      }
      return data;
    } on SocketException catch (e) {
      throw ApiException('Нет сети: ${e.message}');
    } on http.ClientException catch (e) {
      throw ApiException('Сеть: ${e.message}');
    } on FormatException catch (e) {
      throw ApiException('Неверный ответ сервера: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getMe() async {
    final uri = _uri('/auth/me');
    final headers = await _jsonHeaders(includeBearerIfPresent: true);
    final hadBearer = headers.containsKey('Authorization');
    try {
      final resp = await _http.get(uri, headers: headers);
      if (resp.statusCode == 401) {
        await _on401IfHadBearer(hadBearer, resp);
      }
      if (resp.statusCode != 200) {
        throw ApiException(
          _extractErrorMessage(resp.body),
          statusCode: resp.statusCode,
        );
      }
      return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    } on SocketException catch (e) {
      throw ApiException('Нет сети: ${e.message}');
    } on http.ClientException catch (e) {
      throw ApiException('Сеть: ${e.message}');
    } on FormatException catch (e) {
      throw ApiException('Неверный JSON /auth/me: ${e.message}');
    }
  }

  /// Создать личный чат ([POST /messages/chats/direct]).
  Future<Map<String, dynamic>> createDirectChat(int otherUserId) async {
    final uri = _uri('/messages/chats/direct');
    final headers = await _jsonHeaders(includeBearerIfPresent: true);
    final hadBearer = headers.containsKey('Authorization');
    final body = jsonEncode({'other_user_id': otherUserId});
    try {
      final resp = await _http.post(uri, headers: headers, body: body);
      if (resp.statusCode == 401) {
        await _on401IfHadBearer(hadBearer, resp);
      }
      if (resp.statusCode != 200 && resp.statusCode != 201) {
        throw ApiException(
          _extractErrorMessage(resp.body),
          statusCode: resp.statusCode,
        );
      }
      return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    } on SocketException catch (e) {
      throw ApiException('Нет сети: ${e.message}');
    } on http.ClientException catch (e) {
      throw ApiException('Сеть: ${e.message}');
    } on FormatException catch (e) {
      throw ApiException('Неверный JSON чата: ${e.message}');
    }
  }

  /// Создать групповой чат ([POST /messages/chats/group]).
  Future<Map<String, dynamic>> createGroupChat(
    String title, {
    List<int> memberIds = const [],
  }) async {
    final uri = _uri('/messages/chats/group');
    final headers = await _jsonHeaders(includeBearerIfPresent: true);
    final hadBearer = headers.containsKey('Authorization');
    final body = jsonEncode({
      'title': title.trim(),
      'member_ids': memberIds,
    });
    try {
      final resp = await _http.post(uri, headers: headers, body: body);
      if (resp.statusCode == 401) {
        await _on401IfHadBearer(hadBearer, resp);
      }
      if (resp.statusCode != 200 && resp.statusCode != 201) {
        throw ApiException(
          _extractErrorMessage(resp.body),
          statusCode: resp.statusCode,
        );
      }
      return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    } on SocketException catch (e) {
      throw ApiException('Нет сети: ${e.message}');
    } on http.ClientException catch (e) {
      throw ApiException('Сеть: ${e.message}');
    } on FormatException catch (e) {
      throw ApiException('Неверный JSON группы: ${e.message}');
    }
  }

  /// Одноразовый claim владельца ([POST /owner/claim]).
  Future<Map<String, dynamic>> claimOwner(String token) async {
    final uri = _uri('/owner/claim');
    final headers = await _jsonHeaders(includeBearerIfPresent: true);
    final hadBearer = headers.containsKey('Authorization');
    final body = jsonEncode({'token': token.trim()});
    try {
      final resp = await _http.post(uri, headers: headers, body: body);
      if (resp.statusCode == 401) {
        await _on401IfHadBearer(hadBearer, resp);
      }
      if (resp.statusCode != 200 && resp.statusCode != 201) {
        throw ApiException(
          _extractErrorMessage(resp.body),
          statusCode: resp.statusCode,
        );
      }
      return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    } on SocketException catch (e) {
      throw ApiException('Нет сети: ${e.message}');
    } on http.ClientException catch (e) {
      throw ApiException('Сеть: ${e.message}');
    } on FormatException catch (e) {
      throw ApiException('Неверный JSON claim: ${e.message}');
    }
  }

  Future<List<dynamic>> getChats() async {
    final uri = _uri('/messages/chats');
    final headers = await _jsonHeaders(includeBearerIfPresent: true);
    final hadBearer = headers.containsKey('Authorization');
    try {
      final resp = await _http.get(uri, headers: headers);
      if (resp.statusCode == 401) {
        await _on401IfHadBearer(hadBearer, resp);
      }
      if (resp.statusCode != 200) {
        throw ApiException(
          _extractErrorMessage(resp.body),
          statusCode: resp.statusCode,
        );
      }
      return jsonDecode(utf8.decode(resp.bodyBytes)) as List<dynamic>;
    } on SocketException catch (e) {
      throw ApiException('Нет сети: ${e.message}');
    } on http.ClientException catch (e) {
      throw ApiException('Сеть: ${e.message}');
    } on FormatException catch (e) {
      throw ApiException('Неверный JSON чатов: ${e.message}');
    }
  }

  Future<List<dynamic>> getMessages(
    int chatId, {
    int limit = 50,
    int? beforeId,
  }) async {
    final query = <String, String>{
      'limit': '$limit',
      if (beforeId != null) 'before_id': '$beforeId',
    };
    final uri = _uri('/messages/$chatId', query);
    final headers = await _jsonHeaders(includeBearerIfPresent: true);
    final hadBearer = headers.containsKey('Authorization');
    try {
      final resp = await _http.get(uri, headers: headers);
      if (resp.statusCode == 401) {
        await _on401IfHadBearer(hadBearer, resp);
      }
      if (resp.statusCode != 200) {
        throw ApiException(
          _extractErrorMessage(resp.body),
          statusCode: resp.statusCode,
        );
      }
      return jsonDecode(utf8.decode(resp.bodyBytes)) as List<dynamic>;
    } on SocketException catch (e) {
      throw ApiException('Нет сети: ${e.message}');
    } on http.ClientException catch (e) {
      throw ApiException('Сеть: ${e.message}');
    } on FormatException catch (e) {
      throw ApiException('Неверный JSON сообщений: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> sendText(int chatId, String text) async {
    final uri = _uri('/messages/send-text');
    final headers = await _jsonHeaders(includeBearerIfPresent: true);
    final hadBearer = headers.containsKey('Authorization');
    final body = jsonEncode({'chat_id': chatId, 'text': text});
    try {
      final resp = await _http.post(uri, headers: headers, body: body);
      if (resp.statusCode == 401) {
        await _on401IfHadBearer(hadBearer, resp);
      }
      if (resp.statusCode != 200 && resp.statusCode != 201) {
        throw ApiException(
          _extractErrorMessage(resp.body),
          statusCode: resp.statusCode,
        );
      }
      return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    } on SocketException catch (e) {
      throw ApiException('Нет сети: ${e.message}');
    } on http.ClientException catch (e) {
      throw ApiException('Сеть: ${e.message}');
    } on FormatException catch (e) {
      throw ApiException('Неверный JSON отправки: ${e.message}');
    }
  }

  /// Отметить сообщения прочитанными до [messageId] включительно ([POST /messages/mark-read]).
  Future<void> markRead(int chatId, int messageId) async {
    final uri = _uri('/messages/mark-read');
    final headers = await _jsonHeaders(includeBearerIfPresent: true);
    final hadBearer = headers.containsKey('Authorization');
    final body = jsonEncode({
      'chat_id': chatId,
      'message_id': messageId,
    });
    try {
      final resp = await _http.post(uri, headers: headers, body: body);
      if (resp.statusCode == 401) {
        await _on401IfHadBearer(hadBearer, resp);
      }
      if (resp.statusCode != 200 && resp.statusCode != 201) {
        throw ApiException(
          _extractErrorMessage(resp.body),
          statusCode: resp.statusCode,
        );
      }
    } on SocketException catch (e) {
      throw ApiException('Нет сети: ${e.message}');
    } on http.ClientException catch (e) {
      throw ApiException('Сеть: ${e.message}');
    } on FormatException catch (e) {
      throw ApiException('Неверный JSON mark-read: ${e.message}');
    }
  }

  /// Переименовать чат ([PATCH /messages/chats/{chat_id}]).
  Future<void> renameChat(
    int chatId,
    String title, {
    String? description,
  }) async {
    final uri = _uri('/messages/chats/$chatId');
    final headers = await _jsonHeaders(includeBearerIfPresent: true);
    final hadBearer = headers.containsKey('Authorization');
    final bodyMap = <String, dynamic>{
      'title': title,
      if (description != null) 'description': description,
    };
    try {
      final resp = await _http.patch(
        uri,
        headers: headers,
        body: jsonEncode(bodyMap),
      );
      if (resp.statusCode == 401) {
        await _on401IfHadBearer(hadBearer, resp);
      }
      if (resp.statusCode != 200 && resp.statusCode != 204) {
        throw ApiException(
          _extractErrorMessage(resp.body),
          statusCode: resp.statusCode,
        );
      }
    } on SocketException catch (e) {
      throw ApiException('Нет сети: ${e.message}');
    } on http.ClientException catch (e) {
      throw ApiException('Сеть: ${e.message}');
    } on FormatException catch (e) {
      throw ApiException('Неверный JSON переименования: ${e.message}');
    }
  }

  /// Создать инвайт (только owner / chief_admin на сервере).
  Future<Map<String, dynamic>> createAdminInvite({
    int expiresHours = 48,
    String? note,
  }) async {
    final uri = _uri('/admin/invites');
    final headers = await _jsonHeaders(includeBearerIfPresent: true);
    final hadBearer = headers.containsKey('Authorization');
    final body = jsonEncode({
      'expires_hours': expiresHours,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
    try {
      final resp = await _http.post(uri, headers: headers, body: body);
      if (resp.statusCode == 401) {
        await _on401IfHadBearer(hadBearer, resp);
      }
      if (resp.statusCode != 200 && resp.statusCode != 201) {
        throw ApiException(
          _extractErrorMessage(resp.body),
          statusCode: resp.statusCode,
        );
      }
      return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    } on SocketException catch (e) {
      throw ApiException('Нет сети: ${e.message}');
    } on http.ClientException catch (e) {
      throw ApiException('Сеть: ${e.message}');
    } on FormatException catch (e) {
      throw ApiException('Неверный JSON инвайта: ${e.message}');
    }
  }

  /// Список инвайтов (owner / chief_admin).
  Future<List<dynamic>> listAdminInvites({int limit = 100}) async {
    final uri = _uri('/admin/invites', {'limit': '$limit'});
    final headers = await _jsonHeaders(includeBearerIfPresent: true);
    final hadBearer = headers.containsKey('Authorization');
    try {
      final resp = await _http.get(uri, headers: headers);
      if (resp.statusCode == 401) {
        await _on401IfHadBearer(hadBearer, resp);
      }
      if (resp.statusCode != 200) {
        throw ApiException(
          _extractErrorMessage(resp.body),
          statusCode: resp.statusCode,
        );
      }
      return jsonDecode(utf8.decode(resp.bodyBytes)) as List<dynamic>;
    } on SocketException catch (e) {
      throw ApiException('Нет сети: ${e.message}');
    } on http.ClientException catch (e) {
      throw ApiException('Сеть: ${e.message}');
    } on FormatException catch (e) {
      throw ApiException('Неверный JSON списка инвайтов: ${e.message}');
    }
  }

  /// Регистрация FCM-токена ([POST /push/token]).
  Future<void> sendPushToken(String token) async {
    final uri = _uri('/push/token');
    final headers = await _jsonHeaders(includeBearerIfPresent: true);
    final hadBearer = headers.containsKey('Authorization');
    final body = jsonEncode({'token': token});
    try {
      final resp = await _http.post(uri, headers: headers, body: body);
      if (resp.statusCode == 401) {
        await _on401IfHadBearer(hadBearer, resp);
      }
      if (resp.statusCode != 200 && resp.statusCode != 201) {
        throw ApiException(
          _extractErrorMessage(resp.body),
          statusCode: resp.statusCode,
        );
      }
    } on SocketException catch (e) {
      throw ApiException('Нет сети: ${e.message}');
    } on http.ClientException catch (e) {
      throw ApiException('Сеть: ${e.message}');
    } on FormatException catch (e) {
      throw ApiException('Неверный JSON push: ${e.message}');
    }
  }

  void dispose() {
    _http.close();
  }
}
