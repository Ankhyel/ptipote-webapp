import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ptipote_app/features/home/home_page.dart';

void main() {
  testWidgets('Home page exposes public actions only',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));

    expect(find.text('PTIPOTE App'), findsOneWidget);
    expect(find.text('Mes PTIPOTES'), findsOneWidget);
    expect(find.text('Scan une figurine'), findsOneWidget);
    expect(find.text('Reprogrammer une puce'), findsNothing);
  });
}
