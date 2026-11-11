import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/photo_sorter/photo_sorter_screen.dart';

void main() {
  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: PhotoSorterScreen(
          photos: const ['a.jpg', 'b.jpg', 'c.jpg'],
          folderName: 'Vacation',
          loadPreview: (_, _) async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('tablet keyboard stages decisions and previews queue', (
    tester,
  ) async {
    await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.tap(find.byTooltip('Preview queue'));
    await tester.pumpAndSettle();
    expect(find.text('Staged decisions'), findsOneWidget);
    expect(find.text('Favorites'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  testWidgets('touch selection and view/grid toggle work', (tester) async {
    await open(tester);
    await tester.tap(find.text('c.jpg'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('3 / 3'), findsOneWidget);
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.tap(find.text('Grid'));
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('stylus can select a photo', (tester) async {
    await open(tester);
    await tester.tap(find.text('b.jpg'), kind: PointerDeviceKind.stylus);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('2 / 3'), findsOneWidget);
  });
  testWidgets('leaving foreground hides photos until screen is reopened', (
    tester,
  ) async {
    await open(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsNothing);
    expect(find.textContaining('Preview closed'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsNothing);
  });
  testWidgets('empty and narrow layouts stay usable', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: PhotoSorterScreen(
          photos: const [],
          folderName: 'Empty',
          loadPreview: (_, _) async => Uint8List(0),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No photographs in this folder.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
