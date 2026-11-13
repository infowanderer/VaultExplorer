import 'dart:ui' show PointerDeviceKind;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/photo_sorter/photo_sorter_screen.dart';

void main() {
  Future<void> firstDestination(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Escape returns directly to gallery; staged decisions require confirmation',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Gallery'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => PhotoSorterScreen(
                      photos: const ['a.jpg', 'b.jpg'],
                      folderName: 'Vacation',
                      loadPreview: (_, _) async => null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Gallery'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Gallery'), findsOneWidget);
      expect(find.byType(PhotoSorterScreen), findsNothing);
      await tester.tap(find.text('Gallery'));
      await tester.pumpAndSettle();
      await firstDestination(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Discard staged decisions?'), findsOneWidget);
      await tester.tap(find.text('Stay'));
      await tester.pumpAndSettle();
      expect(find.byType(PhotoSorterScreen), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text('Gallery'), findsOneWidget);
    },
  );

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

  testWidgets(
    'full-photo arrows and wheel navigate; Ctrl zooms without navigation',
    (tester) async {
      await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      final transform = viewer.transformationController!;
      final canvas = tester.getCenter(find.byType(InteractiveViewer));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(transform.value.getMaxScaleOnAxis(), closeTo(1.2, .00001));
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: canvas,
          scrollDelta: const Offset(0, -120),
          kind: PointerDeviceKind.mouse,
        ),
      );
      await tester.pump();
      expect(transform.value.getMaxScaleOnAxis(), closeTo(1.44, .00001));
      expect(find.text('2 / 3'), findsOneWidget);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: canvas,
          scrollDelta: const Offset(0, 120),
          kind: PointerDeviceKind.mouse,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('3 / 3'), findsOneWidget);
      expect(transform.value.isIdentity(), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('tablet keyboard stages decisions and previews queue', (
    tester,
  ) async {
    await open(tester);
    await firstDestination(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
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
    await tester.tap(find.byTooltip('Enlarge current photo (Space)'));
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.tap(find.byTooltip('Show thumbnail grid (Space)'));
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('stylus can select a photo', (tester) async {
    await open(tester);
    await tester.tap(find.text('b.jpg'), kind: PointerDeviceKind.stylus);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
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
