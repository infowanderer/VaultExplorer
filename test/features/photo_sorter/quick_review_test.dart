import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/photo_sorter/organizer.dart';
import 'organizer_fakes.dart';

void main() {
  late ProtectedMemory storage;
  late FixtureBridge bridge;
  late OrganizerController model;
  setUp(() async {
    storage = ProtectedMemory();
    bridge = FixtureBridge();
    bridge.version = {
      'identity': 'fixture:video',
      'size': 4 * 1024 * 1024 * 1024,
      'modified': 1000,
    };
    model = OrganizerController(
      root: '/fixture',
      folder: '',
      photos: ['movie.mp4'],
      bridge: bridge,
      repository: storage.repository(),
    );
    await model.open(verifyContent: false);
  });
  tearDown(() => model.dispose());

  test(
    'rating and tagging a large video use metadata reads and persist across sessions',
    () async {
      await model.setRating(['movie.mp4'], 4);
      await model.setTags(['movie.mp4'], ['vacation']);
      expect(bridge.fingerprintReads, 0);
      expect(model.reviewFor('movie.mp4')!.rating, 4);
      expect(model.state.fingerprints['movie.mp4']!['pending'], isTrue);
      await model.open(verifyContent: false);
      await model.verifySavedReviews(verifyContent: false);
      expect(model.reviewFor('movie.mp4')!.tags, ['vacation']);
      expect(bridge.fingerprintReads, 0);
    },
  );
  test('rating preserves a verified review state and tags', () async {
    await model.review([
      'movie.mp4',
    ], const PhotoReview(state: ReviewState.keep, rating: 2, tags: ['beach']));
    final reads = bridge.fingerprintReads;
    await model.setRating(['movie.mp4'], 5);
    expect(model.reviewFor('movie.mp4')!.state, ReviewState.keep);
    expect(model.reviewFor('movie.mp4')!.tags, ['beach']);
    expect(bridge.fingerprintReads, reads);
    expect(model.state.fingerprints['movie.mp4']!['pending'], isNull);
  });
  test(
    'replacement file starts fresh while the previous review is retained',
    () async {
      await model.setTags(['movie.mp4'], ['earlier-file']);
      await model.setRating(['movie.mp4'], 5);
      bridge.version = {
        ...bridge.version,
        'identity': 'fixture:replacement',
        'modified': 2000,
      };
      await model.setRating(['movie.mp4'], 2);
      expect(model.reviewFor('movie.mp4')!.rating, 2);
      expect(model.reviewFor('movie.mp4')!.tags, isEmpty);
      expect(model.state.previousReviews.single['path'], 'movie.mp4');
      expect((model.state.previousReviews.single['review'] as Map)['tags'], [
        'earlier-file',
      ]);
      final restored = await storage.repository().load(model.key!);
      expect(restored.previousReviews, hasLength(1));
    },
  );
  test(
    'a metadata-bound missing file cannot become an automatic relocation match',
    () async {
      await model.setRating(['movie.mp4'], 4);
      final relocated = OrganizerController(
        root: '/fixture',
        folder: '',
        photos: ['renamed.mp4'],
        bridge: bridge,
        repository: storage.repository(),
      );
      addTearDown(relocated.dispose);
      await relocated.open();
      await relocated.verifySavedReviews();
      for (var i = 0; i < 20 && relocated.verifyingReviews; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(relocated.state.reviews.keys, ['movie.mp4']);
      expect(relocated.reviewFor('renamed.mp4'), isNull);
      expect(relocated.reviewWarnings['movie.mp4'], isNotNull);
      expect(bridge.fingerprintReads, 0);
    },
  );
  test(
    'transfer preparation promotes a quick review to a full content binding',
    () async {
      await model.setRating(['movie.mp4'], 5);
      await model.stage(
        ['movie.mp4'],
        const OrganizerFolder('/dest', '', 'Destination'),
        move: false,
      );
      expect(await model.prepare(), isTrue);
      expect(bridge.fingerprintReads, 1);
      expect(model.state.fingerprints['movie.mp4']!['sha256'], 'a' * 64);
      expect(model.state.fingerprints['movie.mp4']!['pending'], isNull);
      expect(bridge.executions, 0);
    },
  );
  test(
    'source replacement before preparation refuses attaching an old review',
    () async {
      await model.setRating(['movie.mp4'], 5);
      await model.stage(
        ['movie.mp4'],
        const OrganizerFolder('/dest', '', 'Destination'),
        move: false,
      );
      bridge.version = {...bridge.version, 'modified': 9000};
      expect(await model.prepare(), isFalse);
      expect(bridge.preparations, 0);
      expect(bridge.executions, 0);
      expect(model.state.decisions['movie.mp4']!['jobId'], isNull);
    },
  );
  test(
    'failed quick review persistence retains prior data and starts no transfer',
    () async {
      await model.setRating(['movie.mp4'], 3);
      storage.persist = false;
      expect(await model.setTags(['movie.mp4'], ['not-saved']), isFalse);
      expect(model.reviewFor('movie.mp4')!.rating, 3);
      expect(model.reviewFor('movie.mp4')!.tags, isEmpty);
      expect(bridge.executions, 0);
    },
  );
  test(
    'schema accepts prior version and rejects malformed identity bindings',
    () {
      final legacy = OrganizerState().toJson()..['version'] = 1;
      expect(OrganizerState.fromJson(legacy).toJson()['version'], 2);
      for (final pending in ['true', 1, true]) {
        final corrupt = {
          ...legacy,
          'fingerprints': {
            'a.jpg': {
              'identity': 'id',
              'size': 1,
              'modified': 1,
              'pending': pending,
            },
          },
        };
        expect(() => OrganizerState.fromJson(corrupt), throwsFormatException);
      }
    },
  );
}
