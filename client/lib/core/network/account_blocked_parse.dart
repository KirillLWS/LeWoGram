import 'dart:convert';

import 'package:lewogram_client/core/network/account_banned_exception.dart';

int? _remainingSecondsFromBanUntil(String? banUntil) {
  final raw = banUntil?.trim();
  if (raw == null || raw.isEmpty) return null;
  final normalized = raw.contains('T') ? raw : raw.replaceFirst(' ', 'T');
  final end = DateTime.tryParse(normalized);
  if (end == null) return null;
  final endUtc = end.isUtc ? end : end.toUtc();
  final now = DateTime.now().toUtc();
  final sec = endUtc.difference(now).inSeconds;
  return sec > 0 ? sec : 0;
}

AccountBannedException? parseAccountBlockedFromBody(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return null;
    Map<String, dynamic>? detail = decoded['detail'] is Map<String, dynamic>
        ? decoded['detail'] as Map<String, dynamic>
        : null;
    detail ??= decoded['code'] == 'account_blocked' ? decoded : null;
    if (detail == null) return null;
    if (detail['code'] != 'account_blocked') return null;

    final isPermanent = detail['is_permanent'] == true;
    final reason = detail['reason']?.toString().trim().isNotEmpty == true
        ? detail['reason'].toString()
        : 'Аккаунт заблокирован';
    final banUntilRaw = detail['ban_until']?.toString();
    final banUntil =
        banUntilRaw != null && banUntilRaw.trim().isNotEmpty ? banUntilRaw.trim() : null;

    final status = isPermanent ? 'banned' : 'temp_banned';
    final remainingLegacy = detail['remaining_seconds'];
    int? remaining = _remainingSecondsFromBanUntil(banUntil);
    if (remainingLegacy is int) {
      remaining = remainingLegacy;
    } else if (remainingLegacy is num) {
      remaining = remainingLegacy.toInt();
    }

    return AccountBannedException(
      accountStatus: status,
      reason: reason,
      banUntil: banUntil,
      remainingSeconds: remaining,
    );
  } catch (_) {
    return null;
  }
}
