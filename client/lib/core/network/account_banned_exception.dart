/// Ответ API при заблокированном аккаунте (403, detail.code == account_blocked).
class AccountBannedException implements Exception {
  AccountBannedException({
    required this.accountStatus,
    required this.reason,
    this.banUntil,
    this.remainingSeconds,
  });

  final String accountStatus;
  final String reason;
  final String? banUntil;
  final int? remainingSeconds;

  @override
  String toString() => reason;
}
