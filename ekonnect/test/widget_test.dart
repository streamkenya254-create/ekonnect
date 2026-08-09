import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App renders a MaterialApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('eKonnect')),
        ),
      ),
    );

    expect(find.text('eKonnect'), findsOneWidget);
  });
}
