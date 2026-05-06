import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lewogram_client/app/app_scope.dart';
import 'package:lewogram_client/core/network/api_client.dart';
import 'package:lewogram_client/core/permissions/permissions_service.dart';
import 'package:lewogram_client/core/permissions/role_access.dart';
import 'package:lewogram_client/core/push/push_service.dart';
import 'package:lewogram_client/core/storage/account_storage.dart';
import 'package:lewogram_client/features/admin/presentation/admin_hub_screen.dart';
import 'package:lewogram_client/features/chat/presentation/chat_list_screen.dart';
import 'package:lewogram_client/features/chat/presentation/chat_screen.dart';
import 'package:lewogram_client/features/developer/presentation/developer_hub_screen.dart';
import 'package:lewogram_client/features/friends/presentation/friends_screen.dart';
import 'package:lewogram_client/features/owner/presentation/owner_hub_screen.dart';
import 'package:lewogram_client/features/profile/presentation/profile_screen.dart';
import 'package:lewogram_client/features/users/data/user_public_profile.dart';
import 'package:lewogram_client/features/users/data/user_search_result.dart';
import 'package:lewogram_client/features/users/presentation/user_search_screen.dart';

List<String> _parseRolesFromMe(Map<String, dynamic> m) {
  final r = m['roles'];
  if (r is List) {
    return r.map((e) => e.toString()).toList();
  }
  return <String>[];
}

String? _parsePrimaryRoleFromMe(Map<String, dynamic> m) {
  final p = m['primary_role'];
  if (p == null) return null;
  final s = p.toString().trim();
  return s.isEmpty ? null : s;
}

List<String> _rolesListFromMe(Map<String, dynamic> m) {
  final primary = _parsePrimaryRoleFromMe(m);
  if (primary != null && primary.trim().isNotEmpty) {
    return [primary.trim()];
  }
  return _parseRolesFromMe(m);
}

