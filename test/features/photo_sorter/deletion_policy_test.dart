import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/features/photo_sorter/deletion_policy.dart';
import 'organizer_fakes.dart';

void main() {
  test('display and deletion preferences preserve each other', () async {
    final storage = ProtectedMemory();
    final repository = storage.repository();
    expect(await repository.loadConfirmDeletion(), isTrue);
    expect(storage.records, isEmpty);
    await repository.saveConfirmDeletion(false);
    await repository.saveButtonLabels(false);
    expect(await repository.loadConfirmDeletion(), isFalse);
    await repository.saveConfirmDeletion(true);
    expect(await repository.loadButtonLabels(), isFalse);
    storage.persist = false;
    await expectLater(repository.saveConfirmDeletion(false), throwsStateError);
    expect(await repository.loadConfirmDeletion(), isTrue);
  });
  for (final ask in [true, false]) {
    testWidgets(
      'deletion confirmation ${ask ? 'prompts and respects cancel' : 'can be skipped'}',
      (tester) async {
        final storage = ProtectedMemory();
        await storage.repository().saveConfirmDeletion(ask);
        var prompts = 0;
        bool? allowed;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  child: const Text('Delete synthetic fixture'),
                  onPressed: () async {
                    allowed = await allowMediaDeletion(context, () async {
                      prompts++;
                      return false;
                    }, repository: storage.repository());
                  },
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Delete synthetic fixture'));
        await tester.pumpAndSettle();
        expect(prompts, ask ? 1 : 0);
        expect(allowed, !ask);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'unavailable encrypted preferences fail closed even after opting out',
    (tester) async {
      final storage = ProtectedMemory();
      await storage.repository().saveConfirmDeletion(false);
      storage.available = false;
      var prompts = 0;
      bool? allowed;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Delete synthetic fixture'),
                onPressed: () async {
                  allowed = await allowMediaDeletion(context, () async {
                    prompts++;
                    return true;
                  }, repository: storage.repository());
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Delete synthetic fixture'));
      await tester.pumpAndSettle();
      expect(prompts, 0);
      expect(allowed, isFalse);
      expect(find.textContaining('Nothing was deleted'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
