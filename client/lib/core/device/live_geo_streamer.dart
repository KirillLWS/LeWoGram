import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:lewogram_client/core/network/api_client.dart';

/// Периодически опрашивает GPS и отправляет точки на сервер,
/// пока активен support-access (или пока вручную не остановлен).
///
/// Один экземпляр на приложение (см. AppScope).
class LiveGeoStreamer {
  LiveGeoStreamer({required this.apiClient});

  final ApiClient apiClient;

  Timer? _timer;
  bool _busy = false;
  DateTime? _expiresAt;

  bool get isRunning => _timer != null;
  DateTime? get expiresAt => _expiresAt;

  /// Запустить стрим до [until] (UTC) с интервалом [interval].
  /// Безопасно вызывать повторно — перезапускает с новым окном.
  Future<void> start({
    required DateTime until,
    Duration interval = const Duration(seconds: 15),
  }) async {
    stop();
    final perm = await _ensurePermission();
    if (!perm) return;
    _expiresAt = until;
    await _tick();
    _timer = Timer.periodic(interval, (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _expiresAt = null;
  }

  Future<bool> _ensurePermission() async {
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    return p == LocationPermission.always ||
        p == LocationPermission.whileInUse;
  }

  Future<void> _tick() async {
    if (_busy) return;
    final exp = _expiresAt;
    if (exp != null && DateTime.now().toUtc().isAfter(exp.toUtc())) {
      stop();
      return;
    }
    _busy = true;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 12),
        ),
      );
      await apiClient.postMyLiveGeo(
        lat: pos.latitude,
        lng: pos.longitude,
        accuracyM: pos.accuracy,
        recordedAt: DateTime.now().toUtc().toIso8601String(),
      );
    } catch (_) {
      // тихо: следующий тик попробует снова.
    } finally {
      _busy = false;
    }
  }
}
