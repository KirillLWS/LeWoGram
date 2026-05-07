import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lewogram_client/app/app_scope.dart';
import 'package:lewogram_client/core/network/api_client.dart';

/// Загрузка APK на сервер (POST /admin/client-apk) — только chief_admin / owner.
class ClientApkUploadScreen extends StatefulWidget {
  const ClientApkUploadScreen({super.key});

  @override
  State<ClientApkUploadScreen> createState() => _ClientApkUploadScreenState();
}

class _ClientApkUploadScreenState extends State<ClientApkUploadScreen> {
  bool _uploading = false;

  Future<void> _pickAndUpload() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['apk'],
      withData: false,
    );
    if (result == null || result.files.isEmpty || !mounted) return;

    final f = result.files.single;
    final path = f.path?.trim();
    if (path == null || path.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Не удалось получить путь к файлу. Попробуйте другой способ выбора.',
          ),
        ),
      );
      return;
    }

    if (!path.toLowerCase().endsWith('.apk')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нужен файл с расширением .apk')),
      );
      return;
    }

    setState(() => _uploading = true);

    final api = AppScope.of(context).apiClient;
    try {
      await api.uploadClientApk(File(path));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'APK загружен (${f.name}). Пользователи скачивают его по адресу из /client/requirements.',
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Обновление клиента (APK)'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Загрузка APK на сервер',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Файл сохраняется в каталог releases и раздаётся по apk_url из '
                    'GET /client/requirements. После загрузки поднимите MIN_CLIENT_VERSION '
                    'на сервере и соберите клиент с новым version в pubspec.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _uploading ? null : _pickAndUpload,
                    icon: _uploading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_file),
                    label: Text(
                      _uploading ? 'Загрузка…' : 'Выбрать APK и загрузить',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
