import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/photo_sorter/rename_plan.dart';

void main() {
  final date = DateTime.utc(2026, 7, 4, 12, 30).millisecondsSinceEpoch;
  final files = [
    RenameInput('trip/Beach.JPG', date),
    RenameInput('trip/Mountain.jpg', date),
  ];
  test('counter templates preserve the explicit stable input order', () {
    final rows = buildRenamePlan(
      files,
      'Vacation-{counter:03}.{ext}',
      start: 7,
      step: 2,
    );
    expect(rows.map((r) => r.name), ['Vacation-007.JPG', 'Vacation-009.jpg']);
    expect(rows.every((r) => r.error == null), isTrue);
  });
  test('modified timestamps use UTC and name retains the original stem', () {
    final row = buildRenamePlan([
      files.first,
    ], '{modified:yyyyMMdd_HHmmss}-{name}.{ext}').single;
    expect(row.name, '20260704_123000-Beach.JPG');
  });
  test('case-insensitive collisions are explicit preview errors', () {
    final rows = buildRenamePlan(files, 'Photo.jpg');
    expect(rows.every((r) => r.error != null), isTrue);
  });
  test(
    'unsafe names, bad tokens and path escapes cannot become valid output',
    () {
      expect(
        buildRenamePlan(files, '../{name}.{ext}').every((r) => r.error != null),
        isTrue,
      );
      for (final template in [
        '{captureDate}',
        '{counter:99}',
        '{modified:yyyy/MM}',
        '{name',
      ]) {
        expect(() => buildRenamePlan(files, template), throwsFormatException);
      }
      expect(validOrganizerName('photo.jpg '), isFalse);
      expect(validOrganizerName('a' * 241), isFalse);
      expect(validOrganizerName('é' * 121), isFalse);
    },
  );
  test(
    'unchanged names are identifiable and zero changes require no transfer',
    () {
      expect(
        buildRenamePlan(files, '{name}.{ext}').every((r) => r.unchanged),
        isTrue,
      );
    },
  );
}
