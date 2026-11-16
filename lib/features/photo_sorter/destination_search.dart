/// Rank saved destination labels, retaining their original shortcut indices.
/// Pure text matching: no directory scan, persistence or external service.
List<int> rankDestinations(List<String> labels, String query) {
  final words = query.trim().toLowerCase().split(RegExp(r'\s+'));
  if (query.trim().isEmpty) return List.generate(labels.length, (i) => i);
  final matches = <({int index, int score})>[];
  for (var index = 0; index < labels.length; index++) {
    final label = labels[index].toLowerCase();
    var score = 0;
    var matched = true;
    for (final word in words) {
      final part = _score(label, word);
      if (part == null) {
        matched = false;
        break;
      }
      score += part;
    }
    if (matched) matches.add((index: index, score: score));
  }
  matches.sort((a, b) {
    final order = a.score.compareTo(b.score);
    return order == 0 ? a.index.compareTo(b.index) : order;
  });
  return matches.map((entry) => entry.index).toList();
}

int? _score(String label, String word) {
  if (label == word) return 0;
  if (label.startsWith(word)) return 100 + label.length - word.length;
  final at = label.indexOf(word);
  if (at >= 0) {
    final boundary = RegExp(r'[\s/_\-]').hasMatch(label[at - 1]);
    return (boundary ? 200 : 300) + at + label.length - word.length;
  }
  var cursor = 0, first = -1, last = -1;
  for (final point in word.runes) {
    final found = label.indexOf(String.fromCharCode(point), cursor);
    if (found < 0) return null;
    if (first < 0) first = found;
    cursor = found + String.fromCharCode(point).length;
    last = cursor;
  }
  return 1000 + first + (last - first - word.length) * 10;
}
