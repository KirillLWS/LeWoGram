import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:lewogram_client/core/config/app_config.dart';
import 'package:lewogram_client/core/network/account_banned_exception.dart';
import 'package:lewogram_client/core/network/account_blocked_parse.dart';
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

/// 202 на /auth/login: пароль верный, но устройство новое — нужен запрос владельцу.
class MustRequestTransferException extends ApiException {
  MustRequestTransferException({required this.transferReason})
      : super(
          'Вход с нового устройства возможен после подтверждения владельцем или главным админом.',
          statusCode: 202,
        );

  final String transferReason;
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

  /// Таймаут для админ-обзора смены устройства (ожидание ответа сервера целиком,
  /// включая возможный refresh токена).
  static const Duration deviceTransferAdminOverviewTimeout = Duration(seconds: 45);

  /// После сброса токена при 401 с Bearer (например навигация на `/login`).
  final UnauthorizedCallback? onUnauthorized;

  final String _baseUrl;
  final TokenStorage _tokenStorage;
  final http.Client _http;

  Uri _uri(String path, [Map<String, String>? query]) {
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$_baseUrl$p').replace(queryParameters: query);
  }

  /// Сохранить access + refresh (например после одноразовой выдачи на poll).
  Future<void> applyTokenPair({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _tokenStorage.saveToken(accessToken);
    await _tokenStorage.saveRefreshToken(refreshToken);
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

  Future<bool> _tryRefreshAccessToken() async {
    final refresh = await _tokenStorage.readRefreshToken();
    if (refresh == null || refresh.isEmpty) return false;
    try {
      final uri = _uri('/auth/refresh');
      final resp = await _http.post(
        uri,
        headers: const {
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: jsonEncode({'refresh_token': refresh}),
      );
      if (resp.statusCode != 200) {
        await _tokenStorage.clearToken();
        final banned = parseAccountBlockedFromBody(utf8.decode(resp.bodyBytes));
        if (banned != null) {
          throw banned;
        }
        return false;
      }
      final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final access = data['access_token'] as String?;
      final next = data['refresh_token'] as String?;
      if (access == null || access.isEmpty) {
        await _tokenStorage.clearToken();
        return false;
      }
      await _tokenStorage.saveToken(access);
      if (next != null && next.isNotEmpty) {
        await _tokenStorage.saveRefreshToken(next);
      }
      return true;
    } catch (e) {
      if (e is AccountBannedException) rethrow;
      await _tokenStorage.clearToken();
      return false;
    }
  }

  Future<http.Response> _authorizedJsonRequest(
    Future<http.Response> Function(Map<String, String> headers) send,
  ) async {
    var headers = await _jsonHeaders(includeBearerIfPresent: true);
    final hadBearer = headers.containsKey('Authorization');
    var resp = await send(headers);
    if (resp.statusCode == 401 && hadBearer) {
      if (await _tryRefreshAccessToken()) {
        headers = await _jsonHeaders(includeBearerIfPresent: true);
        resp = await send(headers);
      }
    }
    if (resp.statusCode == 401) {
      await _on401IfHadBearer(hadBearer, resp);
    }
    if (resp.statusCode == 403 && hadBearer) {
      final banned = parseAccountBlockedFromBody(resp.body);
      if (banned != null) {
        await _tokenStorage.clearToken();
        throw banned;
      }
    }
    return resp;
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
      if (resp.statusCode == 202) {
        final data =
            jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        if (data['must_request_transfer'] == true) {
          throw MustRequestTransferException(
            transferReason: data['reason'] as String? ?? 'new_device',
          );
        }
      }
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        final banned = parseAccountBlockedFromBody(utf8.decode(resp.bodyBytes));
        if (banned != null) {
          throw banned;
        }
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
      final refresh = data['refresh_token'] as String?;
      if (refresh != null && refresh.isNotEmpty) {
        await _tokenStorage.saveRefreshToken(refresh);
      }
      return data;
    } on AccountBannedException {
      rethrow;
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
      final refresh = data['refresh_token'] as String?;
      if (refresh != null && refresh.isNotEmpty) {
        await _tokenStorage.saveRefreshToken(refresh);
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

  /// [POST /device-transfer/request] без JWT.
  /// Возвращает нормализованный объект с [request_id], [short_code], [expires_at].
  Future<Map<String, dynamic>> deviceTransferRequest({
    required String login,
    String? password,
    String? recoveryPhrase,
    required String mode,
    required String deviceFingerprint,
    String? deviceModel,
    String? deviceOs,
    required String reason,
    double? geoLat,
    double? geoLng,
    double? geoAccuracyM,
  }) async {
    try {
      final uri = _uri('/device-transfer/request');
      final bodyMap = <String, dynamic>{
        'login': login,
        'mode': mode,
        'device_fingerprint': deviceFingerprint,
        'reason': reason,
        if (password != null && password.isNotEmpty) 'password': password,
        if (recoveryPhrase != null && recoveryPhrase.isNotEmpty)
          'recovery_phrase': recoveryPhrase,
        if (deviceModel != null && deviceModel.isNotEmpty)
          'device_model': deviceModel,
        if (deviceOs != null && deviceOs.isNotEmpty) 'device_os': deviceOs,
        if (geoLat != null) 'geo_lat': geoLat,
        if (geoLng != null) 'geo_lng': geoLng,
        if (geoAccuracyM != null) 'geo_accuracy_m': geoAccuracyM,
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
      final raw =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final id = raw['id'];
      return <String, dynamic>{
        'request_id': id,
        'short_code': raw['short_code'],
        'expires_at': raw['expires_at'],
        ...raw,
      };
    } on SocketException catch (e) {
      throw ApiException('Нет сети: ${e.message}');
    } on http.ClientException catch (e) {
      throw ApiException('Сеть: ${e.message}');
    } on FormatException catch (e) {
      throw ApiException('Неверный ответ сервера: ${e.message}');
    }
  }

  /// [GET /device-transfer/{id}/poll] без JWT.
  Future<Map<String, dynamic>> deviceTransferPoll({
    required int requestId,
    required String shortCode,
  }) async {
    try {
      final uri = _uri(
        '/device-transfer/$requestId/poll',
        {'code': shortCode},
      );
      final headers = await _jsonHeaders(includeBearerIfPresent: false);
      final resp = await _http.get(uri, headers: headers);
      if (resp.statusCode == 410) {
        throw ApiException(
          _extractErrorMessage(resp.body),
          statusCode: 410,
        );
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
      throw ApiException('Неверный ответ сервера: ${e.message}');
    }
  }

  /// [POST /device-transfer/{id}/cancel] с JWT.
  Future<Map<String, dynamic>> deviceTransferCancel(int requestId) async {
    final uri = _uri('/device-transfer/$requestId/cancel');
    try {
      final resp = await _authorizedJsonRequest(
        (headers) => _http.post(uri, headers: headers, body: '{}'),
      );
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
      throw ApiException('Неверный ответ сервера: ${e.message}');
    }
  }

  /// [GET /device-transfer/admin-overview] — pending + history (owner / chief_admin / admin).
  Future<Map<String, dynamic>> deviceTransferAdminOverview() async {
    final uri = _uri('/device-transfer/admin-overview');
    developer.log('start', name: 'lewogram.api.device_transfer.admin_overview');
    try {
      final resp = await _authorizedJsonRequest(
        (headers) => _http.get(uri, headers: headers),
      ).timeout(
        deviceTransferAdminOverviewTimeout,
        onTimeout: () => throw TimeoutException(
          'Таймаут ${deviceTransferAdminOverviewTimeout.inSeconds} с',
          deviceTransferAdminOverviewTimeout,
        ),
      );
      developer.log(
        'response status=${resp.statusCode} bytes=${resp.bodyBytes.length}',
        name: 'lewogram.api.device_transfer.admin_overview',
      );
      if (resp.statusCode != 200) {
        throw ApiException(
          _extractErrorMessage(resp.body),
          statusCode: resp.statusCode,
        );
      }
      final data = jsonDecode(utf8.decode(resp.bodyBytes));
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      throw ApiException('Неверный ответ сервера');
    } on TimeoutException catch (e) {
      developer.log(
        'timeout: $e',
        name: 'lewogram.api.device_transfer.admin_overview',
      );
      throw ApiException(
        'Сервер не ответил вовремя (${deviceTransferAdminOverviewTimeout.inSeconds} с). '
        'Проверьте адрес ${AppConfig.baseUrl} и сеть.',
      );
    } on SocketException catch (e) {
      developer.log(
        'socket: ${e.message}',
        name: 'lewogram.api.device_transfer.admin_overview',
      );
      throw ApiException('Нет сети: ${e.message}');
    } on http.ClientException catch (e) {
      developer.log(
        'client: ${e.message}',
        name: 'lewogram.api.device_transfer.admin_overview',
      );
      throw ApiException('Сеть: ${e.message}');
    } on FormatException catch (e) {
      developer.log(
        'format: ${e.message}',
        name: 'lewogram.api.device_transfer.admin_overview',
      );
      throw ApiException('Неверный ответ сервера: ${e.message}');
    } on ApiException {
      rethrow;
    } on UnauthorizedException {
      rethrow;
    } catch (e, st) {
      developer.log(
        'error: $e',
        name: 'lewogram.api.device_transfer.admin_overview',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// [GET /device-transfer/my]
  Future<List<dynamic>> deviceTransferMy() async {
    final uri = _uri('/device-transfer/my');
    try {
      final resp = await _authorizedJsonRequest(
        (headers) => _http.get(uri, headers: headers),
      );
      if (resp.statusCode != 200) {
        throw ApiException(
          _extractErrorMessage(resp.body),
          statusCode: resp.statusCode,
        );
      }
      final data = jsonDecode(utf8.decode(resp.bodyBytes));
      if (data is List<dynamic>) return data;
      throw ApiException('Неверный ответ сервера');
    } on SocketException catch (e) {
      throw ApiException('Нет сети: ${e.message}');
    } on http.ClientException catch (e) {
      throw ApiException('Сеть: ${e.message}');
    } on FormatException catch (e) {
      throw ApiException('Неверный ответ сервера: ${e.message}');
    }
  }

  /// [GET /device-transfer/pending] (owner / chief_admin / admin).
  Future<List<dynamic>> deviceTransferPending() async {
    final uri = _uri('/device-transfer/pending');
    try {
      final resp = await _authorizedJsonRequest(
        (headers) => _http.get(uri, headers: headers),
      );
      if (resp.statusCode != 200) {
        throw ApiException(
          _extractErrorMessage(resp.body),
          statusCode: resp.statusCode,
        );
      }
      final data = jsonDecode(utf8.decode(resp.bodyBytes));
      if (data is List<dynamic>) return data;
      throw ApiException('Неверный ответ сервера');
    } on SocketException catch (e) {
      throw ApiException('Нет сети: ${e.message}');
    } on http.ClientException catch (e) {
      throw ApiException('Сеть: ${e.message}');
    } on FormatException catch (e) {
      throw ApiException('Неверный ответ сервера: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> deviceTransferApprove(
    int requestId, {
    bool revokeOld = false,
  }) async {
    final uri = _uri('/device-transfer/$requestId/approve');
    final body = jsonEncode({'revoke_old': revokeOld});
    try {
      final resp = await _authorizedJsonRequest(
        (headers) => _http.post(uri, headers: headers, body: body),
      );
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
      throw ApiException('Неверный ответ сервера: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> deviceTransferDeny(
    int requestId, {
    String? note,
  }) async {
    final uri = _uri('/device-transfer/$requestId/deny');
    final body = jsonEncode({'note': note});
    try {
      final resp = await _authorizedJsonRequest(
        (headers) => _http.post(uri, headers: headers, body: body),
      );
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
      throw ApiException('Неверный ответ сервера: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getMe() async {
    final uri = _uri('/auth/me');
    try {
      final resp = await _authorizedJsonRequest(
        (headers) => _http.get(uri, headers: headers),
      );
      if (resp.statusCode != 200) {
        final banned = parseAccountBlockedFromBody(utf8.decode(resp.bodyBytes));
        if (banned != null) {
          throw banned;
        }
        throw ApiException(
          _extractErrorMessage(resp.body),
          statusCode: resp.statusCode,
        );
      }
      return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    } on AccountBannedException {
      rethrow;
    } on SocketException catch (e) {
      throw ApiException('Нет сети: ${e.message}');
    } on http.ClientException catch (e) {
      throw ApiException('Сеть: ${e.message}');
    } on FormatException catch (e) {
      throw ApiException('Неверный JSON /auth/me: ${e.message}');
    }
  }

  /// Загрузка аватара ([POST /users/me/avatar], поле формы `avatar`).
  Future<Map<String, dynamic>> uploadAvatar(File file) async {
    final uri = _uri('/users/me/avatar');
    final token0 = await _tokenStorage.readToken();
    final had = token0 != null && token0.isNotEmpty;

    Future<http.Response> sendOnce() async {
      final request = http.MultipartRequest('POST', uri);
      final token = await _tokenStorage.readToken();
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      request.files.add(
        await http.MultipartFile.fromPath('avatar', file.path),
      );
      final streamed = await _http.send(request);
      return http.Response.fromStream(streamed);
    }

    try {
      var resp = await sendOnce();
      if (resp.statusCode == 401 && had) {
        if (await _tryRefreshAccessToken()) {
          resp = await sendOnce();
        }
      }
      if (resp.statusCode == 401) {
        await _on401IfHadBearer(had, resp);
      }
      if (resp.statusCode == 413) {
        throw ApiException(
          'Файл слишком большой (лимит сервера)',
          statusCode: 413,
        );
      }
      if (resp.statusCode == 415) {
        throw ApiException(
          'Недопустимый тип файла (jpg, png или webp)',
          statusCode: 415,
        );
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
      throw ApiException('Неверный ответ при загрузке аватара: ${e.message}');
    }
  }

  /// Создать личный чат ([POST /messages/chats/direct]).
  Future<Map<String, dynamic>> createDirectChat(int otherUserId) async {
    final uri = _uri('/messages/chats/direct');
    final body = jsonEncode({'other_user_id': otherUserId});
    try {
      final resp = await _authorizedJsonRequest(
        (headers) => _http.post(uri, headers: headers, body: body),
      );
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
    final body = jsonEncode({
      'title': title.trim(),
      'member_ids': memberIds,
    });
    try {
      final resp = await _authorizedJsonRequest(
        (headers) => _http.post(uri, headers: headers, body: body),
      );
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
    final body = jsonEncode({'token': token.trim()});
    try {
      final resp = await _authorizedJsonRequest(
        (headers) => _http.post(uri, headers: headers, body: body),
      );
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
    try {
      final resp = await _authorizedJsonRequest(
        (headers) => _http.get(uri, headers: headers),
      );
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
    try {
      final resp = await _authorizedJsonRequest(
        (headers) => _http.get(uri, headers: headers),
      );
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
    final body = jsonEncode({'chat_id': chatId, 'text': text});
    try {
      final resp = await _authorizedJsonRequest(
        (headers) => _http.post(uri, headers: headers, body: body),
      );
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
    final body = jsonEncode({
      'chat_id': chatId,
      'message_id': messageId,
    });
    try {
      final resp = await _authorizedJsonRequest(
        (headers) => _http.post(uri, headers: headers, body: body),
      );
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
    final bodyMap = <String, dynamic>{
      'title': title,
      if (description != null) 'description': description,
    };
    try {
      final resp = await _authorizedJsonRequest(
        (headers) => _http.patch(
          uri,
          headers: headers,
          body: jsonEncode(bodyMap),
        ),
      );
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

  /// Создать инвайт (owner / chief_admin / admin на сервере).
  Future<Map<String, dynamic>> createAdminInvite({
    int expiresHours = 48,
    String? note,
  }) async {
    final uri = _uri('/admin/invites');
    final body = jsonEncode({
      'expires_hours': expiresHours,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
    try {
      final resp = await _authorizedJsonRequest(
        (headers) => _http.post(uri, headers: headers, body: body),
      );
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

  /// Список инвайтов (owner / chief_admin / admin).
  Future<List<dynamic>> listAdminInvites({int limit = 100}) async {
    final uri = _uri('/admin/invites', {'limit': '$limit'});
    try {
      final resp = await _authorizedJsonRequest(
        (headers) => _http.get(uri, headers: headers),
      );
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

  /// Поиск пользователей ([GET /users/search]).
  Future<List<dynamic>> searchUsers(String query, {int limit = 50}) async {
    final uri = _uri('/users/search', {'q': query, 'limit': '$limit'});
    try {
      final resp = await _authorizedJsonRequest(
        (headers) => _http.get(uri, headers: headers),
      );
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
      throw ApiException('Неверный JSON поиска: ${e.message}');
    }
  }

  /// Публичный профиль ([GET /users/{id}]).
  Future<Map<String, dynamic>> getUserPublic(int userId) async {
    final uri = _uri('/users/$userId');
    try {
      final resp = await _authorizedJsonRequest(
        (headers) => _http.get(uri, headers: headers),
      );
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
      throw ApiException('Неверный JSON профиля: ${e.message}');
    }
  }

  /// Список друзей ([GET /friends/]).
  Future<List<dynamic>> friendsList() async {
    final uri = _uri('/friends/');
    try {
      final resp = await _authorizedJsonRequest(
        (headers) => _http.get(uri, headers: headers),
      );
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
      throw ApiException('Неверный JSON друзей: ${e.message}');
    }
  }

  /// Входящие заявки ([GET /friends/incoming]).
  Future<List<dynamic>> friendsIncoming() async {
    final uri = _uri('/friends/incoming');
    try {
      final resp = await _authorizedJsonRequest(
        (headers) => _http.get(uri, headers: headers),
      );
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
      throw ApiException('Неверный JSON заявок: ${e.message}');
    }
  }

  /// Исходящие заявки ([GET /friends/outgoing]).
  Future<List<dynamic>> friendsOutgoing() async {
    final uri = _uri('/friends/outgoing');
    try {
      final resp = await _authorizedJsonRequest(
        (headers) => _http.get(uri, headers: headers),
      );
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
      throw ApiException('Неверный JSON подписок: ${e.message}');
    }
  }

  /// Статус дружбы с пользователем ([GET /friends/status/{id}]).
  Future<Map<String, dynamic>> friendsStatus(int otherUserId) async {
    final uri = _uri('/friends/status/$otherUserId');
    try {
      final resp = await _authorizedJsonRequest(
        (headers) => _http.get(uri, headers: headers),
      );
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
      throw ApiException('Неверный JSON статуса: ${e.message}');
    }
  }

  /// Отправить заявку в друзья ([POST /friends/request]).
  Future<Map<String, dynamic>> friendsRequest(int targetUserId) async {
    final uri = _uri('/friends/request');
    final body = jsonEncode({'target_user_id': targetUserId});
    try {
      final resp = await _authorizedJsonRequest(
        (headers) => _http.post(uri, headers: headers, body: body),
      );
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
      throw ApiException('Неверный JSON заявки: ${e.message}');
    }
  }

  /// Принять заявку ([POST /friends/accept/{id}]).
  Future<void> friendsAccept(int requestId) async {
    final uri = _uri('/friends/accept/$requestId');
    try {
      final resp = await _authorizedJsonRequest(
        (headers) => _http.post(uri, headers: headers),
      );
      if (resp.statusCode != 200 && resp.statusCode != 201 && resp.statusCode != 204) {
        throw ApiException(
          _extractErrorMessage(resp.body),
          statusCode: resp.statusCode,
        );
      }
    } on SocketException catch (e) {
      throw ApiException('Нет сети: ${e.message}');
    } on http.ClientException catch (e) {
      throw ApiException('Сеть: ${e.message}');
    }
  }

  /// Отклонить заявку ([POST /friends/decline/{id}]).
  Future<void> friendsDecline(int requestId) async {
    final uri = _uri('/friends/decline/$requestId');
    try {
      final resp = await _authorizedJsonRequest(
        (headers) => _http.post(uri, headers: headers),
      );
      if (resp.statusCode != 200 &&
          resp.statusCode != 201 &&
          resp.statusCode != 204) {
        throw ApiException(
          _extractErrorMessage(resp.body),
          statusCode: resp.statusCode,
        );
      }
    } on SocketException catch (e) {
      throw ApiException('Нет сети: ${e.message}');
    } on http.ClientException catch (e) {
      throw ApiException('Сеть: ${e.message}');
    }
  }

  /// Отозвать исходящую заявку ([DELETE /friends/cancel/{targetUserId}]).
  Future<void> friendsCancel(int targetUserId) async {
    final uri = _uri('/friends/cancel/$targetUserId');
    try {
      final resp = await _authorizedJsonRequest(
        (headers) => _http.delete(uri, headers: headers),
      );
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
    }
  }

  /// Удалить из друзей ([DELETE /friends/{otherUserId}]).
  Future<void> friendsRemove(int otherUserId) async {
    final uri = _uri('/friends/$otherUserId');
    try {
      final resp = await _authorizedJsonRequest(
        (headers) => _http.delete(uri, headers: headers),
      );
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
    }
  }

  /// Заблокировать ([POST /friends/block/{otherUserId}]).
  Future<void> friendsBlock(int otherUserId) async {
    final uri = _uri('/friends/block/$otherUserId');
    try {
      final resp = await _authorizedJsonRequest(
        (headers) => _http.post(uri, headers: headers),
      );
      if (resp.statusCode != 200 && resp.statusCode != 201 && resp.statusCode != 204) {
        throw ApiException(
          _extractErrorMessage(resp.body),
          statusCode: resp.statusCode,
        );
      }
    } on SocketException catch (e) {
      throw ApiException('Нет сети: ${e.message}');
    } on http.ClientException catch (e) {
      throw ApiException('Сеть: ${e.message}');
    }
  }

  /// Разблокировать ([DELETE /friends/block/{otherUserId}]).
  Future<void> friendsUnblock(int otherUserId) async {
    final uri = _uri('/friends/block/$otherUserId');
    try {
      final resp = await _authorizedJsonRequest(
        (headers) => _http.delete(uri, headers: headers),
      );
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
    }
  }

  /// Регистрация FCM-токена ([POST /push/token]).
  Future<void> sendPushToken(String token) async {
    final uri = _uri('/push/token');
    final body = jsonEncode({'token': token});
    try {
      final resp = await _authorizedJsonRequest(
        (headers) => _http.post(uri, headers: headers, body: body),
      );
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

  /// Список всех пользователей ([GET /admin/users], staff).
  Future<Map<String, dynamic>> adminListUsers({
    int limit = 50,
    int offset = 0,
    String? query,
  }) async {
    final uri = _uri('/admin/users', {
      'limit': '$limit',
      'offset': '$offset',
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
    });
    try {
      final resp = await _authorizedJsonRequest(
        (headers) => _http.get(uri, headers: headers),
      );
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
      throw ApiException('Неверный JSON списка пользователей: ${e.message}');
    }
  }

  /// Staff-блокировка ([POST /admin/users/{id}/ban]).
  Future<Map<String, dynamic>> adminBanUser(
    int userId, {
    required String kind,
    String reason = '',
    int? durationMinutes,
  }) async {
    final uri = _uri('/admin/users/$userId/ban');
    final body = <String, dynamic>{
      'kind': kind,
      'reason': reason,
      if (durationMinutes != null) 'duration_minutes': durationMinutes,
    };
    try {
      final resp = await _authorizedJsonRequest(
        (headers) => _http.post(uri, headers: headers, body: jsonEncode(body)),
      );
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
      throw ApiException('Неверный JSON бана: ${e.message}');
    }
  }

  /// Снять staff-блокировку ([POST /admin/users/{id}/unban]).
  Future<Map<String, dynamic>> adminUnbanUser(int userId) async {
    final uri = _uri('/admin/users/$userId/unban');
    try {
      final resp = await _authorizedJsonRequest(
        (headers) => _http.post(uri, headers: headers, body: '{}'),
      );
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
      throw ApiException('Неверный JSON разбана: ${e.message}');
    }
  }

  void dispose() {
    _http.close();
  }
}
