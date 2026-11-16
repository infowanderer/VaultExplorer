import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/seek_seconds_button.dart';

void main() {
  testWidgets(
    'exact seconds validate before saving; cancel leaves setting alone',
    (tester) async {
      final values = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SeekSecondsButton(
              seconds: 5,
              label: 'Video jump',
              onChanged: (value) async => values.add(value),
            ),
          ),
        ),
      );
      await tester.tap(find.text('5s'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '0');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter 1–600 seconds'), findsOneWidget);
      expect(values, isEmpty);
      await tester.enterText(find.byType(TextFormField), '42');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(values, [42]);
      await tester.tap(find.text('5s'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '99');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(values, [42]);
    },
  );
}
