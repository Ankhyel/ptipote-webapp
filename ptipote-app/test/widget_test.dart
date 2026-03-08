import 'package:flutter_test/flutter_test.dart';
import 'package:ptipote_app/app.dart';

void main() {
  testWidgets('App renders home title', (WidgetTester tester) async {
    await tester.pumpWidget(const PtipoteApp());

    expect(find.text('PTIPOTE App'), findsOneWidget);
  });
}
