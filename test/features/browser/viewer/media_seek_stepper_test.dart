import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/viewer/media_seek_stepper.dart';

void main() {
  test('rapid steps accumulate and native seeks never overlap', () async {
    final stepper = MediaSeekStepper();
    final owner = Object();
    final seeks = <Duration>[];
    final pending = <Completer<void>>[];
    void step(int seconds) => stepper.step(
      owner: owner,
      position: const Duration(seconds: 20),
      duration: const Duration(seconds: 100),
      delta: Duration(seconds: seconds),
      onError: () => fail('unexpected error'),
      seek: (target) {
        seeks.add(target);
        final c = Completer<void>();
        pending.add(c);
        return c.future;
      },
    );
    step(5);
    step(5);
    step(30);
    expect(seeks, [const Duration(seconds: 25)]);
    pending.first.complete();
    await Future<void>.delayed(Duration.zero);
    expect(seeks, [const Duration(seconds: 25), const Duration(seconds: 60)]);
    pending.last.complete();
    await Future<void>.delayed(Duration.zero);
    step(-5); // Stale native position event is still 20s.
    expect(seeks.last, const Duration(seconds: 55));
    pending.last.complete();
    await Future<void>.delayed(Duration.zero);
  });

  test(
    'clamps endpoints, drops old media queue and recovers after errors',
    () async {
      final stepper = MediaSeekStepper();
      final owner = Object();
      final pending = Completer<void>();
      final seeks = <Duration>[];
      var errors = 0;
      stepper.step(
        owner: owner,
        position: const Duration(seconds: 95),
        duration: const Duration(seconds: 100),
        delta: const Duration(seconds: 30),
        seek: (target) {
          seeks.add(target);
          return pending.future;
        },
        onError: () => errors++,
      );
      expect(seeks.single, const Duration(seconds: 100));
      stepper.reset();
      stepper.step(
        owner: Object(),
        position: const Duration(seconds: 3),
        duration: const Duration(seconds: 100),
        delta: const Duration(seconds: -30),
        seek: (target) async {
          seeks.add(target);
          throw StateError('disconnected');
        },
        onError: () => errors++,
      );
      await Future<void>.delayed(Duration.zero);
      pending.complete();
      await Future<void>.delayed(Duration.zero);
      expect(seeks, [const Duration(seconds: 100), Duration.zero]);
      expect(errors, 1);
    },
  );
}
