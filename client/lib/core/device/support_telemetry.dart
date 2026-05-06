import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:lewogram_client/core/device/device_fingerprint.dart';

/// Неблокирующий снимок окружения клиента для журнала поддержки (без потоковой камеры/микрофона).
Future<Map<String, dynamic>> collectSupportTelemetrySnapshot() async {
  final out = <String, dynamic>{
    'platform': Platform.operatingSystem,
    'platform_version': Platform.operatingSystemVersion,
  };
  try {
    out['device_fingerprint'] = await DeviceFingerprint().getOrCreate();
  } catch (_) {
    out['device_fingerprint'] = null;
  }
  try {
    final bat = Battery();
    final lvl = await bat.batteryLevel;
    final st = await bat.batteryState;
    out['battery_percent'] = lvl;
    out['battery_state'] = st.name;
    out['battery_is_charging'] =
        st == BatteryState.charging || st == BatteryState.full;
  } catch (_) {
    out['battery_percent'] = null;
  }
  try {
    final di = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final a = await di.androidInfo;
      out['device_model'] = '${a.manufacturer} ${a.model}'.trim();
      out['device_os_label'] =
          'Android ${a.version.release} (SDK ${a.version.sdkInt})';
    } else if (Platform.isIOS) {
      final i = await di.iosInfo;
      out['device_model'] = i.utsname.machine;
      out['device_os_label'] = '${i.systemName} ${i.systemVersion}';
    } else {
      out['device_model'] = 'desktop/other';
      out['device_os_label'] = Platform.operatingSystemVersion;
    }
  } catch (e) {
    out['device_info_error'] = e.toString();
  }
  return out;
}
