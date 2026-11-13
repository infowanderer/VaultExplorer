import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/photo_sorter/organizer_catalog.dart';
import 'organizer_fakes.dart';

MediaReference media(String root, String path) => MediaReference(
  root: root,
  path: path,
  identity: '$root:$path',
  sha256: 'a' * 64,
  size: 123,
  modified: 0,
);
void main() {
  test(
    'collections span folders without moving files; removing a collection keeps other records',
    () async {
      final protected = ProtectedMemory();
      final catalog = protected.repository().catalog;
      final first = await catalog.create(
        'Vacation',
        members: [
          media('/internal', 'beach.jpg'),
          media('/usb', 'trip/mountain.jpg'),
        ],
      );
      final other = await catalog.create('Keep');
      expect((await catalog.list()).last.members.length, 2);
      await catalog.remove(first);
      expect((await catalog.list()).single.id, other);
    },
  );
  test(
    'adding the same media reference updates it without duplicates',
    () async {
      final catalog = ProtectedMemory().repository().catalog;
      final item = media('/internal', 'photo.jpg');
      final id = await catalog.create('Keep', members: [item]);
      await catalog.addMembers(id, [item]);
      expect((await catalog.list()).single.members.length, 1);
    },
  );
  test('duplicate names and failed writes retain the last catalog', () async {
    final protected = ProtectedMemory();
    final catalog = protected.repository().catalog;
    await catalog.create('Keep');
    final before = Map.of(protected.records);
    await expectLater(catalog.create('KEEP'), throwsFormatException);
    expect(protected.records, before);
    protected.persist = false;
    await expectLater(catalog.create('New collection'), throwsStateError);
    expect(protected.records, before);
  });
  test(
    'saved filters match case-insensitive text, state and minimum rating',
    () {
      const filter = CollectionFilter(
        query: 'beach',
        reviewState: 'keep',
        minimumRating: 4,
      );
      expect(
        filter.matches(
          path: 'trip/a.jpg',
          state: 'keep',
          rating: 5,
          tags: ['Beach'],
        ),
        isTrue,
      );
      expect(
        filter.matches(
          path: 'trip/beach.jpg',
          state: 'sortLater',
          rating: 5,
          tags: [],
        ),
        isFalse,
      );
      expect(
        filter.matches(
          path: 'trip/beach.jpg',
          state: 'keep',
          rating: 3,
          tags: [],
        ),
        isFalse,
      );
    },
  );
  test(
    'references require both identity and content, not a matching path alone',
    () {
      final item = media('/internal', 'photo.jpg');
      expect(
        item.matches({
          'identity': item.identity,
          'sha256': 'a' * 64,
          'size': 123,
        }),
        isTrue,
      );
      expect(
        item.matches({
          'identity': item.identity,
          'sha256': 'b' * 64,
          'size': 123,
        }),
        isFalse,
      );
    },
  );
}
