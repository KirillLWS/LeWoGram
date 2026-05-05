/// Санкции — локальные модели фичи `moderation`.
library;

/// Тип санкции к объекту жалобы.
enum SanctionKind {
  warning,
  mute,
  ban,
  contentRemoval,
}

/// Санкция, собранная из формы (заглушка до интеграции с API).
class Sanction {
  const Sanction({
    required this.kind,
    this.reason,
    this.duration,
  });

  final SanctionKind kind;
  final String? reason;

  /// Для временных мутов и т.п.; null — «навсегда» или не применимо.
  final Duration? duration;

  String get kindLabel => switch (kind) {
        SanctionKind.warning => 'Warning',
        SanctionKind.mute => 'Mute',
        SanctionKind.ban => 'Ban',
        SanctionKind.contentRemoval => 'Remove content',
      };
}
