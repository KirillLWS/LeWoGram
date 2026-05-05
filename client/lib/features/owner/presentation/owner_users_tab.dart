import 'package:flutter/material.dart';
import 'package:lewogram_client/features/admin/presentation/staff_users_screen.dart';

/// Вкладка «Пользователи»: полный список пользователей сервера (staff API).
class OwnerUsersTab extends StatelessWidget {
  const OwnerUsersTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const StaffUsersListView();
  }
}
