import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/features/photo_sorter/duplicates_dialog.dart';
import 'package:vaultexplorer/features/photo_sorter/organizer.dart';
import 'organizer_fakes.dart';

class ScanFixture extends FixtureBridge {
  int scans = 0;
  Completer<Map<String, dynamic>>? gate;
  Map<String, dynamic> report = {
    'examined': 2,
    'hashed': 2,
    'groups': [
      {
        'sha256': 'a' * 64,
        'size': 123,
        'paths': ['a.jpg', 'b.jpg'],
      },
    ],
  };
  @override
  Future<Map<String, dynamic>> exactDuplicates(
    String id,
    String root,
    List<String> paths,
  ) async {
    scans++;
    return gate == null ? report : gate!.future;
  }
}

void main() {
  late ScanFixture bridge;
  late ProtectedMemory storage;
  late OrganizerController model;
  setUp(() {
    bridge = ScanFixture();
    storage = ProtectedMemory();
    model = OrganizerController(
      root: '/fixture',
      folder: '',
      photos: ['a.jpg', 'b.jpg'],
      repository: storage.repository(),
      bridge: bridge,
    );
  });
  tearDown(() => model.dispose());
  Future<void> open(WidgetTester tester, {List<String>? paths}) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: DuplicatesDialog(controller: model, paths: paths ?? model.photos),
      ),
    );
  }

  testWidgets(
    'reports exact groups in a narrow window without metadata or file mutations',
    (tester) async {
      await open(tester);
      await tester.pumpAndSettle();
      expect(find.text('Group 1 · 2 files'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('a.jpg'), 120);
      expect(find.text('a.jpg'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('b.jpg'), 120);
      expect(find.text('b.jpg'), findsOneWidget);
      expect(storage.records, isEmpty);
      expect(bridge.preparations, 0);
      expect(bridge.executions, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('no duplicate match is reported explicitly', (tester) async {
    bridge.report = {'examined': 2, 'hashed': 0, 'groups': []};
    await open(tester);
    await tester.pumpAndSettle();
    expect(find.text('No exact duplicates found'), findsOneWidget);
  });
  testWidgets('out-of-selection report members fail closed', (tester) async {
    bridge.report['groups'] = [
      {
        'sha256': 'a' * 64,
        'size': 1,
        'paths': ['a.jpg', '../outside.jpg'],
      },
    ];
    await open(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('Scan stopped'), findsOneWidget);
    expect(find.text('../outside.jpg'), findsNothing);
    expect(find.text('No exact duplicates found'), findsNothing);
  });
  testWidgets('cancel discards even a late successful native report', (
    tester,
  ) async {
    bridge.gate = Completer<Map<String, dynamic>>();
    await open(tester);
    await tester.pump();
    await tester.tap(find.text('Cancel scan'));
    await tester.pump();
    expect(bridge.cancellations, 1);
    bridge.gate!.complete(bridge.report);
    await tester.pumpAndSettle();
    expect(find.textContaining('Scan cancelled'), findsOneWidget);
    expect(find.text('Group 1 · 2 files'), findsNothing);
  });
  testWidgets(
    'backgrounding cancels the scan and does not publish results on return',
    (tester) async {
      bridge.gate = Completer<Map<String, dynamic>>();
      await open(tester);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(bridge.cancellations, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      bridge.gate!.complete(bridge.report);
      await tester.pumpAndSettle();
      expect(find.textContaining('Scan cancelled'), findsOneWidget);
      expect(find.text('a.jpg'), findsNothing);
    },
  );
  testWidgets('oversized batches are refused before a platform scan', (
    tester,
  ) async {
    await open(tester, paths: List.generate(501, (i) => '$i.jpg'));
    await tester.pumpAndSettle();
    expect(bridge.scans, 0);
    expect(find.textContaining('Scan stopped'), findsOneWidget);
  });
}
