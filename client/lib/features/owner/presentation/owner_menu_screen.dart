import 'package:flutter/material.dart';
import 'package:lewogram_client/app/app_scope.dart';
import 'package:lewogram_client/features/admin/presentation/admin_hub_screen.dart';
import 'package:lewogram_client/features/developer/presentation/developer_hub_screen.dart';
import 'package:lewogram_client/features/owner/presentation/owner_chats_tab.dart';
import 'package:lewogram_client/features/owner/presentation/owner_users_tab.dart';

/// Меню владельца: пользователи, чаты и админ-инструменты (superset внутри Owner).
class OwnerMenuScreen extends StatefulWidget {
  const OwnerMenuScreen({
    super.key,
    this.onJoinChatAsParticipant,
  });

  /// Вступить в чат как обычный участник (отдельно от режима модерации).
  final void Function(String chatId)? onJoinChatAsParticipant;

  @override
  State<OwnerMenuScreen> createState() => _OwnerMenuScreenState();
}

class _OwnerMenuScreenState extends State<OwnerMenuScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final api = AppScope.of(context).apiClient;

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
          tabs: const [
            Tab(text: 'Пользователи'),
            Tab(text: 'Чаты'),
            Tab(text: 'Админ'),
            Tab(text: 'Dev'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          const OwnerUsersTab(),
          OwnerChatsTab(
            apiClient: api,
            onJoinAsParticipant: widget.onJoinChatAsParticipant,
          ),
          const AdminHubBody(),
          const DeveloperHubBody(),
        ],
      ),
    );
  }
}
