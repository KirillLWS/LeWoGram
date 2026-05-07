import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:lewogram_client/core/config/app_config.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Блокирующий экран: версия ниже минимальной.
/// После появления автоматически скачивает APK и открывает системный установщик.
class UpdateRequiredScreen extends StatefulWidget {
  const UpdateRequiredScreen({
    super.key,
    required this.currentVersion,
    required this.minimumVersion,
    required this.apkUrlOrPath,
    required this.infoUrl,
  });

  final String currentVersion;
  final String minimumVersion;
  /// Путь `/releases/...` на базовом URL или полный `http(s)://`.
  final String apkUrlOrPath;
  /// Опционально: страница с описанием релиза.
  final String infoUrl;

  @override
  State<UpdateRequiredScreen> createState() => _UpdateRequiredScreenState();
}

class _UpdateRequiredScreenState extends State<UpdateRequiredScreen> {
  bool _busy = false;
  bool _autoStarted = false;

  Uri? _resolveApkUri() {
    final t = widget.apkUrlOrPath.trim();
    if (t.isEmpty) return null;
    if (t.startsWith('http://') || t.startsWith('https://')) {
      return Uri.tryParse(t);
    }
    final base = AppConfig.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final p = t.startsWith('/') ? t : '/$t';
    return Uri.tryParse('$base$p');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _autoStarted) return;
      if (_resolveApkUri() != null) {
        _autoStarted = true;
        _downloadAndInstall();
      }
    });
  }

  Future<void> _openInfoUrl() async {
    final u = Uri.tryParse(widget.infoUrl.trim());
    if (u == null) return;
    await launchUrl(u, mode: LaunchMode.externalApplication);
  }

  Future<void> _downloadAndInstall() async {
    final uri = _resolveApkUri();
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не задан URL APK на сервере')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final resp = await http.get(uri).timeout(const Duration(minutes: 5));
      if (!mounted) return;
      if (resp.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Не удалось скачать APK (HTTP ${resp.statusCode}). '
              'Проверьте, что файл загружен на сервер.',
            ),
          ),
        );
        return;
      }
      if (resp.bodyBytes.length < 2048) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Скачанный файл слишком мал — не похоже на APK'),
          ),
        );
        return;
      }

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/lewo_update.apk');
      await file.writeAsBytes(resp.bodyBytes, flush: true);

      final result = await OpenFile.open(file.path);
      if (!mounted) return;
      if (result.type != ResultType.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Установщик: ${result.message}')),
        );
      }
    } on SocketException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Сеть: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasApk = widget.apkUrlOrPath.trim().isNotEmpty;
    final hasInfo = widget.infoUrl.trim().isNotEmpty;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.system_update_alt, size: 56, color: cs.primary),
                const SizedBox(height: 24),
                Text(
                  'Требуется обновление',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'Установленная версия ${widget.currentVersion} ниже минимальной '
                  '${widget.minimumVersion}. Загрузка нового APK начинается автоматически; '
                  'после скачивания откроется установщик Android — подтвердите установку '
                  '(полностью «тихую» установку без этого шага обычное приложение сделать не может).',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
                if (hasApk)
                  Text(
                    'Источник: ${_resolveApkUri()}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                if (_busy) ...[
                  const SizedBox(height: 24),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(
                    'Скачивание…',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
                const Spacer(),
                if (hasApk)
                  FilledButton.icon(
                    onPressed: _busy ? null : _downloadAndInstall,
                    icon: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: Text(
                      _busy ? 'Подождите…' : 'Повторить загрузку и установку',
                    ),
                  ),
                if (hasApk && hasInfo) const SizedBox(height: 12),
                if (hasInfo)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _openInfoUrl,
                    icon: const Icon(Icons.info_outline),
                    label: const Text('Описание релиза'),
                  ),
                if (!hasApk && !hasInfo)
                  Text(
                    'На сервере не настроены apk_url и update_url — '
                    'обратитесь к администратору.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: cs.error,
                        ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
