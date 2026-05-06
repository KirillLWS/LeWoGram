import 'package:flutter/material.dart';
import 'package:lewogram_client/app/app_scope.dart';
import 'package:lewogram_client/core/storage/account_storage.dart';
import 'package:lewogram_client/features/admin/presentation/admin_hub_screen.dart';
import 'package:lewogram_client/features/developer/presentation/developer_hub_screen.dart';
import 'package:lewogram_client/features/owner/presentation/owner_chats_tab.dart';
import 'package:lewogram_client/features/owner/presentation/owner_users_tab.dart';

/// Меню владельца: пользователи, (только owner) чаты, админ, Dev.
class OwnerMenuScreen extends StatefulWidget {
  const OwnerMenuScreen({
    super.key,
    this.onJoinChatAsParticipant,
  });

  final void Function(String chatId)? onJoinChatAsParticipant;

  @override
  State<OwnerMenuScreen> createState() => _OwnerMenuScreenState();
}

class _OwnerMenuScreenState extends State<OwnerMenuScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  bool _loaded = false;
  bool _isOwner = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final me = await AccountStorage.read();
    final primary = me?['primary_role']?.toString().trim();
    final owner = primary == 'owner';
    if (!mounted) return;
    _tabController?.dispose();
    _tabController = TabController(
      length: owner ? 4 : 3,
      vsync: this,
    );
    setState(() {
      _isOwner = owner;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final api = AppScope.of(context).apiClient;

    if (!_loaded || _tabController == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Владелец')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final tabs = _isOwner
        ? const [
            Tab(text: 'Пользователи'),
            Tab(text: 'Чаты'),
            Tab(text: 'Админ'),
            Tab(text: 'Dev'),
          ]
        : const [
            Tab(text: 'Пользователи'),
            Tab(text: 'Админ'),
            Tab(text: 'Dev'),
          ];

    final bodies = _isOwner
        ? [
            const OwnerUsersTab(),
            OwnerChatsTab(
              apiClient: api,
              onJoinAsParticipant: widget.onJoinChatAsParticipant,
            ),
            const AdminHubBody(),
            const DeveloperHubBody(),
          ]
        : [
            const OwnerUsersTab(),
            const AdminHubBody(),
            const DeveloperHubBody(),
          ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Владелец',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: tabs,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: bodies,
      ),
    );
  }
}
