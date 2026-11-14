import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/features/photo_sorter/contact_sheet_plan.dart';
import 'package:vaultexplorer/features/photo_sorter/contact_sheet_dialog.dart';

void main() {
  test('sampling uses bucket centers and never requests the end timestamp', () {
    expect(
      contactSheetTimes(120000000),
      List.generate(12, (i) => 5000000 + 10000000 * i),
    );
    expect(contactSheetTimes(3), [0, 1, 2]);
    expect(contactSheetTimes(1), [0]);
    for (final duration in [1, 2, 5, 1000, 3600000000]) {
      for (final count in [6, 12, 24]) {
        final times = contactSheetTimes(duration, count: count);
        expect(times.toSet().length, times.length);
        expect(times.every((n) => n >= 0 && n < duration), isTrue);
        expect([...times]..sort(), times);
      }
    }
  });
  test('invalid duration and frame counts fail before decoding', () {
    for (final duration in [-1, 0, (1 << 52) + 1]) {
      expect(() => contactSheetTimes(duration), throwsFormatException);
    }
    for (final count in [0, 25]) {
      expect(
        () => contactSheetTimes(1000, count: count),
        throwsFormatException,
      );
    }
    expect(contactSheetTimeLabel(3661000000), '1:01:01');
    expect(contactSheetTimeLabel(1250000), '0:01.250');
  });
  Future<void> open(
    WidgetTester tester, {
    required Future<Uint8List?> Function(int) frame,
    required Future<void> Function(int) seek,
    int duration = 120000000,
  }) async {
    await tester.binding.setSurfaceSize(const Size(600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => ContactSheetDialog(
                  durationUs: duration,
                  loadFrame: frame,
                  seek: seek,
                ),
              ),
              child: const Text('Open frames'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open frames'));
  }

  testWidgets(
    'generates 12 bounded previews and a tile seeks its requested timestamp',
    (tester) async {
      final requested = <int>[];
      final sought = <int>[];
      await open(
        tester,
        frame: (time) async {
          requested.add(time);
          return null;
        },
        seek: (time) async {
          sought.add(time);
        },
      );
      await tester.pumpAndSettle();
      expect(requested, contactSheetTimes(120000000));
      await tester.tap(find.text('0:05'));
      await tester.pumpAndSettle();
      expect(sought, [5000000]);
      expect(find.text('Video contact sheet'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'decodes sequentially and wipes a late result after cancellation',
    (tester) async {
      final gate = Completer<Uint8List?>();
      var requests = 0;
      await open(
        tester,
        frame: (_) {
          requests++;
          return gate.future;
        },
        seek: (_) async {},
      );
      await tester.pump();
      expect(requests, 1);
      await tester.tap(find.text('Stop previews'));
      await tester.pump();
      final bytes = Uint8List.fromList([12, 34, 56]);
      gate.complete(bytes);
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(bytes, [0, 0, 0]);
      expect(find.text('Preview closed'), findsOneWidget);
    },
  );
  testWidgets('backgrounding closes previews and discards late frame bytes', (
    tester,
  ) async {
    final gate = Completer<Uint8List?>();
    await open(tester, frame: (_) => gate.future, seek: (_) async {});
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    final bytes = Uint8List.fromList([9, 8, 7]);
    gate.complete(bytes);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(bytes, [0, 0, 0]);
    expect(find.text('Preview closed'), findsOneWidget);
  });
  testWidgets('a changed video refuses seek without closing the report', (
    tester,
  ) async {
    await open(
      tester,
      frame: (_) async => null,
      seek: (_) async => throw StateError('Changed synthetic source'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('0:05'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not seek'), findsOneWidget);
    expect(find.text('Video contact sheet'), findsOneWidget);
  });
  testWidgets('invalid duration makes no decoder request', (tester) async {
    var requests = 0;
    await open(
      tester,
      duration: 0,
      frame: (_) async {
        requests++;
        return null;
      },
      seek: (_) async {},
    );
    await tester.pumpAndSettle();
    expect(requests, 0);
    expect(find.textContaining('valid video duration'), findsOneWidget);
  });
  testWidgets(
    'closing evicts decoded previews and wipes their owned encoded buffers',
    (tester) async {
      late Uint8List png;
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
        final image = await recorder.endRecording().toImage(2, 2);
        png = (await image.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List();
        image.dispose();
      });
      final buffers = <Uint8List>[];
      await open(
        tester,
        duration: 3,
        frame: (_) async {
          final bytes = Uint8List.fromList(png);
          buffers.add(bytes);
          return bytes;
        },
        seek: (_) async {},
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pumpAndSettle();
      expect(buffers.length, 3);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(buffers.every((bytes) => bytes.every((b) => b == 0)), isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
