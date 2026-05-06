import 'package:flutter/material.dart';
import 'package:lewogram_client/core/refresh/auto_refresh_mixin.dart';
import 'package:lewogram_client/core/network/api_client.dart';
import 'package:lewogram_client/features/developer/presentation/developer_hub_screen.dart';
import 'package:lewogram_client/features/profile/data/profile_user.dart';
import 'package:lewogram_client/features/profile/presentation/edit_profile_sheet.dart';
import 'package:lewogram_client/features/profile/presentation/profile_avatar.dart';
import 'package:lewogram_client/features/profile/presentation/role_history_placeholder_screen.dart';

/// Подбор локального файла аватара; координатор может подключить `image_picker` / загрузку на сервер.
typedef PickAvatarCallback = Future<String?> Function();

/// Профиль: данные из [ApiClient.getMe], выход через [onLogout] (очистка токена — снаружи).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.apiClient,
    this.onLogout,
    this.onEditProfile,
    this.editProfileRouteName,
    this.onPickAvatar,
    this.onAvatarPicked,
    this.onSaveProfile,
    this.avatarUrlOverride,
    this.resolveAvatarUrl,
    this.initialRoles = const [],
    this.loadRoles,
    this.invitesEligibility,
    this.onOpenInvites,
    this.onOpenOwnerClaim,
    this.onOpenDeviceTransferPending,
  });

  final ApiClient apiClient;

  /// Очистка сессии и навигация — подключает координатор ([TokenStorage.clearToken] и т.д.).
  final Future<void> Function()? onLogout;

  /// Редактирование: навигация на экран координатора. Если задано вместе с [editProfileRouteName], приоритет у колбэка.
  final void Function()? onEditProfile;

  /// Имя маршрута для `Navigator.pushNamed` (если [onEditProfile] == null).
  final String? editProfileRouteName;

  /// «Сменить аватар»: выбор файла; возвращает локальный путь или `null` при отмене.
  final PickAvatarCallback? onPickAvatar;

  /// После успешного выбора файла (локальный путь): загрузка на сервер и т.п.
  final Future<void> Function(String localPath)? onAvatarPicked;

  /// Сохранение полей профиля из модалки редактирования.
  final Future<void> Function(
      String displayName, String username, String about)? onSaveProfile;

  /// Подмена URL/пути аватара над значением из API.
  final String? avatarUrlOverride;

  /// Собрать URL для сетевого аватара (например, база API + относительный путь из [ProfileUser.avatarUrl]).
  final String? Function(ProfileUser user)? resolveAvatarUrl;

  /// Роли до асинхронной подгрузки; при [loadRoles] обновляются после вызова колбэка.
  final List<String> initialRoles;

  /// Асинхронная подгрузка ролей (например из API); вызывается при открытии и при обновлении профиля.
  final Future<List<String>> Function()? loadRoles;

  /// Условие показа «Инвайты» и «Запросы смены устройства» (owner, chief_admin, admin).
  final bool Function(List<String> roles)? invitesEligibility;

  /// Открыть экран управления инвайтами.
  final VoidCallback? onOpenInvites;

  /// Перейти к списку запросов на смену устройства (owner, chief_admin, admin).
  final VoidCallback? onOpenDeviceTransferPending;

  /// Перейти к одноразовому claim владельца ([OwnerClaimScreen]).
  final VoidCallback? onOpenOwnerClaim;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with AutoRefreshMixin {
  ProfileUser? _user;
  bool _loading = true;
  bool _loggingOut = false;
  bool _pickingAvatar = false;
  String? _error;
  late List<String> _roles;
  bool _loadingRoles = false;
  bool _initialized = false;

  @override
  Duration get refreshInterval => const Duration(seconds: 60);

  @override
  Future<void> performRefresh() => _loadMe(silent: true);

  String? _effectiveAvatarRef(ProfileUser user) {
    final o = widget.avatarUrlOverride?.trim();
    if (o != null && o.isNotEmpty) return o;
    final resolved = widget.resolveAvatarUrl?.call(user)?.trim();
    if (resolved != null && resolved.isNotEmpty) return resolved;
    return user.avatarUrl?.trim();
  }

  @override
  void initState() {
    super.initState();
    _roles = List<String>.from(widget.initialRoles);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadMe();
    });
  }

  Future<void> _syncRoles() async {
    final fn = widget.loadRoles;
    if (fn == null) return;
    setState(() => _loadingRoles = true);
    try {
      final next = await fn();
      if (!mounted) return;
      setState(() {
        _roles = List<String>.from(next);
        _loadingRoles = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingRoles = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось обновить роли: $e')),
      );
    }
  }

  Future<void> _loadMe({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final raw = await widget.apiClient.getMe();
      if (!mounted) return;
      setState(() {
        _user = ProfileUser.fromJson(Map<String, dynamic>.from(raw));
        _loading = false;
      });
      if (widget.loadRoles != null) await _syncRoles();
    } on UnauthorizedException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = e.message;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = e.toString();
      });
    }
  }

  Future<void> _logout() async {
    final fn = widget.onLogout;
    if (fn == null || _loggingOut) return;
    setState(() => _loggingOut = true);
    try {
      await fn();
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  Future<void> _handleEdit(ProfileUser user) async {
    final cb = widget.onEditProfile;
    if (cb != null) {
      cb();
      return;
    }
    final route = widget.editProfileRouteName?.trim();
    if (route != null && route.isNotEmpty) {
      Navigator.of(context).pushNamed(route);
      return;
    }
    await _openEditSheet(user);
  }

  Future<void> _saveProfileDefault(
    String displayName,
    String username,
    String about,
  ) async {
    await widget.apiClient.patchMe(
      displayName: displayName,
      username: username,
      about: about,
    );
  }

  Future<void> _openEditSheet(ProfileUser user) async {
    final saved = await showEditProfileSheet(
      context,
      initialDisplayName: user.displayName?.trim() ?? '',
      initialUsername: user.username,
      initialAbout: user.about?.trim() ?? '',
      onSave: widget.onSaveProfile ?? _saveProfileDefault,
    );
    if (saved == true && mounted) await _loadMe();
  }

  Future<void> _pickAvatar() async {
    final fn = widget.onPickAvatar;
    if (fn == null || _pickingAvatar) return;
    setState(() => _pickingAvatar = true);
    try {
      final path = await fn();
      if (!mounted) return;
      if (path != null && path.trim().isNotEmpty) {
        final trimmed = path.trim();
        final upload = widget.onAvatarPicked;
        if (upload != null) {
          try {
            await upload(trimmed);
          } on ApiException catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(e.message)),
              );
            }
          }
        }
        if (mounted) await _loadMe();
      }
    } finally {
      if (mounted) setState(() => _pickingAvatar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль'),
        actions: [
          if (_user != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Редактировать',
              onPressed: _loading ? null : () => _handleEdit(_user!),
            ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadMe,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (_loading && _user == null)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null && _user == null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style:
                            textTheme.bodyLarge?.copyWith(color: scheme.error),
                      ),
                    ),
                  ),
                )
              else if (_user != null) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      20,
                      20,
                      24 + MediaQuery.paddingOf(context).bottom,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ProfileAvatar(
                              user: _user!,
                              effectiveAvatarRef: _effectiveAvatarRef(_user!),
                              radius: 40,
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _user!.primaryLabel,
                                    style: textTheme.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '@${_user!.username}',
                                    style: textTheme.bodyMedium?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _aboutSummary(_user!.about),
                                    style: textTheme.bodyMedium?.copyWith(
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (widget.onPickAvatar != null)
                          OutlinedButton.icon(
                            onPressed: _pickingAvatar ? null : _pickAvatar,
                            icon: _pickingAvatar
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: scheme.primary,
                                    ),
                                  )
                                : const Icon(Icons.photo_camera_outlined),
                            label: const Text('Сменить аватар'),
                          ),
                        const SizedBox(height: 20),
                        Card(
                          elevation: 0,
                          color: scheme.surfaceContainerHighest,
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              _InfoTile(
                                icon: Icons.alternate_email_outlined,
                                label: 'Логин',
                                value: _user!.login,
                              ),
                              Divider(height: 1, color: scheme.outlineVariant),
                              _InfoTile(
                                icon: Icons.badge_outlined,
                                label: 'Отображаемое имя',
                                value: _user!.displayName?.trim().isNotEmpty ==
                                        true
                                    ? _user!.displayName!.trim()
                                    : '—',
                              ),
                              Divider(height: 1, color: scheme.outlineVariant),
                              _InfoTile(
                                icon: Icons.perm_identity_outlined,
                                label: 'Имя пользователя',
                                value: _user!.username,
                              ),
                              Divider(height: 1, color: scheme.outlineVariant),
                              _InfoTile(
                                icon: Icons.info_outline_rounded,
                                label: 'О себе',
                                value: _aboutDisplay(_user!.about),
                                alignTop: true,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Роли',
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (_loadingRoles)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: scheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Загрузка ролей…',
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else if (_roles.isEmpty)
                          Text(
                            'Нет назначенных ролей',
                            style: textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _roles
                                .map(
                                  (r) => Chip(
                                    label: Text(r),
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                )
                                .toList(),
                          ),
                        const SizedBox(height: 24),
                        Card(
                          elevation: 0,
                          color: scheme.surfaceContainerHighest,
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 16, 16, 8),
                                child: Text(
                                  'Безопасность',
                                  style: textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                child: Text(
                                  'Управление сессиями и ключами появится ниже; инвайты и смена устройства — для владельца, главного админа и администратора.',
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              if (widget.onOpenOwnerClaim != null) ...[
                                ListTile(
                                  leading: Icon(
                                    Icons.verified_user_outlined,
                                    color: scheme.primary,
                                  ),
                                  title: const Text('Первичный владелец'),
                                  subtitle: const Text(
                                    'Ввести INITIAL_OWNER_TOKEN с сервера',
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: widget.onOpenOwnerClaim,
                                ),
                                Divider(
                                    height: 1, color: scheme.outlineVariant),
                              ],
                              if (widget.invitesEligibility != null &&
                                  widget.onOpenInvites != null &&
                                  !_loadingRoles &&
                                  widget.invitesEligibility!(_roles)) ...[
                                ListTile(
                                  leading: Icon(
                                    Icons.add_link,
                                    color: scheme.primary,
                                  ),
                                  title: const Text('Инвайты и регистрация'),
                                  subtitle: const Text(
                                    'Создать токен для нового пользователя',
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: widget.onOpenInvites,
                                ),
                                Divider(
                                    height: 1, color: scheme.outlineVariant),
                              ],
                              if (widget.invitesEligibility != null &&
                                  widget.onOpenDeviceTransferPending != null &&
                                  !_loadingRoles &&
                                  widget.invitesEligibility!(_roles)) ...[
                                ListTile(
                                  leading: Icon(
                                    Icons.phonelink_setup_outlined,
                                    color: scheme.primary,
                                  ),
                                  title: const Text('Запросы смены устройства'),
                                  subtitle: const Text(
                                    'Подтвердить или отклонить вход с нового устройства',
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: widget.onOpenDeviceTransferPending,
                                ),
                                Divider(
                                    height: 1, color: scheme.outlineVariant),
                              ],
                              ListTile(
                                leading: Icon(Icons.history_outlined,
                                    color: scheme.primary),
                                title: const Text('История назначения ролей'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {
                                  Navigator.of(context).push<void>(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          const RoleHistoryPlaceholderScreen(),
                                    ),
                                  );
                                },
                              ),
                              Divider(height: 1, color: scheme.outlineVariant),
                              ListTile(
                                leading: Icon(Icons.settings_outlined,
                                    color: scheme.primary),
                                title: const Text('Настройки'),
                                subtitle: const Text('Тема оформления'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {
                                  Navigator.of(context).pushNamed('/settings');
                                },
                              ),
                              Divider(height: 1, color: scheme.outlineVariant),
                              ListTile(
                                leading: Icon(Icons.developer_mode_outlined,
                                    color: scheme.primary),
                                title: const Text('Сервис и отладка'),
                                subtitle:
                                    const Text('Информация для разработчика'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {
                                  Navigator.of(context).push<void>(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          const DeveloperHubScreen(),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                        FilledButton.tonal(
                          onPressed: widget.onLogout == null || _loggingOut
                              ? null
                              : _logout,
                          style: FilledButton.styleFrom(
                            foregroundColor: scheme.onErrorContainer,
                            backgroundColor: scheme.errorContainer,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            textStyle: textTheme.labelLarge?.copyWith(
                              color: scheme.onErrorContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          child: _loggingOut
                              ? SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: scheme.onErrorContainer,
                                  ),
                                )
                              : const Text('Выйти'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _aboutDisplay(String? about) {
    final t = about?.trim();
    if (t == null || t.isEmpty) return 'Нет описания';
    return t;
  }

  static String _aboutSummary(String? about) {
    final t = about?.trim();
    if (t == null || t.isEmpty) return 'Нет описания';
    if (t.length <= 120) return t;
    return '${t.substring(0, 117)}…';
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.alignTop = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool alignTop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment:
            alignTop ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 22, color: scheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: textTheme.bodyLarge,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
