import 'package:flutter/material.dart';

import '../../reports/data/report_models.dart';
import '../data/sanction_models.dart';

typedef ResolveReportCallback = Future<void> Function(
  Report report,
  String resolutionNote,
);

typedef RejectReportCallback = Future<void> Function(
  Report report,
  String rejectionReason,
);

typedef SanctionReportCallback = Future<void> Function(
  Report report,
  Sanction sanction,
);

/// Детали жалобы: формы-заглушки для решения, отклонения и санкции.
class ReportDetailScreen extends StatefulWidget {
  const ReportDetailScreen({
    super.key,
    required this.report,
    required this.onResolve,
    required this.onReject,
    required this.onSanction,
  });

  final Report report;
  final ResolveReportCallback onResolve;
  final RejectReportCallback onReject;
  final SanctionReportCallback onSanction;

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  final _resolveNote = TextEditingController();
  final _rejectReason = TextEditingController();
  final _sanctionReason = TextEditingController();
  SanctionKind _sanctionKind = SanctionKind.warning;
  int _muteHours = 24;

  @override
  void dispose() {
    _resolveNote.dispose();
    _rejectReason.dispose();
    _sanctionReason.dispose();
    super.dispose();
  }

  bool _busy = false;

  Future<void> _guard(Future<void> Function() fn) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await fn();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Sanction _buildSanction() {
    final reason = _sanctionReason.text.trim();
    return Sanction(
      kind: _sanctionKind,
      reason: reason.isEmpty ? null : reason,
      duration: _sanctionKind == SanctionKind.mute
          ? Duration(hours: _muteHours)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    return Scaffold(
      appBar: AppBar(
        title: Text('Report #${r.id}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            r.summary,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text('Status: ${r.statusLabel}'),
          if (r.details != null && r.details!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(r.details!, style: Theme.of(context).textTheme.bodyMedium),
          ],
          const SizedBox(height: 24),
          _ResolveSection(
            controller: _resolveNote,
            busy: _busy,
            onSubmit: () => _guard(() async {
              await widget.onResolve(r, _resolveNote.text.trim());
            }),
          ),
          const SizedBox(height: 24),
          _RejectSection(
            controller: _rejectReason,
            busy: _busy,
            onSubmit: () => _guard(() async {
              await widget.onReject(r, _rejectReason.text.trim());
            }),
          ),
          const SizedBox(height: 24),
          _SanctionSection(
            kind: _sanctionKind,
            muteHours: _muteHours,
            reasonController: _sanctionReason,
            busy: _busy,
            onKindChanged: (k) => setState(() => _sanctionKind = k),
            onMuteHoursChanged: (h) => setState(() => _muteHours = h),
            onSubmit: () => _guard(() async {
              await widget.onSanction(r, _buildSanction());
            }),
          ),
        ],
      ),
    );
  }
}

class _ResolveSection extends StatelessWidget {
  const _ResolveSection({
    required this.controller,
    required this.busy,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Resolve', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Resolution note',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              enabled: !busy,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: busy ? null : onSubmit,
              child: const Text('Resolve'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RejectSection extends StatelessWidget {
  const _RejectSection({
    required this.controller,
    required this.busy,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Reject', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Rejection reason',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              enabled: !busy,
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: busy ? null : onSubmit,
              child: const Text('Reject'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SanctionSection extends StatelessWidget {
  const _SanctionSection({
    required this.kind,
    required this.muteHours,
    required this.reasonController,
    required this.busy,
    required this.onKindChanged,
    required this.onMuteHoursChanged,
    required this.onSubmit,
  });

  final SanctionKind kind;
  final int muteHours;
  final TextEditingController reasonController;
  final bool busy;
  final ValueChanged<SanctionKind> onKindChanged;
  final ValueChanged<int> onMuteHoursChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Sanction', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            DropdownButtonFormField<SanctionKind>(
              key: ValueKey(kind),
              initialValue: kind,
              decoration: const InputDecoration(
                labelText: 'Kind',
                border: OutlineInputBorder(),
              ),
              items: SanctionKind.values
                  .map(
                    (k) => DropdownMenuItem(
                      value: k,
                      child: Text(_kindLabel(k)),
                    ),
                  )
                  .toList(),
              onChanged: busy
                  ? null
                  : (v) {
                      if (v != null) onKindChanged(v);
                    },
            ),
            if (kind == SanctionKind.mute) ...[
              const SizedBox(height: 12),
              TextFormField(
                initialValue: '$muteHours',
                decoration: const InputDecoration(
                  labelText: 'Mute duration (hours)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                enabled: !busy,
                onChanged: (s) {
                  final parsed = int.tryParse(s.trim());
                  if (parsed != null && parsed > 0) {
                    onMuteHoursChanged(parsed);
                  }
                },
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
              enabled: !busy,
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: busy ? null : onSubmit,
              child: const Text('Apply sanction'),
            ),
          ],
        ),
      ),
    );
  }

  static String _kindLabel(SanctionKind k) => switch (k) {
        SanctionKind.warning => 'Warning',
        SanctionKind.mute => 'Mute',
        SanctionKind.ban => 'Ban',
        SanctionKind.contentRemoval => 'Remove content',
      };
}
