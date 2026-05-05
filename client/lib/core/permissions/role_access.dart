/// Роли приходят только из [GET /auth/me] → поле `roles` (на сервере — таблица user_roles).
/// Не дублировать проверки вида `roles.contains('admin')` вне этого файла.
abstract final class RoleAccess {
  /// Синхронно с server `OPERATIONAL_STAFF_ROLES`: owner, chief_admin, admin.
  static const Set<String> operationalStaffRoles = {
    'owner',
    'chief_admin',
    'admin',
  };

  static const Set<String> _ownerHubRoles = {'owner'};

  /// Вкладка «Разработка»: capability developer или owner (как на сервере по ролям).
  static const Set<String> _developerHubRoles = {'developer', 'owner'};

  static bool _anyRoleMatch(Iterable<String> roles, Set<String> allowed) {
    for (final r in roles) {
      if (allowed.contains(r)) return true;
    }
    return false;
  }

  /// Пересечение с [operationalStaffRoles] — операционный персонал.
  static bool hasOperationalStaffRole(Iterable<String> roles) =>
      _anyRoleMatch(roles, operationalStaffRoles);

  /// Вкладка «Админ» (инвайты, пользователи, смена устройства).
  static bool canOpenAdminHub(List<String> roles) =>
      hasOperationalStaffRole(roles);

  /// Вкладка «Владелец» (claim / transfer).
  static bool canOpenOwnerHub(List<String> roles) =>
      _anyRoleMatch(roles, _ownerHubRoles);

  /// Вкладка «Разработка».
  static bool canOpenDeveloperHub(List<String> roles) =>
      _anyRoleMatch(roles, _developerHubRoles);

  /// Инвайты и очередь смены устройства из профиля.
  static bool canManageInvitesAndDeviceTransfers(List<String> roles) =>
      hasOperationalStaffRole(roles);
}
