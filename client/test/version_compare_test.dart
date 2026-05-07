import 'package:flutter_test/flutter_test.dart';
import 'package:lewogram_client/core/version/version_compare.dart';

void main() {
  test('isClientVersionBelowMinimum', () {
    expect(isClientVersionBelowMinimum('0.0.1', '0.0.2'), isTrue);
    expect(isClientVersionBelowMinimum('0.0.2', '0.0.2'), isFalse);
    expect(isClientVersionBelowMinimum('1.0.0', '0.9.9'), isFalse);
    expect(isClientVersionBelowMinimum('0.10.0', '0.9.0'), isFalse);
  });
}
