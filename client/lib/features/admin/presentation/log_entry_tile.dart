import 'dart:convert';

import 'package:flutter/material.dart';

/// Универсальная плитка лога: краткая строка-резюме + раскрывающийся блок с JSON/деталями.
///
/// [title] — основной заголовок (например `#42 · login_success`).
/// [subtitle] — мета (время, user_id и т. п.) одной строкой.
/// [summary] — однострочное превью body/payload (обрезается).
/// [details] — карта/строка/значение для развёрнутого вида (форматируется как JSON, если Map/List).
class LogEntryTile extends StatelessWidget {
  const LogEntryTile({
    super.key,
    required this.title,
    this.subtitle,
    this.summary,
    this.details,
    this.titleColor,
  });

  final String title;
  final String? subtitle;
  final String? summary;
  final Object? details;
  final Color? titleColor;

  static String _formatDetails(Object? d) {
    if (d == null) return '';
    if (d is String) {
      final s = d.trim();
      if (s.isEmpty) return '';
      try {
        final decoded = jsonDecode(s);
        return const JsonEncoder.withIndent('  ').convert(decoded);
      } catch (_) {
        return s;
      }
    }
    if (d is Map || d is List) {
      try {
        return const JsonEncoder.withIndent('  ').convert(d);
      } catch (_) {
        return d.toString();
      }
    }
    return d.toString();
  }

  /// Делает однострочное превью из произвольного значения (схлопывает пробелы и обрезает).
  static String detailsToOneLine(Object? d) => _oneLine(d);

  static String _oneLine(Object? d) {
    if (d == null) return '';
    final s = d is String ? d : d.toString();
    final flat = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.length <= 160) return flat;
    return '${flat.substring(0, 157)}…';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final detailsText = _formatDetails(details);
    final hasDetails = detailsText.isNotEmpty;

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.labelMedium?.copyWith(
            color: titleColor ?? cs.primary,
          ),
        ),
        if (subtitle != null && subtitle!.isNotEmpty)
          Text(subtitle!, style: theme.textTheme.bodySmall),
        if (summary != null && summary!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            summary!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ],
    );

    if (!hasDetails) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: header,
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        title: header,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              detailsText,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
