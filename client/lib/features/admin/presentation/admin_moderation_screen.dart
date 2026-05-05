import 'package:flutter/material.dart';

import '../../moderation/presentation/report_detail_screen.dart';
import '../../reports/data/report_models.dart';
import '../../reports/presentation/reports_list_screen.dart';

/// Обёртка: список жалоб → деталь с действиями модератора (колбэки снаружи).
///
/// Подключение к API — через [onLoadReports], [onResolve], [onReject], [onSanction].
class AdminModerationScreen extends StatelessWidget {
  const AdminModerationScreen({
    super.key,
    required this.onLoadReports,
    required this.onResolve,
    required this.onReject,
    required this.onSanction,
    this.listTitle = 'Moderation',
  });

  final ReportsLoadCallback onLoadReports;
  final ResolveReportCallback onResolve;
  final RejectReportCallback onReject;
  final SanctionReportCallback onSanction;
  final String listTitle;

  void _openDetail(BuildContext context, Report report) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => ReportDetailScreen(
          report: report,
          onResolve: onResolve,
          onReject: onReject,
          onSanction: onSanction,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ReportsListScreen(
      title: listTitle,
      onLoad: onLoadReports,
      onOpenReport: _openDetail,
    );
  }
}
