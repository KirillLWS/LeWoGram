/// Сравнение semver вида `x.y.z` (части по необходимости дополняются нулями).
bool isClientVersionBelowMinimum(String current, String minimum) {
  final c = _normParts(current);
  final m = _normParts(minimum);
  for (var i = 0; i < 3; i++) {
    if (c[i] < m[i]) return true;
    if (c[i] > m[i]) return false;
  }
  return false;
}

List<int> _normParts(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return [0, 0, 0];
  final chunks = s.split(RegExp(r'[^0-9]+')).where((e) => e.isNotEmpty).toList();
  final a = <int>[];
  for (final chunk in chunks.take(3)) {
    a.add(int.tryParse(chunk) ?? 0);
  }
  while (a.length < 3) {
    a.add(0);
  }
  return a;
}
