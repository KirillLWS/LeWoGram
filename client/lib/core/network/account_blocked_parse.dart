import 'dart:convert';

import 'package:lewogram_client/core/network/account_banned_exception.dart';

AccountBannedException? parseAccountBlockedFromBody(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return null;
    final detail = decoded['detail'];
    if (detail is! Map<String, dynamic>) return null;
    if (detail['code'] != 'account_blocked') return null;
    final status = detail['account_status']?.toString() ?? 'banned';
    final reason = detail['reason']?.toString().trim().isNotEmpty == true
        ? detail['reason'].toString()
        : 'Аккаунт заблокирован';
    final banUntil = detail['ban_until']?.toString();
    final rem = detail['remaining_seconds'];
    int? remaining;
    if (rem is int) {
      remaining = rem;
    } else if (rem is num) {
      remaining = rem.toInt();
    }
    return AccountBannedException(
      accountStatus: status,
      reason: reason,
      banUntil: banUntil?.trim().isEmpty == true ? null : banUntil,
      remainingSeconds: remaining,
    );
  } catch (_) {
    return null;
  }
}
