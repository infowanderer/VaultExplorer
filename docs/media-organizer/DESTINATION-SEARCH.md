# Saved destination search

The Sort sheet now searches saved destination names with deterministic text
matching. Exact names rank first, followed by prefixes, words/substrings and
ordered subsequences. Multiple query words must all match; word order can vary.
For example, `myfav` finds `My Favorites`. Ties preserve deck order.

The displayed Alt+number remains the destination's original deck index, not its
filtered result position. Enter stages the first matching destination; no match
never falls back to another folder. This only stages a decision. Run queue still
executes transfers. The search performs no filesystem scan or persistent writes.
The existing nine-destination bound remains. This is saved-label search, not yet
an arbitrary folder search or a recents/frequency system.

Validation: the standalone Dart check covers ordering, whitespace/case, fuzzy
subsequences, multiword matches, empty/no-match decks, Unicode and original
shortcut indices. Run `dart tool/destination_search_check.dart`.

Two widget regression cases are added for filtered Enter routing and no-match
Enter at narrow width. They have **not been executed in the current environment**:
the restored Dart SDK works, but the app's Flutter dependency cache is missing.
The modified UI parses/formats successfully. Full widget checks and a full native
Android build remain required before releasing this UI or the preceding Undo fix.
The published APK has not changed.
