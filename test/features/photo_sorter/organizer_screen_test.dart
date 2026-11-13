import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets(
    'actual chosen destination stages and requires preview plus confirmation before copy',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('Choose your first destination folder'));
      await tester.pumpAndSettle();
      expect(find.text('1 · My picks'), findsOneWidget);
      await tester.tap(find.text('1 · My picks'));
      await tester.pumpAndSettle();
      expect(controller.state.decisions.keys, ['a.jpg']);
      expect(find.text('2 / 2'), findsOneWidget);
      expect(bridge.executions, 0);
      await tester.tap(find.byTooltip('Operation queue & history'));
      await tester.pumpAndSettle();
      expect(find.text('Commit…'), findsNothing);
      await tester.tap(find.text('Check & preview'));
      await tester.pumpAndSettle();
      expect(find.text('Commit…'), findsOneWidget);
      expect(bridge.executions, 0);
      await tester.tap(find.text('Commit…'));
      await tester.pumpAndSettle();
      expect(find.text('Commit these operations?'), findsOneWidget);
      expect(bridge.executions, 0);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(bridge.executions, 0);
      await tester.tap(find.text('Commit…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Commit'));
      await tester.pumpAndSettle();
      expect(bridge.executions, 1);
      expect(controller.state.decisions, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('typing digits in search never stages a destination', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Choose your first destination folder'));
    await tester.pumpAndSettle();
    final search = find.widgetWithText(TextField, 'Find filename or tag');
    await tester.tap(search);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pumpAndSettle();
    expect(controller.state.decisions, isEmpty);
    expect(bridge.inspections, 0);
    await tester.enterText(search, 'b.jpg');
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(GridView), matching: find.text('b.jpg')),
      findsOneWidget,
    );
    expect(find.text('a.jpg'), findsNothing);
  });
  testWidgets(
    'reviews, rating and tags are saved through the protected model',
    (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Review / rate / tag (R)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep'));
      await tester.tap(find.byTooltip('4 stars'));
      await tester.enterText(find.byType(TextField).last, 'vacation, beach');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(controller.state.reviews['a.jpg']!.rating, 4);
      expect(controller.state.reviews['a.jpg']!.tags, ['vacation', 'beach']);
      expect(bridge.executions, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('background curtain keeps saved decisions and offers resume', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Choose your first destination folder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 · My picks'));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsNothing);
    expect(find.text('Resume organizer'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resume organizer'));
    await tester.pumpAndSettle();
    expect(controller.state.decisions.keys, ['a.jpg']);
    expect(find.byType(GridView), findsOneWidget);
    expect(bridge.executions, 0);
  });
  testWidgets('narrow touch layout stays usable without plaintext fallback', (
    tester,
  ) async {
    await open(tester, size: const Size(400, 800));
    expect(find.text('Choose your first destination folder'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Choose your first destination folder'));
    await tester.pumpAndSettle();
    expect(find.text('1 · My picks'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
