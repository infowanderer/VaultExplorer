import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/photo_sorter/organizer.dart';
import 'organizer_fakes.dart';

void main() {
  test(
    'old sessions default to labels without creating a preference record',
    () async {
      final storage = ProtectedMemory();
      expect(await storage.repository().loadButtonLabels(), isTrue);
      expect(storage.records, isEmpty);
    },
  );
  test('invalid protected display preferences are never replaced', () async {
    final storage = ProtectedMemory();
    storage.records['private_metadata_organizer_ui_v1'] =
        '{"version":99,"showButtonLabels":false}';
    final before = Map.of(storage.records);
    await expectLater(
      storage.repository().saveButtonLabels(true),
      throwsFormatException,
    );
    expect(storage.records, before);
  });
  late ProtectedMemory protected;
  late FixtureBridge bridge;
  late OrganizerController controller;
  const destination = OrganizerFolder('/storage/fixtures/keep', '', 'Keep');
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
  test(
    'failed label persistence retains the last setting and staged decisions',
    () async {
      await controller.open();
      final before = controller.state.toJson();
      protected.persist = false;
      await controller.setButtonLabels(false);
      expect(controller.showButtonLabels, isTrue);
      expect(controller.error, isNotNull);
      expect(controller.state.toJson(), before);
      expect(bridge.executions, 0);
      protected.persist = true;
      await controller.setButtonLabels(false);
      expect(controller.showButtonLabels, isFalse);
      expect(await protected.repository().loadButtonLabels(), isFalse);
    },
  );
  tearDown(() => controller.dispose());
  test(
    'destinations, decisions, selected photo and reviews survive a new controller',
    () async {
      await controller.open();
      await controller.addDestination(destination);
      await controller.review(
        ['a.jpg'],
        const PhotoReview(
          state: ReviewState.keep,
          rating: 4,
          tags: ['vacation'],
        ),
      );
      expect(
        await controller.stage(
          ['a.jpg'],
          destination,
          move: false,
          nextSelected: 'b.jpg',
        ),
        isTrue,
      );
      expect(bridge.executions, 0);
      final next = OrganizerController(
        root: controller.root,
        folder: '',
        photos: controller.photos,
        repository: protected.repository(),
        bridge: bridge,
      );
      addTearDown(next.dispose);
      await next.open();
      expect(next.state.selected, 'b.jpg');
      expect(next.state.decisions.keys, ['a.jpg']);
      expect(next.state.destinations.single.name, 'Keep');
      expect(next.state.reviews['a.jpg']!.tags, ['vacation']);
      expect(next.state.reviews['a.jpg']!.rating, 4);
      expect(next.ready, isTrue);
    },
  );
  test('no commit happens until explicit preparation and commit', () async {
    await controller.open();
    await controller.stage(['a.jpg'], destination, move: false);
    await controller.commit();
    expect(bridge.executions, 0);
    expect(await controller.prepare(), isTrue);
    expect(bridge.preparations, 1);
    expect(bridge.executions, 0);
    await controller.commit();
    expect(bridge.executions, 1);
    expect(controller.state.decisions, isEmpty);
    expect(controller.jobs.single['state'], 'complete');
  });
  test('a collision stops preview and cannot turn into a copy', () async {
    await controller.open();
    await controller.stage(['a.jpg'], destination, move: false);
    bridge.refusePreparation = true;
    expect(await controller.prepare(), isFalse);
    await controller.commit();
    expect(bridge.executions, 0);
    expect(controller.state.decisions.length, 1);
    expect(controller.error, isNotNull);
  });
  test(
    'failed protected writes keep the last saved decisions and never transfer',
    () async {
      await controller.open();
      await controller.addDestination(destination);
      protected.persist = false;
      expect(
        await controller.stage(['a.jpg'], destination, move: true),
        isFalse,
      );
      expect(controller.state.decisions, isEmpty);
      expect(bridge.executions, 0);
      expect(controller.error, contains('Could not safely stage'));
    },
  );
  test(
    'present but unreadable protected data cannot reset the session',
    () async {
      await controller.open();
      await controller.addDestination(destination);
      final before = Map.of(protected.records);
      protected.available = false;
      final next = OrganizerController(
        root: controller.root,
        folder: '',
        photos: controller.photos,
        repository: protected.repository(),
        bridge: bridge,
      );
      addTearDown(next.dispose);
      await next.open();
      expect(next.ready, isFalse);
      expect(next.error, isNotNull);
      expect(protected.records, before);
    },
  );
  test('concurrent session revisions reject stale overwrites', () async {
    await controller.open();
    final repo = protected.repository();
    final key = controller.key!;
    final a = await repo.load(key), b = await repo.load(key);
    a.selected = 'a.jpg';
    await repo.save(key, a);
    b.selected = 'b.jpg';
    await expectLater(repo.save(key, b), throwsStateError);
    expect((await repo.load(key)).selected, 'a.jpg');
  });
  test(
    'invalid new values and corrupt index are refused before replacement',
    () async {
      await controller.open();
      final repo = protected.repository();
      final key = controller.key!;
      final bad = controller.state.clone()
        ..reviews['a.jpg'] = const PhotoReview(rating: 99);
      await expectLater(repo.save(key, bad), throwsFormatException);
      final before = Map.of(protected.records);
      protected.records['private_metadata_organizer_index_v1'] = '{broken';
      await expectLater(repo.sessionKey('/new', ''), throwsFormatException);
      expect(protected.records[key], before[key]);
    },
  );
  test('SAF sources offer copies but refuse destructive moves', () async {
    final saf = OrganizerController(
      root:
          'content://com.android.externalstorage.documents/tree/primary%3APictures',
      folder: '',
      photos: ['a.jpg'],
      repository: protected.repository(),
      bridge: bridge,
    );
    addTearDown(saf.dispose);
    await saf.open();
    expect(await saf.stage(['a.jpg'], destination, move: true), isFalse);
    expect(bridge.inspections, 0);
    expect(await saf.stage(['a.jpg'], destination, move: false), isTrue);
    expect(bridge.inspections, 1);
  });
  test(
    'pause cancels active native work and stops before the next queued file',
    () async {
      await controller.open();
      await controller.stage(['a.jpg', 'b.jpg'], destination, move: false);
      await controller.prepare();
      bridge.executeGate = Completer<Map<String, dynamic>>();
      final work = controller.commit();
      await Future<void>.delayed(Duration.zero);
      controller.pause();
      bridge.executeGate!.complete({'state': 'interrupted'});
      await work;
      expect(bridge.executions, 1);
      expect(bridge.cancellations, 1);
      expect(controller.state.decisions.length, 2);
    },
  );
  test(
    'delete-candidate is review metadata only and filters are deterministic',
    () async {
      await controller.open();
      await controller.review(
        ['a.jpg'],
        const PhotoReview(
          state: ReviewState.deleteCandidate,
          rating: 3,
          tags: ['Colorado'],
        ),
      );
      expect(
        controller.matches('a.jpg', 'colorado', ReviewState.deleteCandidate, 3),
        isTrue,
      );
      expect(controller.matches('a.jpg', '', ReviewState.keep, 0), isFalse);
      expect(controller.matches('a.jpg', '', null, 4), isFalse);
      expect(bridge.executions, 0);
      expect(bridge.undos, 0);
    },
  );
  test(
    'renaming a staged output invalidates its prior plan; traversal is rejected',
    () async {
      await controller.open();
      await controller.stage(['a.jpg'], destination, move: false);
      await controller.prepare();
      await controller.renameDecision('a.jpg', '../unsafe.jpg');
      expect(controller.state.decisions['a.jpg']!['name'], 'a.jpg');
      await controller.renameDecision('a.jpg', 'vacation-01.jpg');
      expect(controller.state.decisions['a.jpg']!['jobId'], isNull);
      expect(controller.state.decisions['a.jpg']!['name'], 'vacation-01.jpg');
      await controller.commit();
      expect(bridge.executions, 0);
    },
  );
  test(
    'incoming review is recovered only for the recorded identity and exact content',
    () async {
      bridge.rows.add({
        'id': 'incoming',
        'source': {'root': '/elsewhere', 'path': 'old.jpg'},
        'created': {'root': '/storage/fixtures', 'path': '/a.jpg'},
        'state': 'complete',
        'move': false,
        'createdIdentity': 'fixture:42',
        'sha256':
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'annotation': jsonEncode(
          const PhotoReview(
            state: ReviewState.keep,
            rating: 5,
            tags: ['beach'],
          ).toJson(),
        ),
      });
      await controller.open();
      for (
        var i = 0;
        i < 10 && controller.state.reviews['a.jpg'] == null;
        i++
      ) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(controller.state.reviews['a.jpg']!.tags, ['beach']);
      expect(
        (await protected.repository().load(
          controller.key!,
        )).reviews['a.jpg']!.rating,
        5,
      );
    },
  );
  test(
    'verified within-folder rename restores notes and invalidates staged plans',
    () async {
      await controller.open();
      await controller.review(
        ['a.jpg'],
        const PhotoReview(
          state: ReviewState.keep,
          rating: 5,
          tags: ['mountains'],
        ),
      );
      await controller.stage(['a.jpg'], destination, move: false);
      await controller.prepare();
      bridge.versionsByPath['b.jpg'] = {
        'identity': 'fixture:99',
        'size': 9,
        'modified': 1,
      };
      final renamed = OrganizerController(
        root: controller.root,
        folder: '',
        photos: ['renamed.jpg', 'b.jpg'],
        repository: protected.repository(),
        bridge: bridge,
      );
      addTearDown(renamed.dispose);
      await renamed.open();
      for (var i = 0; i < 30 && renamed.verifyingReviews; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(renamed.reviewFor('renamed.jpg')!.tags, ['mountains']);
      expect(renamed.state.reviews.containsKey('a.jpg'), isFalse);
      expect(renamed.state.decisions['renamed.jpg']!['jobId'], isNull);
      expect(
        renamed.state.fingerprints['renamed.jpg']!['previousPath'],
        'a.jpg',
      );
      expect(bridge.executions, 0);
    },
  );
  test(
    'same pathname with changed contents retains a candidate without trusting its review',
    () async {
      await controller.open();
      await controller.review([
        'a.jpg',
      ], const PhotoReview(state: ReviewState.keep, rating: 4));
      bridge.hashesByPath['a.jpg'] = '${"b" * 64}';
      final next = OrganizerController(
        root: controller.root,
        folder: '',
        photos: controller.photos,
        repository: protected.repository(),
        bridge: bridge,
      );
      addTearDown(next.dispose);
      await next.open();
      for (var i = 0; i < 30 && next.verifyingReviews; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(next.reviewFor('a.jpg'), isNull);
      expect(next.reviewWarnings['a.jpg'], isNotNull);
      expect(next.state.reviews['a.jpg']!.rating, 4);
      expect(next.matches('a.jpg', '', ReviewState.keep, 0), isFalse);
    },
  );
  test('ambiguous identity matches do not reassign a missing review', () async {
    await controller.open();
    await controller.review(['a.jpg'], const PhotoReview(rating: 4));
    final ambiguous = OrganizerController(
      root: controller.root,
      folder: '',
      photos: ['one.jpg', 'two.jpg'],
      repository: protected.repository(),
      bridge: bridge,
    );
    addTearDown(ambiguous.dispose);
    await ambiguous.open();
    for (var i = 0; i < 30 && ambiguous.verifyingReviews; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(ambiguous.state.reviews.keys, ['a.jpg']);
    expect(ambiguous.reviewWarnings, isNotEmpty);
  });
  test(
    'provider handles normalize without assuming raw and SAF are the same file',
    () {
      expect(
        organizerAddress('/storage/fixtures/keep', '/a.jpg'),
        organizerAddress('/storage/fixtures', 'keep/a.jpg'),
      );
      expect(
        organizerAddress(
          'content://com.android.externalstorage.documents/tree/primary%3A',
          'Pictures/a.jpg',
        ),
        'com.android.externalstorage.documents:primary:Pictures/a.jpg',
      );
      expect(
        organizerAddress('/storage/fixtures', 'a.jpg'),
        isNot(
          organizerAddress(
            'content://com.android.externalstorage.documents/tree/primary%3A',
            'a.jpg',
          ),
        ),
      );
    },
  );
}