class _NavTab {
  const _NavTab({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.builder,
    required this.visibleFor,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final Widget Function() builder;
  final bool Function(List<String> roles) visibleFor;
}

/// Авторизованная оболочка: нижняя навигация по ролям из [/auth/me].
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  List<String> _roles = <String>[];
  String? _serverPrimaryRole;
  bool _initialized = false;

  /// Число входящих заявок в друзья (бейдж на вкладке «Друзья»).
  final ValueNotifier<int> _friendsIncomingCount = ValueNotifier<int>(0);

  /// Кэш страниц: пересобираем только при смене набора вкладок (подпись по label).
  String? _pagesCacheKey;
  List<Widget>? _cachedPages;

  Future<void> _syncIncomingCount(ApiClient api) async {
    try {
      final list = await api.friendsIncoming();
      if (!mounted) return;
      _friendsIncomingCount.value = list.length;
    } catch (e, st) {
      assert(() {
        debugPrint('friendsIncoming: $e\n$st');
        return true;
      }());
    }
  }

  List<_NavTab> _tabDefinitions(
    BuildContext context,
    AppScope scope,
    String? serverPrimaryRole,
  ) {
    final api = scope.apiClient;
    return <_NavTab>[
      _NavTab(
        icon: Icons.chat_bubble_outline,
        selectedIcon: Icons.chat_bubble,
        label: 'Чаты',
        visibleFor: (_) => true,
        builder: () => ChatListScreen(
          apiClient: api,
          onStartChat: () {
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (ctx) => UserSearchScreen(
                  apiClient: api,
                  onSearch: (q) async {
                    final raw = await api.searchUsers(q);
                    return raw
                        .map(
                          (e) => UserSearchResult.fromJson(
                            Map<String, dynamic>.from(e as Map),
                          ),
                        )
                        .toList();
                  },
                  onWrite: (otherId) async {
                    final chat = await api.createDirectChat(otherId);
                    if (!ctx.mounted) return;
                    Navigator.of(ctx).pop();
                    if (!ctx.mounted) return;
                    final chatId = (chat['id'] as num).toInt();
                    await Navigator.of(ctx).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => ChatScreen(
                          chatId: chatId,
                          apiClient: api,
                          chatType: 'direct',
                          peerUserId: otherId,
                        ),
                      ),
                    );
                  },
                  loadPublicProfile: (id) async {
                    final m = await api.getUserPublic(id);
                    return UserPublicProfile.fromJson(m);
                  },
                ),
              ),
            );
          },
        ),
      ),
      _NavTab(
        icon: Icons.people_outline,
        selectedIcon: Icons.people,
        label: 'Друзья',
        visibleFor: (_) => true,
        builder: () => FriendsScreen(
          apiClient: api,
          incomingBadgeNotifier: _friendsIncomingCount,
        ),
      ),
      _NavTab(
        icon: Icons.person_outline,
        selectedIcon: Icons.person,
        label: 'Профиль',
        visibleFor: (_) => true,
        builder: () => ProfileScreen(
          apiClient: api,
          loadRoles: () async {
            try {
              final m = await api.getMe();
              return _rolesListFromMe(m);
            } on ApiException catch (_) {
              return List<String>.from(_roles);
            } on UnauthorizedException catch (_) {
              return List<String>.from(_roles);
            } catch (_) {
              return List<String>.from(_roles);
            }
          },
          invitesEligibility: (roles) => RoleAccess.canManageInvitesAndDeviceTransfers(
            roles,
            serverPrimaryRole: serverPrimaryRole,
          ),
          onOpenInvites: () {
            Navigator.of(context).pushNamed('/invites');
          },
          onOpenDeviceTransferPending: () {
            Navigator.of(context).pushNamed('/device-transfers-admin');
          },
          onPickAvatar: () async {
            final messenger = ScaffoldMessenger.of(context);
            final sheetCtx = context;
            final source = await showModalBottomSheet<ImageSource>(
              context: sheetCtx,
              builder: (ctx) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.photo_camera_outlined),
                      title: const Text('Камера'),
                      onTap: () => Navigator.pop(ctx, ImageSource.camera),
                    ),
                    ListTile(
                      leading: const Icon(Icons.photo_library_outlined),
                      title: const Text('Галерея'),
                      onTap: () => Navigator.pop(ctx, ImageSource.gallery),
                    ),
                  ],
                ),
              ),
            );
            if (source == null) return null;
            final permSvc = PermissionsService();
            final ok = source == ImageSource.camera
                ? await permSvc.request(AppPermission.camera)
                : await permSvc.request(AppPermission.photos);
            if (!ok) {
              if (context.mounted) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      source == ImageSource.camera
                          ? 'Разрешите доступ к камере'
                          : 'Разрешите доступ к фото',
                    ),
                  ),
                );
              }
              return null;
            }
            final picker = ImagePicker();
            final x = await picker.pickImage(source: source, imageQuality: 85);
            return x?.path;
          },
          onAvatarPicked: (localPath) async {
            await api.uploadAvatar(File(localPath));
          },
          onSaveProfile: (displayName, username, about) async {
            await api.patchMe(
              displayName: displayName,
              username: username,
              about: about,
            );
          },
          onLogout: () async {
            await scope.tokenStorage.clearToken();
            await AccountStorage.clear();
            if (!context.mounted) return;
            Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
          },
        ),
      ),
      _NavTab(
        icon: Icons.admin_panel_settings_outlined,
        selectedIcon: Icons.admin_panel_settings,
        label: 'Админ',
        visibleFor: (roles) => RoleAccess.showAdminNav(
          roles,
          serverPrimaryRole: serverPrimaryRole,
        ),
        builder: () => const AdminHubScreen(),
      ),
      _NavTab(
        icon: Icons.verified_user_outlined,
        selectedIcon: Icons.verified_user,
        label: 'Владелец',
        visibleFor: (roles) => RoleAccess.showOwnerNav(
          roles,
          serverPrimaryRole: serverPrimaryRole,
        ),
        builder: () => const OwnerHubScreen(),
      ),
      _NavTab(
        icon: Icons.developer_mode_outlined,
        selectedIcon: Icons.developer_mode,
        label: 'Dev',
        visibleFor: (roles) => RoleAccess.showDeveloperNav(
          roles,
          serverPrimaryRole: serverPrimaryRole,
        ),
        builder: () => const DeveloperHubScreen(),
      ),
    ];
  }

  List<_NavTab> _visibleTabs(List<String> roles, String? serverPrimaryRole) {
    final scope = AppScope.of(context);
    return _tabDefinitions(context, scope, serverPrimaryRole)
        .where((t) => t.visibleFor(roles))
        .toList();
  }

  void _invalidatePagesCache() {
    _pagesCacheKey = null;
    _cachedPages = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _bootstrap();
    });
  }

  @override
  void dispose() {
    _friendsIncomingCount.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final scope = AppScope.of(context);
    final api = scope.apiClient;
    PushService.initAndGetToken(api);
    try {
      final m = await api.getMe();
      if (!mounted) return;
      await AccountStorage.upsert(m);
      final primary = _parsePrimaryRoleFromMe(m);
      final next = _rolesListFromMe(m);
      setState(() {
        _roles = next;
        _serverPrimaryRole = primary;
        final visible = _visibleTabs(next, _serverPrimaryRole);
        _index = visible.isEmpty ? 0 : _index.clamp(0, visible.length - 1);
        _invalidatePagesCache();
      });
      await _syncIncomingCount(api);
    } on ApiException catch (_) {
      if (!mounted) return;
      setState(() {
        _roles = <String>[];
        _serverPrimaryRole = null;
        final visible = _visibleTabs(_roles, _serverPrimaryRole);
        _index = visible.isEmpty ? 0 : _index.clamp(0, visible.length - 1);
        _invalidatePagesCache();
      });
    } on UnauthorizedException catch (_) {
      if (!mounted) return;
      setState(() {
        _roles = <String>[];
        _serverPrimaryRole = null;
        final visible = _visibleTabs(_roles, _serverPrimaryRole);
        _index = visible.isEmpty ? 0 : _index.clamp(0, visible.length - 1);
        _invalidatePagesCache();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _roles = <String>[];
        _serverPrimaryRole = null;
        final visible = _visibleTabs(_roles, _serverPrimaryRole);
        _index = visible.isEmpty ? 0 : _index.clamp(0, visible.length - 1);
        _invalidatePagesCache();
      });
    }
  }

  Widget _badgedNavIcon(IconData icon) {
    return ValueListenableBuilder<int>(
      valueListenable: _friendsIncomingCount,
      builder: (_, count, __) {
        if (count <= 0) return Icon(icon);
        return Badge(
          isLabelVisible: true,
          label: Text('$count'),
          child: Icon(icon),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final api = scope.apiClient;
    final tabs = _visibleTabs(_roles, _serverPrimaryRole);
    final tabSig = tabs.map((e) => e.label).join('|');

    if (_pagesCacheKey != tabSig || _cachedPages == null) {
      _pagesCacheKey = tabSig;
      _cachedPages = tabs.map((t) => t.builder()).toList();
    }

    final n = tabs.length;
    final safeIndex = n == 0 ? 0 : _index.clamp(0, n - 1);
    if (safeIndex != _index) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _index = safeIndex);
      });
    }

    return Scaffold(
      body: IndexedStack(
        key: ValueKey<String>(tabSig),
        index: safeIndex,
        children: _cachedPages!,
      ),
      bottomNavigationBar: DefaultTextStyle.merge(
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        child: NavigationBar(
          selectedIndex: safeIndex,
          onDestinationSelected: (i) {
            setState(() => _index = i);
            if (i < tabs.length && tabs[i].label == 'Друзья') {
              unawaited(_syncIncomingCount(api));
            }
          },
          destinations: [
            for (final t in tabs)
              NavigationDestination(
                icon: t.label == 'Друзья' ? _badgedNavIcon(t.icon) : Icon(t.icon),
                selectedIcon:
                    t.label == 'Друзья' ? _badgedNavIcon(t.selectedIcon) : Icon(t.selectedIcon),
                label: t.label,
              ),
          ],
        ),
      ),
    );
  }
}
