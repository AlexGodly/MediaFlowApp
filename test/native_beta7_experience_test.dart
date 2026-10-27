import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/app/mediaflow_shell.dart';
import 'package:mediaflow_app/data/mediaflow_library_repository.dart';
import 'package:mediaflow_app/design_system/mediaflow_ambience.dart';
import 'package:mediaflow_app/design_system/mediaflow_cloud_indicator.dart';
import 'package:mediaflow_app/design_system/mediaflow_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cloud labels explicitly distinguish online reads from offline copies', () {
    expect(nativeCloudSourceLabel(NativeSnapshotSource.cloud),
        'Cloud read-only');
    expect(nativeCloudSourceLabel(NativeSnapshotSource.cloudNotCached),
        'Cloud · cache warning');
    expect(nativeCloudSourceLabel(NativeSnapshotSource.offline),
        'Offline copy');
    expect(nativeCloudSourceLabel(NativeSnapshotSource.invalidCloud),
        'Cloud data invalid');
    expect(nativeCloudSourceLabel(NativeSnapshotSource.cloud,
        refreshing: true), 'Refreshing cloud');
    expect(nativeCloudSourceOnline(NativeSnapshotSource.cloud), isTrue);
    expect(nativeCloudSourceOnline(NativeSnapshotSource.cloudNotCached), isTrue);
    expect(nativeCloudSourceOnline(NativeSnapshotSource.offline), isFalse);
  });

  testWidgets('AMOLED backdrop preserves legible native content',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: MediaFlowTheme.build(MediaFlowAppearance.amoled),
      home: const Scaffold(body: MfAmbientBackdrop(
        child: Center(child: Text('MediaFlow native')),
      )),
    ));
    expect(find.text('MediaFlow native'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile palette searches across hidden More destinations',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: MediaFlowShell()));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('workspace-search-mobile')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'fresh');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('search-freshReleases')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('search-freshReleases')));
    await tester.pumpAndSettle();
    expect(find.text('Fresh Episodes'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
