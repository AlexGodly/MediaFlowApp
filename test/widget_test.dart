import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/main.dart';

void main() {
  testWidgets('app bootstrap renders', (tester) async {
    await tester.pumpWidget(const MediaFlowApp());
    expect(find.text('MediaFlow native migration — development scaffold'), findsOneWidget);
  });
}
