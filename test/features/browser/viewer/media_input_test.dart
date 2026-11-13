import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/viewer/media_input.dart';

void main() {
  testWidgets('arrows, repeats and Ctrl dispatch once; key-up does not', (
    tester,
  ) async {
    final commands = <MediaInputCommand>[];
    await tester.pumpWidget(
      MaterialApp(
        home: MediaInputScope(
          onCommand: (command) {
            commands.add(command);
            return true;
          },
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(commands, [
      MediaInputCommand.forward,
      MediaInputCommand.forward,
      MediaInputCommand.backward,
      MediaInputCommand.controlBackward,
      MediaInputCommand.controlForward,
    ]);
  });

  testWidgets(
    'canvas wheel overrides InteractiveViewer wheel zoom, including Ctrl',
    (tester) async {
      final commands = <MediaInputCommand>[];
      final transform = TransformationController();
      addTearDown(transform.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaInputScope(
            onCommand: (command) {
              commands.add(command);
              return true;
            },
            child: Builder(
              builder: (context) => InteractiveViewer(
                scaleFactor: MediaInputScope.wheelScaleFactor(context),
                transformationController: transform,
                child: const MediaPointerRegion(child: SizedBox.expand()),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      Future<void> wheel(double delta) async {
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: const Offset(200, 200),
            scrollDelta: Offset(0, delta),
            kind: PointerDeviceKind.mouse,
          ),
        );
        await tester.pump();
      }

      await wheel(120);
      await wheel(-120);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await wheel(-120);
      await wheel(120);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(commands, [
        MediaInputCommand.forward,
        MediaInputCommand.backward,
        MediaInputCommand.controlWheelUp,
        MediaInputCommand.controlWheelDown,
      ]);
      expect(transform.value.isIdentity(), isTrue);
    },
  );

  testWidgets('focused text and a modal keep their arrow keys', (tester) async {
    var commands = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaInputScope(
          onCommand: (_) {
            commands++;
            return true;
          },
          child: Scaffold(
            body: Column(
              children: [
                const TextField(),
                Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => const AlertDialog(content: TextField()),
                    ),
                    child: const Text('Open dialog'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(TextField));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(commands, 0);
    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(commands, 0);
  });

  test('centered zoom is bounded and reversible', () {
    const viewport = Size(800, 600);
    final zoomed = steppedMediaZoom(Matrix4.identity(), viewport, 1);
    expect(zoomed.getMaxScaleOnAxis(), closeTo(1.2, .00001));
    expect(zoomed.getTranslation().x, closeTo(-80, .00001));
    expect(zoomed.getTranslation().y, closeTo(-60, .00001));
    final restored = steppedMediaZoom(zoomed, viewport, -1);
    expect(restored.getMaxScaleOnAxis(), closeTo(1, .00001));
    expect(restored.getTranslation().length, closeTo(0, .00001));
    expect(
      steppedMediaZoom(Matrix4.identity(), viewport, -1).getMaxScaleOnAxis(),
      1,
    );
  });
}
