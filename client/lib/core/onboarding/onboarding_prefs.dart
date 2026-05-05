import 'package:shared_preferences/shared_preferences.dart';

/// Ключ и чтение/запись флага «онбординг разрешений пройден».
abstract final class OnboardingPrefs {
  static const String doneKey = 'lewogram_onboarding_done';

  static Future<bool> isDone() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(doneKey) ?? false;
  }

  static Future<void> setDone() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(doneKey, true);
  }
}
