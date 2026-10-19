// ignore_for_file: prefer_interpolation_to_compose_strings
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mediaflow_app/data/mediaflow_library_repository.dart';
import 'package:mediaflow_app/data/mediaflow_models.dart';
import 'package:mediaflow_app/data/mediaflow_state_codec.dart';
import 'package:mediaflow_app/features/dashboard/dashboard_screen.dart';
import 'package:mediaflow_app/features/history/history_screen.dart';

class FakeSnapshot extends MediaFlowLibraryRepository {
  int requests = 0;
  @override
  Future<MediaFlowCatalog> load() async {
    requests++;
    final today = DateTime.now();
    final iso = today.year.toString().padLeft(4, '0') + '-' +
        today.month.toString().padLeft(2, '0') + '-' +
        today.day.toString().padLeft(2, '0');
    return decodeMediaFlowState({
      'categories': [{'id': 'anime', 'name': 'Anime', 'icon': '📺'}],
      'library': [
        {'id':'one', 'title': 'Hotel', 'categoryId':'anime',
          'status':'active', 'progress':2, 'total':12},
      ],
      'sessions': [
        {
          'id': 's1', 'date': iso, 'timestamp': today.millisecondsSinceEpoch,
          'categoryId': 'anime', 'actualAmount': 2, 'minutes': 35, 'xp': 20,
          'status':'complete', 'unit':'episodes',
          'titles':[{'title':'Hotel', 'qty':2}],
        },
      ],
      'settings': {'dailyMinutes': 60, 'tasksPerDay': 2},
      'sessionActive': true,
      'currentTask': {
        'categoryId':'anime', 'title':'Hotel',
        'low':1, 'high':3, 'unit':'episodes',
      },
    });
  }
}

void main() {
  testWidgets('Dashboard uses real snapshot projection and navigates',
      (tester) async {
    tester.view.physicalSize = const Size(820, 1040);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var navigated = false;
    final repository = FakeSnapshot();
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: DashboardScreen(
        repository: repository,
        openLibrary: () => navigated = true,
        openHistory: () {},
      ),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Library titles'), findsOneWidget);
    expect(find.text('NEXT TASK'), findsOneWidget);
    expect(find.text('Hotel', skipOffstage: false), findsWidgets);
    await tester.ensureVisible(
      find.widgetWithText(OutlinedButton, 'Browse Library'));
    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Browse Library'));
    expect(navigated, isTrue);
  });

  testWidgets('History renders real sessions and searches title',
      (tester) async {
    tester.view.physicalSize = const Size(850, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = FakeSnapshot();
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: HistoryScreen(repository: repository),
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('Hotel'), findsWidgets);
    await tester.enterText(find.byType(TextField), 'absent search');
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pumpAndSettle();
    expect(find.text('No sessions match the current filters.'), findsOneWidget);
  });
}
