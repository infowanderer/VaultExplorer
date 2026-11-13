/// Photo-sorting decisions only. This model never performs file I/O.
/// Addresses are scoped to one open storage session, not stable file identities.
class SortSession {
  SortSession(Iterable<String> photos) : photos = List.unmodifiable(photos);

  final List<String> photos;
  final Map<String, String> _decisions = {};
  int _selected = 0;
  int get selected => _selected;
  String? get current => photos.isEmpty ? null : photos[_selected];
  Map<String, String> get decisions => Map.unmodifiable(_decisions);

  void select(int index) {
    if (index < 0 || index >= photos.length) {
      throw RangeError.index(index, photos);
    }
    _selected = index;
  }

  void navigate(int delta) {
    if (photos.isEmpty) return;
    _selected = (_selected + delta).clamp(0, photos.length - 1);
  }

  void stage(String destination) {
    if (current == null) return;
    if (destination.trim().isEmpty) throw ArgumentError('Empty destination');
    _decisions[current!] = destination;
    navigate(1);
  }

  void restore({String? selected, Map<String, String> decisions = const {}}) {
    _decisions
      ..clear()
      ..addEntries(
        decisions.entries.where((entry) => photos.contains(entry.key)),
      );
    final index = selected == null ? -1 : photos.indexOf(selected);
    _selected = index < 0 ? 0 : index;
  }

  void clearCurrent() => _decisions.remove(current);
  void clear() => _decisions.clear();
}
