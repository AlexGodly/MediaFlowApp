import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/platform/device_report.dart';

void main() {
  const day = 24 * 60 * 60 * 1000;
  test('writes a new entry, nothing while current, again on a new version or after a day', () {
    final first = DeviceReport.entryToWrite(null, version: '6.0.0.565', now: 1000)!;
    expect(first['version'], '6.0.0.565');
    expect(first['platform'], DeviceReport.platform);
    expect(first['lastSeen'], 1000);
    expect(DeviceReport.entryToWrite(first, version: '6.0.0.565', now: 1000 + day - 1), isNull);
    expect(DeviceReport.entryToWrite(first, version: '6.0.1.565', now: 2000), isNotNull);
    expect(DeviceReport.entryToWrite(first, version: '6.0.0.565', now: 1000 + day), isNotNull);
  });
}
