import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/design_system/mediaflow_theme.dart';
import 'package:mediaflow_app/features/settings/native_m55_release_readiness_panel.dart';
import 'package:mediaflow_app/features/settings/native_settings_screen.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';
import 'package:mediaflow_app/services/native_m30_shared_sync.dart';
import 'package:mediaflow_app/services/native_m55_readiness.dart';

void main() {
  test('v410 inventory is fully traced but not certified by milestone number',
      () {
    expect(NativeM55Readiness.sourceBaseline,'MediaFlow v410');
    expect(NativeM55Readiness.inventorySurfaces,307);
    expect(NativeM55Readiness.inventoriedDomains,21);
    expect(NativeM55Readiness.certifiedSurfaces,0);
    expect(NativeM55Readiness.inventoriedJourneys,54);
    expect(NativeM55Readiness.certifiedJourneys,0);
    expect(NativeM55Readiness.defaultSettingsKeys,38);
    expect(NativeM55Readiness.candidateStateRoots,30);
    expect(NativeM55Readiness.domainAudits.length,21);
    expect(NativeM55Readiness.domainAudits.fold<int>(
        0,(count,d)=>count+d.surfaces),307);
    expect(NativeM55Readiness.domainAudits.fold<int>(
        0,(count,d)=>count+d.journeys),54);
    expect(NativeM55Readiness.domainAudits.every(
        (d)=>d.certified==0&&d.verifiedJourneys==0),true);
    expect(NativeM55Readiness.domainAudits.map((e)=>e.id).toSet().length,21);
    expect(NativeM55Readiness.productionReleaseAuthorized,false);
    expect(NativeM55Readiness.fullWebsiteParityCertified,false);
    expect(NativeM55Readiness.productionCloudWritesEnabled,false);
    expect(NativeM55Readiness.canPublishProduction,false);
    expect(NativeM55Readiness.allCertified,false);
    expect(NativeCloudCapabilities.cloudWritesEnabled,false);
    expect(NativeCloudCapabilities.hasServerSideCas,false);
    expect(NativeM30Protocol.deployed,false);
  });

  test('each critical release gate stays a blocker until source sign-off',() {
    expect(NativeM55Readiness.gates.length,12);
    expect(NativeM55Readiness.gates.map((e)=>e.id).toSet().length,12);
    expect(NativeM55Readiness.gates.any(
      (e)=>e.id=='shared-sync'&&e.priority=='P0'),true);
    expect(NativeM55Readiness.gates.any(
      (e)=>e.id=='logging-history-xp'&&e.priority=='P0'),true);
    expect(NativeM55Readiness.gates.any(
      (e)=>e.id=='signed-distribution'&&e.priority=='P0'),true);
    expect(NativeM55Readiness.proposedNextMilestones.length,15);
    expect(NativeM55Readiness.proposedNextMilestones.first,
      startsWith('M56'));
    expect(NativeM55Readiness.proposedNextMilestones.last,
      startsWith('M70'));
  });

  testWidgets('compact phone panel reports blockers with no action buttons',
      (tester) async {
    tester.view.physicalSize=const Size(320,850);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme:MediaFlowTheme.build(MediaFlowAppearance.dark),
      home:const Scaffold(body:SingleChildScrollView(
        child:NativeM55ReleaseReadinessPanel()))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m55-readiness-panel')),findsOneWidget);
    expect(find.byKey(const Key('m55-release-blocked')),findsOneWidget);
    expect(find.text('Production release: BLOCKED'),findsOneWidget);
    expect(find.byType(FilledButton),findsNothing);
    expect(find.byKey(const Key('m55-release-gates')),findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('m55-release-gates')));
    await tester.tap(find.text('Why a production release is blocked'));
    await tester.pumpAndSettle();
    expect(find.text('12 unresolved gates'),findsOneWidget);
    expect(find.text('Atomic shared website/native synchronization'),
      findsOneWidget);
    expect(tester.takeException(),isNull);
  });

  testWidgets('domain and roadmap counts stay visible in light UI',
      (tester) async {
    tester.view.physicalSize=const Size(390,900);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme:MediaFlowTheme.build(MediaFlowAppearance.light),
      home:const Scaffold(body:SingleChildScrollView(
        child:NativeM55ReleaseReadinessPanel()))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('m55-domain-audit')));
    await tester.tap(find.text('21-domain source coverage'));
    await tester.pumpAndSettle();
    expect(find.textContaining('17 inventoried'),findsWidgets);
    expect(find.textContaining('0 certified'),findsWidgets);
    await tester.ensureVisible(find.byKey(const Key('m55-future-roadmap')));
    await tester.tap(find.text('Proposed next development milestones'));
    await tester.pumpAndSettle();
    expect(find.textContaining('M56 —'),findsOneWidget);
    expect(find.byType(FilledButton),findsNothing);
    expect(tester.takeException(),isNull);
  });

  testWidgets('Settings exposes release blockers without needing Supabase',
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
    expect(find.byKey(const Key('m55-release-blocked')),findsOneWidget);
    expect(find.textContaining('Native application preferences'),
      findsOneWidget);
    expect(NativeCloudCapabilities.cloudWritesEnabled,false);
    expect(tester.takeException(),isNull);
  });
}
