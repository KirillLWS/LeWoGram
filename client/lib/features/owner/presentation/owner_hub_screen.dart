import 'package:flutter/material.dart';

/// Заглушка: раздел владельца (этап позже).
class OwnerHubScreen extends StatelessWidget {
  const OwnerHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Владелец')),
      body: const Center(child: Text('Раздел в разработке')),
    );
  }
}
