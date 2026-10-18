import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/features/full_app/full_mediaflow_screen.dart';

void main() {
  test('full application uses the real MediaFlow HTTPS origin', () {
    final url = MediaFlowWebConfig.startUri;
    expect(url.scheme, 'https');
    expect(url.host, 'alexgodly.github.io');
    expect(url.path, '/MediaFlow/');
    expect(url.userInfo, isEmpty);
    expect(url.query, isEmpty);
  });

  test('full application does not use the old v410 preview URL', () {
    expect(MediaFlowWebConfig.productionUrl,
        'https://alexgodly.github.io/MediaFlow/');
    expect(MediaFlowWebConfig.startUri.toString(),
        MediaFlowWebConfig.productionUrl);
  });
}
