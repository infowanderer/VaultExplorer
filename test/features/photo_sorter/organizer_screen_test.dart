import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/photo_sorter/organizer.dart';
import 'package:vaultexplorer/features/photo_sorter/photo_sorter_screen.dart';
import 'organizer_fakes.dart';

void main() {
  late ProtectedMemory protected;
  late FixtureBridge bridge;
  late OrganizerController controller;
  setUp(() {
    protected = ProtectedMemory();
    bridge = FixtureBridge();
    controller = OrganizerController(
      root: '/storage/fixtures',
      folder: '',
      photos: ['a.jpg', 'b.jpg'],
      repository: protected.repository(),
      bridge: bridge,
    );
  });
  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(1280, 800),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: PhotoSorterScreen(
          photos: controller.photos,
          folderName: 'Vacation',
          organizer: controller,
          loadPreview: (_, _) async => null,
          pickDestination: () async =>
              const OrganizerFolder('/storage/fixtures/keep', '', 'My picks'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> menu(WidgetTester tester, String text) async {
    await tester.tap(find.byTooltip('More organization tools'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  Future<void> destination(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Choose a destination (S)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add destination'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Choose a destination (S)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My picks'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'compact gallery keeps stars Sort and Tags visible with advanced tools secondary',
    (tester) async {
      await open(tester);
      expect(find.byType(GridView), findsOneWidget);
      expect(find.byTooltip('Rate 5 stars (5)'), findsOneWidget);
      expect(find.text('Sort'), findsOneWidget);
      expect(find.text('Tags'), findsOneWidget);
      expect(find.text('Batch rename'), findsNothing);
      expect(find.text('All review states'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'chosen destination stages, advances, and Run queue has no extra confirmation',
    (tester) async {
      await open(tester);
      await destination(tester);
      expect(controller.state.decisions.keys, ['a.jpg']);
      expect(controller.state.selected, 'b.jpg');
      expect(bridge.executions, 0);
      await tester.tap(find.byTooltip('Operation queue & history'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Run queue'));
      await tester.pumpAndSettle();
      expect(find.text('Commit these operations?'), findsNothing);
      expect(bridge.executions, 1);
      expect(controller.state.decisions, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    '1 through 5 rate the selected photo and never stage destination operations',
    (tester) async {
      await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
      await tester.pumpAndSettle();
      expect(controller.reviewFor('a.jpg')!.rating, 4);
      expect(controller.state.decisions, isEmpty);
      expect(bridge.fingerprintReads, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
      await tester.pumpAndSettle();
      expect(controller.reviewFor('a.jpg')!.rating, 5);
      expect(bridge.executions, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'digits typed in search remain text and cannot rate or route files',
    (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Search filename or tag'));
      await tester.pumpAndSettle();
      final search = find.widgetWithText(TextField, 'Find filename or tag');
      await tester.tap(search);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.pumpAndSettle();
      expect(controller.state.reviews, isEmpty);
      expect(controller.state.decisions, isEmpty);
      await tester.enterText(search, 'b.jpg');
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(GridView),
          matching: find.text('b.jpg'),
        ),
        findsOneWidget,
      );
      expect(find.text('a.jpg'), findsNothing);
    },
  );
  testWidgets(
    'tags can be edited in the image viewer without losing its rating',
    (tester) async {
      await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Tags, separated by commas'),
        'vacation, beach',
      );
      await tester.tap(find.text('Save tags'));
      await tester.pumpAndSettle();
      expect(controller.reviewFor('a.jpg')!.rating, 4);
      expect(controller.reviewFor('a.jpg')!.tags, ['vacation', 'beach']);
      expect(bridge.fingerprintReads, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'review states remain available with ratings and tags in details',
    (tester) async {
      await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep'));
      await tester.tap(find.byTooltip('4 stars'));
      await tester.enterText(find.byType(TextField).last, 'vacation, beach');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(controller.state.reviews['a.jpg']!.state, ReviewState.keep);
      expect(controller.state.reviews['a.jpg']!.rating, 4);
      expect(bridge.executions, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'background curtain retains staged decisions and never auto-runs transfers',
    (tester) async {
      await open(tester);
      await destination(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(find.byType(GridView), findsNothing);
      expect(find.text('Resume organizer'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resume organizer'));
      await tester.pumpAndSettle();
      expect(controller.state.decisions.keys, ['a.jpg']);
      expect(bridge.executions, 0);
    },
  );
  testWidgets('compact controls fit a narrow touch window', (tester) async {
    await open(tester, size: const Size(400, 800));
    expect(find.byTooltip('Rate 5 stars (5)'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await destination(tester);
    expect(controller.state.decisions.length, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'labels are optional and the setting survives opening another folder',
    (tester) async {
      await open(tester);
      await menu(tester, 'Preferences');
      await tester.tap(find.widgetWithText(SwitchListTile, 'Button labels'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Sort'), findsNothing);
      expect(find.byTooltip('Choose a destination (S)'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      controller = OrganizerController(
        root: '/storage/other',
        folder: '',
        photos: ['a.jpg'],
        repository: protected.repository(),
        bridge: bridge,
      );
      await open(tester);
      expect(controller.showButtonLabels, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('long press explains sorting without activating it', (
    tester,
  ) async {
    await open(tester);
    await tester.longPress(find.byTooltip('Choose a destination (S)'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a destination (S)'), findsOneWidget);
    expect(find.text('Sort 1 file'), findsNothing);
    expect(bridge.executions, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('mouse hover shows contextual action help', (tester) async {
    await open(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(find.byTooltip('Edit tags (T)')));
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(find.text('Edit tags (T)'), findsOneWidget);
    await mouse.removePointer();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('batch rename previews names and stages without executing', (
    tester,
  ) async {
    await open(tester);
    await menu(tester, 'Batch rename');
    await tester.enterText(
      find.widgetWithText(TextField, 'Filename template'),
      'Vacation-{counter:03}.{ext}',
    );
    await tester.pumpAndSettle();
    expect(find.text('→ Vacation-001.jpg'), findsOneWidget);
    expect(find.text('→ Vacation-002.jpg'), findsOneWidget);
    await tester.tap(find.text('Stage 2 renamed copies'));
    await tester.pumpAndSettle();
    expect(controller.state.decisions['a.jpg']!['name'], 'Vacation-001.jpg');
    expect(bridge.executions, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('duplicate rename targets are refused in a narrow window', (
    tester,
  ) async {
    await open(tester, size: const Size(400, 800));
    await menu(tester, 'Batch rename');
    await tester.enterText(
      find.widgetWithText(TextField, 'Filename template'),
      'Photo.jpg',
    );
    await tester.pumpAndSettle();
    expect(find.text('Duplicate output name in this batch'), findsNWidgets(2));
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Stage 2 renamed copies'),
          )
          .onPressed,
      isNull,
    );
    expect(bridge.executions, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'collecting selected files writes only references and can display the collection',
    (tester) async {
      await open(tester);
      await menu(tester, 'Collections and saved searches');
      await tester.tap(find.text('Collect selected'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Collection name'),
        'Vacation picks',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        (await controller.repository.catalog.list()).single.members.single.path,
        'a.jpg',
      );
      await tester.tap(find.text('Vacation picks'));
      await tester.pumpAndSettle();
      expect(find.text('Vacation picks · 1'), findsOneWidget);
      expect(bridge.executions, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
