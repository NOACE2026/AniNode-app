import 'package:aninode_mobile/screens/search_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('search screen shows idle placeholder before typing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: SearchScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Type to search for anime'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });
}
