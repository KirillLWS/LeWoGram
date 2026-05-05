import 'package:flutter/material.dart';
import 'package:lewogram_client/features/owner/data/transfer_ownership_result.dart';
import 'package:lewogram_client/features/owner/presentation/owner_chats_tab.dart';
import 'package:lewogram_client/features/owner/presentation/owner_users_tab.dart';
import 'package:lewogram_client/features/owner/presentation/transfer_ownership_dialog.dart';

/// Меню владельца: вкладки «Пользователи» и «Чаты».
class OwnerMenuScreen extends StatefulWidget {
  const OwnerMenuScreen({
    super.key,
    this.onJoinChatAsParticipant,
    this.onTransferOwnership,
  });

  /// Вступить в чат как обычный участник (отдельно от режима модерации).
  final void Function(String chatId)? onJoinChatAsParticipant;

  /// Подтверждение передачи владения из диалога.
  final void Function(TransferOwnershipResult result)? onTransferOwnership;

  @override
  State<OwnerMenuScreen> createState() => _OwnerMenuScreenState();
}

class _OwnerMenuScreenState extends State<OwnerMenuScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _openTransferDialog() async {
    final result = await showTransferOwnershipDialog(context);
    if (result != null && mounted) {
      widget.onTransferOwnership?.call(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Владелец',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Передать владение',
            onPressed:
                widget.onTransferOwnership == null ? null : _openTransferDialog,
            icon: const Icon(Icons.swap_horiz),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Пользователи'),
            Tab(text: 'Чаты'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          const OwnerUsersTab(),
          OwnerChatsTab(
            onJoinAsParticipant: widget.onJoinChatAsParticipant,
          ),
        ],
      ),
    );
  }
}
