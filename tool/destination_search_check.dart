import '../lib/features/photo_sorter/destination_search.dart';

void main() {
  var checks = 0;
  void check(bool value, String reason) {
    if (!value) throw StateError(reason);
    checks++;
  }

  const labels = [
    'Vacation beach',
    'Beach',
    'My Favorites',
    'Vacation mountains',
    'BEACH',
  ];
  check(
    rankDestinations(labels, '').join(',') == '0,1,2,3,4',
    'Empty query preserves destination order',
  );
  check(
    rankDestinations(labels, ' beach ').take(2).join(',') == '1,4',
    'Exact matches rank first with stable ties',
  );
  check(
    rankDestinations(labels, 'myfav').single == 2,
    'Subsequence crosses spaces',
  );
  check(
    rankDestinations(labels, 'bea vac').single == 0,
    'Every search word matches, in either order',
  );
  check(
    rankDestinations(labels, 'mount beach').isEmpty,
    'Unmatched words refuse partial results',
  );
  check(
    rankDestinations(labels, 'zzzz').isEmpty,
    'No result is not a fallback destination',
  );
  check(
    rankDestinations(labels, 'FAVORITES').single == 2,
    'Matching ignores case',
  );
  check(
    rankDestinations(['Bébé', 'Photos'], 'bé').single == 0,
    'Unicode labels remain searchable',
  );
  check(rankDestinations([], 'a').isEmpty, 'Empty deck is safe');
  check(
    rankDestinations(labels, 'myfav').single == 2,
    'Filtering retains original Alt shortcut index',
  );
  print('$checks destination-search checks passed');
}
