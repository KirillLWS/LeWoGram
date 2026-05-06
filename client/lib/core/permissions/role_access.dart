/// Роли из [GET /auth/me]: `roles` и авторитетное поле `primary_role` с сервера.
abstract final class RoleAccess {
  /// Синхронно с server `OPERATIONAL_STAFF_ROLES`: owner, chief_admin, admin.
  static const Set<String> operationalStaffRoles = {
    'owner',
    'chief_admin',
    'admin',
  };

  static const List<String> _privilegeOrder = [
    'user',
    'developer',
    'admin',
    'chief_admin',
    'owner',
  ];

  static int _rank(String role) {
    final i = _privilegeOrder.indexOf(role);
    return i >= 0 ? i : 0;
  }

  static bool _anyRoleMatch(Iterable<String> roles, Set<String> allowed) {
    for (final r in roles) {
      if (allowed.contains(r)) return true;
    }
    return false;
  }

  /// Fallback, если сервер не прислал `primary_role` (устаревший клиент / старый ответ).
  static String? primaryPrivilegedRole(List<String> roles) {
    if (roles.isEmpty) return null;
    String? best;
    var bestR = -1;
    for (final r in roles) {
      final rr = _rank(r);
      if (rr > bestR) {
        bestR = rr;
        best = r;
      }
    }
    if (best == null || best == 'user') return null;
    return best;
  }

  /// Главная привилегированная роль: доверяем серверу [`primary_role`], иначе считаем из списка.
  static String? resolvedPrivilegedPrimary(
    List<String> roles, {
    String? serverPrimaryRole,
  }) {
    final s = serverPrimaryRole?.trim();
    if (s != null && s.isNotEmpty) {
      if (s == 'user') return null;
      return s;
    }
    return primaryPrivilegedRole(roles);
  }

  static bool hasOperationalStaffRole(Iterable<String> roles) =>
      _anyRoleMatch(roles, operationalStaffRoles);

  /// Ровно одна админская вкладка: только если главная роль admin или chief_admin.
  static bool showAdminNav(
    List<String> roles, {
    String? serverPrimaryRole,
  }) {
    final p = resolvedPrivilegedPrimary(roles, serverPrimaryRole: serverPrimaryRole);
    return p == 'admin' || p == 'chief_admin';
  }

  /// Вкладка владельца только если главная роль owner.
  static bool showOwnerNav(
    List<String> roles, {
    String? serverPrimaryRole,
  }) =>
      resolvedPrivilegedPrimary(roles, serverPrimaryRole: serverPrimaryRole) == 'owner';

  /// Dev: только главная роль developer.
  static bool showDeveloperNav(
    List<String> roles, {
    String? serverPrimaryRole,
  }) =>
      resolvedPrivilegedPrimary(roles, serverPrimaryRole: serverPrimaryRole) == 'developer';

  static bool canManageInvitesAndDeviceTransfers(
    List<String> roles, {
    String? serverPrimaryRole,
  }) {
    final p = resolvedPrivilegedPrimary(roles, serverPrimaryRole: serverPrimaryRole);
    return p != null && operationalStaffRoles.contains(p);
  }
}
