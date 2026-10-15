import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/design_system/mediaflow_theme.dart';
import 'package:mediaflow_app/features/settings/native_m56_sync_preflight_panel.dart';
import 'package:mediaflow_app/features/settings/native_settings_screen.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';
import 'package:mediaflow_app/services/native_m30_shared_sync.dart';
import 'package:mediaflow_app/services/native_m56_sync_inventory.dart';

void main() {
  test('source audit has traceable, unique writer references', () {
    expect(NativeM56SyncInventory.writerSurfaces, 18);
    expect(NativeM56SyncInventory.sources.length, 18);
    expect(NativeM56SyncInventory.sources.map((s)=>s.id).toSet().length, 18);
    expect(NativeM56SyncInventory.sources.where(
      (s)=>s.client=='website').length, 14);
    expect(NativeM56SyncInventory.sources.where(
      (s)=>s.client=='native').length, 4);
    expect(NativeM56SyncInventory.sources.every(
      (s)=>s.entrypoint.isNotEmpty && s.sourcePath.isNotEmpty), isTrue);
    expect(NativeM56SyncInventory.rehearsalScenarios, 12);
    expect(NativeM56SyncInventory.unresolvedDiscoveryTasks, 8);
    expect(NativeM56SyncInventory.unresolvedStagingChecks, 8);
    expect(NativeM56SyncInventory.stagingChecks.length, 8);
    expect(NativeM56SyncInventory.stagingChecks.map((g)=>g.id).toSet().length,
      8);
  });

  test('staging, production and cloud capabilities remain locked', () {
    expect(NativeM56SyncInventory.sourceAuditExhaustive, isFalse);
    expect(NativeM56SyncInventory.stagingEnvironmentProvisioned, isFalse);
    expect(NativeM56SyncInventory.productionCloudWritesEnabled, isFalse);
    expect(NativeM56SyncInventory.serverProtocolDeployed, isFalse);
    expect(NativeM56SyncInventory.cutoverAuthorized, isFalse);
    expect(NativeM56SyncInventory.readyForStaging, isFalse);
    expect(NativeM56SyncInventory.readyForProduction, isFalse);
    expect(NativeCloudCapabilities.cloudWritesEnabled, isFalse);
    expect(NativeCloudCapabilities.hasServerSideCas, isFalse);
    expect(NativeCloudCapabilities.offlineWriteQueueEnabled, isFalse);
    expect(NativeM30Protocol.deployed, isFalse);
  });

  testWidgets('320px panel shows lock and local-only audit',
      (tester) async {
    tester.view.physicalSize=const Size(320,890);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme:MediaFlowTheme.build(MediaFlowAppearance.dark),
      home:const Scaffold(body:SingleChildScrollView(
        child:NativeM56SyncPreflightPanel()))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m56-sync-preflight-panel')), findsOneWidget);
    expect(find.byKey(const Key('m56-sync-cutover-blocked')), findsOneWidget);
    expect(find.text('Staging & production cutover: BLOCKED'), findsOneWidget);
    expect(find.textContaining('18 writer-related surfaces'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('m56-staging-checks')));
    await tester.tap(find.text('Blocked staging prerequisites'));
    await tester.pumpAndSettle();
    expect(find.text('No staging project has been provisioned'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('light mode writer review cannot trigger account edits',
      (tester) async {
    tester.view.physicalSize=const Size(390,1000);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme:MediaFlowTheme.build(MediaFlowAppearance.light),
      home:const Scaffold(body:SingleChildScrollView(
        child:NativeM56SyncPreflightPanel()))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('m56-writer-surfaces')));
    await tester.tap(find.text('Source-backed write path inventory'));
    await tester.pumpAndSettle();
    expect(find.text('rawSet()'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AMOLED Settings shows M55 and M56 without Supabase',
      (tester) async {
    tester.view.physicalSize=const Size(400,950);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme:MediaFlowTheme.build(MediaFlowAppearance.amoled),
      home:Scaffold(body:NativeSettingsScreen(
        appearance:MediaFlowAppearance.amoled,
        onAppearanceChanged:(_){},
      ))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m55-release-blocked')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('m56-sync-preflight-panel')),
      260, maxScrolls: 20);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m56-sync-cutover-blocked')), findsOneWidget);
    expect(NativeCloudCapabilities.cloudWritesEnabled, isFalse);
    expect(tester.takeException(), isNull);
  });
}
