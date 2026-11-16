import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/photo_sorter/sort_session.dart';

void main() {
  test(
    'staging advances, revisiting replaces one decision, original list stays intact',
    () {
      final originals = ['a.jpg', 'b.jpg', 'c.jpg'];
      final session = SortSession(originals);
      originals.clear();
      session.stage('Favorites');
      expect(session.current, 'b.jpg');
      session.navigate(-1);
      session.stage('Share');
      expect(session.decisions, {'a.jpg': 'Share'});
      expect(session.photos, ['a.jpg', 'b.jpg', 'c.jpg']);
    },
  );
  test('navigation clamps and empty folders have no decision', () {
    final empty = SortSession([]);
    empty.navigate(100);
    empty.stage('Favorites');
    expect(empty.current, isNull);
    expect(empty.decisions, isEmpty);
    final session = SortSession(['one']);
    session.navigate(-1);
    session.stage('Favorites');
    session.navigate(99);
    expect(session.selected, 0);
  });
  test(
    'clearing affects only current item and exposed decisions cannot be changed',
    () {
      final session = SortSession(['a', 'b']);
      session.stage('Favorites');
      session.stage('Share');
      session.clearCurrent();
      expect(session.decisions, {'a': 'Favorites'});
      expect(() => session.decisions.clear(), throwsUnsupportedError);
      expect(() => session.select(2), throwsRangeError);
      expect(() => session.stage('  '), throwsArgumentError);
      session.clear();
      expect(session.decisions, isEmpty);
    },
  );
}
