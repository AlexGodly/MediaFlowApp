import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/config.dart';

void main() {
  test('update check compares version numbers', () {
    expect(isNewerVersion('mediaflowapp-v2.0.0.560', '1.2.0'), isTrue);
    expect(isNewerVersion('mediaflowapp-v2.0.0.560', '2.0.0.560'), isFalse);
    expect(isNewerVersion('mediaflowapp-v2.0.1.560', '2.0.0.560'), isTrue);
    expect(isNewerVersion('mediaflowapp-v2.0.0.561', '2.0.0.560'), isTrue);
    expect(isNewerVersion('mediaflowapp-v2.1.0.560', '2.0.9.560'), isTrue);
    expect(isNewerVersion('mediaflowapp-v1.2.0', '2.0.0.560'), isFalse);
    expect(isNewerVersion('mediaflowapp-v1.0.0-beta.16', '2.0.0.560'), isFalse);
  });
}
