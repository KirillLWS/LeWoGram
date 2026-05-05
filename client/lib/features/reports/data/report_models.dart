/// Жалобы и статусы модерации — локальные модели фичи `reports`.
library;

/// Статус обработки жалобы.
enum ReportStatus {
  open,
  inReview,
  resolved,
  rejected,
  escalated,
}

/// Жалоба для списка и карточки деталей.
class Report {
  const Report({
    required this.id,
    required this.status,
    required this.summary,
    this.createdAt,
    this.subjectUserId,
    this.reporterUserId,
    this.details,
  });

  final int id;
  final ReportStatus status;
  final String summary;
  final DateTime? createdAt;
  final int? subjectUserId;
  final int? reporterUserId;
  final String? details;

  String get statusLabel => switch (status) {
        ReportStatus.open => 'Open',
        ReportStatus.inReview => 'In review',
        ReportStatus.resolved => 'Resolved',
        ReportStatus.rejected => 'Rejected',
        ReportStatus.escalated => 'Escalated',
      };
}
