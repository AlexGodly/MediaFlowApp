import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_library_repository.dart';
import 'package:mediaflow_app/data/mediaflow_models.dart';
import 'package:mediaflow_app/data/mediaflow_state_codec.dart';
import 'package:mediaflow_app/features/library/library_screen.dart';

class FakeLibraryRepository extends MediaFlowLibraryRepository {
  @override
  Future<MediaFlowCatalog> load() async => decodeMediaFlowState({
    'categories': [
      {'id': 'a', 'name': 'Anime'},
      {'id': 'b', 'name': 'Books'},
    ],
    'library': [
      {'id': '1', 'title': 'Hotel', 'categoryId': 'a',
        'status': 'active', 'progress': 2, 'total': 12},
      {'id': '2', 'title': 'A Book', 'categoryId': 'b',
        'status': 'planned', 'progress': 0, 'total': 1},
    ],
  });
}

void main() {
  testWidgets('native Library filters titles without any cloud writes',
      (tester) async {
    tester.view.physicalSize = const Size(900, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: LibraryScreen(repository: FakeLibraryRepository())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Hotel'), findsOneWidget);
    expect(find.text('A Book'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'hotel');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.text('Hotel'), findsOneWidget);
    expect(find.text('A Book'), findsNothing);
  });
}
