import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_library_repository.dart';
import 'package:mediaflow_app/data/mediaflow_models.dart';
import 'package:mediaflow_app/features/logging/logging_screen.dart';

class _FixtureRepository extends MediaFlowLibraryRepository {
  @override
  Future<MediaFlowCatalog> load() async => MediaFlowCatalog(
    categories: [
      const MediaFlowCategory(
        id: 'anime', name: 'Anime', icon: '◈', iconUrl: '', color: '',
      ),
    ],
    library: [
      MediaFlowTitle.fromJson({
        'id': 'one', 'title': 'Alpha', 'categoryId': 'anime',
        'status': 'active', 'priority': 'high', 'progress': 8, 'total': 12,
      }),
      MediaFlowTitle.fromJson({
        'id': 'two', 'title': 'Beta', 'categoryId': 'anime',
        'status': 'completed', 'priority': 'low', 'progress': 24, 'total': 24,
      }),
    ],
  );
}

void main() {
  testWidgets('Logging selection previews titles without a save action',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: LoggingScreen(repository: _FixtureRepository()),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Preview selection'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Select visible'), 160,
      scrollable: find.descendant(
        of: find.byKey(const Key('m51-logging-controls-scroll')),
        matching: find.byType(Scrollable)).first;
    await tester.tap(find.text('Select visible'));
    await tester.pump();
    expect(find.textContaining('2 selected'), findsOneWidget);
    await tester.tap(find.text('Preview selection'));
    await tester.pumpAndSettle();
    expect(find.text('Selection preview'), findsOneWidget);
    expect(find.textContaining('this does not record progress'),
        findsOneWidget);
    expect(find.text('Close preview'), findsOneWidget);
    expect(find.text('Save'), findsNothing);
    await tester.tap(find.text('Close preview'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Clear selection'), 160,
      scrollable: find.descendant(
        of: find.byKey(const Key('m51-logging-controls-scroll')),
        matching: find.byType(Scrollable)).first;
    await tester.tap(find.text('Clear selection'));
    await tester.pump();
    expect(find.textContaining('0 selected'), findsOneWidget);
  });
}
