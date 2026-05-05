/// Результат диалога передачи владения — обрабатывается координатором (вызовы API).
class TransferOwnershipResult {
  const TransferOwnershipResult({
    required this.targetUserId,
    required this.selfRoleAfterTransfer,
  });

  /// Идентификатор пользователя, которому передаётся владение.
  final String targetUserId;

  /// Роль текущего владельца после передачи (заглушка: произвольная строка, например `member`).
  final String selfRoleAfterTransfer;
}
