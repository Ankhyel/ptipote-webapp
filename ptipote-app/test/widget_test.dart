import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ptipote_app/features/home/home_page.dart';

void main() {
  testWidgets('Home page exposes public actions only',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));

    expect(find.text('PTIPOTE App'), findsOneWidget);
    expect(find.text('Mes PTIPOTE'), findsOneWidget);
    expect(find.text('Scanner une puce'), findsOneWidget);
    expect(find.text('Reprogrammer une puce'), findsNothing);
  });
}
