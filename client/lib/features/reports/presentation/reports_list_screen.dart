import 'package:flutter/material.dart';

import '../data/report_models.dart';

/// Загрузить список жалоб; [statusFilter] — null означает «все статусы».
typedef ReportsLoadCallback = Future<List<Report>> Function(
  ReportStatus? statusFilter,
);

/// Список жалоб с фильтром по статусу.
class ReportsListScreen extends StatefulWidget {
  const ReportsListScreen({
    super.key,
    required this.onLoad,
    this.onOpenReport,
    this.title = 'Reports',
  });

  final ReportsLoadCallback onLoad;

  /// Открыть деталь (например, push к [ReportDetailScreen]).
  final void Function(BuildContext context, Report report)? onOpenReport;

  final String title;

  @override
  State<ReportsListScreen> createState() => _ReportsListScreenState();
}

class _ReportsListScreenState extends State<ReportsListScreen> {
  ReportStatus? _filter;
  List<Report> _items = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.onLoad(_filter);
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _setFilter(ReportStatus? next) {
    if (_filter == next) return;
    setState(() => _filter = next);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: _filter == null,
                  onSelected: (_) => _setFilter(null),
                ),
                for (final s in ReportStatus.values)
                  FilterChip(
                    label: Text(_statusChipLabel(s)),
                    selected: _filter == s,
                    onSelected: (_) => _setFilter(s),
                  ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: _loading && _items.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? const Center(child: Text('No reports'))
                    : ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final r = _items[i];
                          return ListTile(
                            title: Text(r.summary),
                            subtitle: Text(
                              '${r.statusLabel}'
                              '${r.createdAt != null ? ' · ${_formatDate(r.createdAt!)}' : ''}',
                            ),
                            trailing: Icon(
                              Icons.chevron_right,
                              color: Theme.of(context).disabledColor,
                            ),
                            onTap: () {
                              final open = widget.onOpenReport;
                              if (open != null) {
                                open(context, r);
                              }
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  static String _statusChipLabel(ReportStatus s) => switch (s) {
        ReportStatus.open => 'Open',
        ReportStatus.inReview => 'Review',
        ReportStatus.resolved => 'Resolved',
        ReportStatus.rejected => 'Rejected',
        ReportStatus.escalated => 'Escalated',
      };

  static String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
