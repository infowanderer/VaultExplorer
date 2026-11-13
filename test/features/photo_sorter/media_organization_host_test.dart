import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/features/browser/viewer/media_input.dart';
import 'package:vaultexplorer/features/photo_sorter/media_organization_host.dart';
import 'package:vaultexplorer/features/photo_sorter/organizer.dart';
import 'organizer_fakes.dart';

void main() {
  for (final file in ['photo.jpg', 'video.mp4']) {
    for (final viewer in [false, true]) {
      testWidgets(
        '${viewer ? 'viewer' : 'gallery'} rates, tags and stages $file',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(1280, 800));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final storage = ProtectedMemory();
          final bridge = FixtureBridge();
          OrganizerController? model;
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: MediaOrganizationHost(
                  root: '/fixture',
                  folder: '',
                  files: [file],
                  selected: [file],
                  repository: storage.repository(),
                  bridge: bridge,
                  overlay: viewer,
                  builder: (_, controller, controls) {
                    model = controller;
                    final canvas = Column(
                      children: [
                        Expanded(child: Text(file)),
                        controls,
                      ],
                    );
                    return viewer
                        ? MediaInputScope(onCommand: (_) => true, child: canvas)
                  : canvas;
                  },
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
          await tester.pumpAndSettle();
          expect(model!.reviewFor(file)!.rating, 5);
          expect(bridge.fingerprintReads, 0);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextFormField), 'beach, family');
          await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
          await tester.pumpAndSettle();
          expect(
            model!.reviewFor(file)!.rating,
            5,
            reason: 'Tag input keeps digit keys',
          );
          await tester.tap(find.text('Save tags'));
          await tester.pumpAndSettle();
          expect(model!.reviewFor(file)!.tags, ['beach', 'family']);
          await model!.addDestination(
            const OrganizerFolder('/fixture/destination', '', 'Keep'),
          );
          await tester.pumpAndSettle();
          await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
          await tester.pumpAndSettle();
          expect(model!.state.decisions.keys, [file]);
          expect(bridge.executions, 0);
          expect(bridge.fingerprintReads, 0);
          await tester.tap(find.byTooltip('Operation queue & history'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Run queue'));
          await tester.pumpAndSettle();
          expect(bridge.executions, 1);
          expect(
            bridge.fingerprintReads,
            1,
            reason: 'Content verified before transporting notes',
          );
          expect(find.text('Commit these operations?'), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('disabled viewer input and covered routes cannot rate media', (
    tester,
  ) async {
    final storage = ProtectedMemory();
    final bridge = FixtureBridge();
    late OrganizerController model;
    late StateSetter update;
    var enabled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return Scaffold(
              body: MediaOrganizationHost(
                root: '/fixture',
                folder: '',
                files: const ['a.jpg'],
                selected: const ['a.jpg'],
                bridge: bridge,
                repository: storage.repository(),
                enabled: enabled,
                builder: (_, controller, controls) {
                  model = controller;
                  return Focus(
                    autofocus: true,
                    child: Column(
                      children: [
                        TextButton(
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) =>
                                const AlertDialog(content: Text('Covered')),
                          ),
                          child: const Text('Dialog'),
                        ),
                        controls,
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.tap(find.byTooltip('Rate 5 stars (5)'));
    await tester.pumpAndSettle();
    expect(model.state.reviews, isEmpty);
    update(() => enabled = true);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dialog'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
    expect(model.state.reviews, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gallery refreshes ratings edited by a pushed viewer', (
    tester,
  ) async {
    final storage = ProtectedMemory();
    final bridge = FixtureBridge();
    late OrganizerController gallery;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: MediaOrganizationHost(
              root: '/fixture',
              folder: '',
              files: const ['a.jpg'],
              selected: const ['a.jpg'],
              repository: storage.repository(),
              bridge: bridge,
              builder: (_, model, controls) {
                gallery = model;
                return Focus(
                  autofocus: true,
                  child: Column(
                    children: [
                      controls,
                      TextButton(
                        child: const Text('Open viewer'),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (viewerContext) => Scaffold(
                              body: MediaOrganizationHost(
                                root: '/fixture',
                                folder: '',
                                files: const ['a.jpg'],
                                selected: const ['a.jpg'],
                                repository: storage.repository(),
                                bridge: bridge,
                                builder: (_, model, controls) => Focus(
                                  autofocus: true,
                                  child: Column(
                                    children: [
                                      controls,
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(viewerContext),
                                        child: const Text('Return'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open viewer'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Rate 4 stars (4)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Return'));
    await tester.pumpAndSettle();
    expect(gallery.reviewFor('a.jpg')!.rating, 4);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
    await tester.pumpAndSettle();
    expect(gallery.reviewFor('a.jpg')!.rating, 5);
    expect(gallery.error, isNull);
    expect(tester.takeException(), isNull);
  });

  test('organization paths confine raw and approved document roots', () {
    expect(organizationPath('/photos', '/photos/day/a.jpg'), 'day/a.jpg');
    expect(organizationPath('/photos', '/other/a.jpg'), isNull);
    expect(organizationPath('/photos', '../a.jpg'), isNull);
    expect(organizationPath('content://untrusted/tree/a', 'a.jpg'), isNull);
    expect(
      organizationPath(
        'content://com.android.externalstorage.documents/tree/1',
        'day/a.mp4',
      ),
      'day/a.mp4',
    );
    expect(
      organizationPath(
        'content://com.android.externalstorage.documents/tree/1',
        '../a.jpg',
      ),
      isNull,
    );
  });
}
