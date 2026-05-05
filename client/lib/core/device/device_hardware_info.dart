import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

/// Человекочитаемая модель и ОС для [deviceTransferRequest].
Future<({String model, String os})> readDeviceHardwareLabel() async {
  final plugin = DeviceInfoPlugin();
  if (Platform.isAndroid) {
    final a = await plugin.androidInfo;
    final brand = a.brand.trim();
    final man = a.manufacturer.trim();
    final mod = a.model.trim();
    final head = brand.isNotEmpty ? brand : (man.isNotEmpty ? man : 'Android');
    final model = mod.isNotEmpty ? '$head $mod' : head;
    final rel = a.version.release.trim();
    final os = rel.isNotEmpty ? 'Android $rel' : 'Android';
    return (model: model, os: os);
  }
  if (Platform.isIOS) {
    final i = await plugin.iosInfo;
    final model = i.utsname.machine.trim().isNotEmpty
        ? i.utsname.machine.trim()
        : (i.model.trim().isNotEmpty ? i.model.trim() : 'iOS');
    final osVer = i.systemVersion.trim();
    final os = osVer.isNotEmpty ? 'iOS $osVer' : 'iOS';
    return (model: model, os: os);
  }
  return (model: 'Flutter', os: Platform.operatingSystem);
}
