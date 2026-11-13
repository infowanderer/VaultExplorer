# Protected media workflow — Android checkpoint 61, compact UI revision

This is the first write-enabled organizer build, following the read-only tablet
preview. Start with disposable photographs before using a valuable collection.
The implementation has automated synthetic-filesystem and UI coverage; device
storage-provider behavior and performance still need the hardware checks below.

## Use it

1. Open a local, SD or USB folder. Select media in the main gallery (long press),
   open an image/video, or choose **Sort photos** for a focused photo grid.
2. **Stars, Sort and Tags** appear together. **1–5** sets the selected image/video's
   rating; **T** edits tags without changing its rating or review state. Batch tag
   edits explicitly replace the selected files' tags. Text fields keep their keys.
3. **S / Sort** opens destinations: add a named folder, choose Copy (default) or
   Move, and choose the destination. **Alt+1–9** stages a copy to a saved folder.
   Photo sort mode advances after staging. A badge means planned, not transferred.
4. Open **Queue**, inspect paths and output names, and choose **Run queue**. This
   prepares and verifies the transfer, then runs it without an extra confirmation.
   Collisions and source changes still stop the operation. Resume and Undo act
   directly and retain their filesystem checks. No transfer runs merely by staging.
5. Photo sorter's **More** menu holds filters, review states/details (**R**), batch
   rename, collections/saved searches, rename reconciliation and Preferences.
   Delete candidate is metadata. Escape returns to the gallery with decisions saved.

The inherited browser/viewer **Delete** action permanently deletes. **More →
Preferences → Confirm permanent deletion** makes its confirmation optional (on by
default). This is distinct from organizer moves' recoverable Trash. Unreadable
protected preferences refuse deletion rather than assume prompting was disabled.

Previous arrow, mouse wheel, Ctrl zoom/seek, Escape slideshow/video and touch
controls remain. Backgrounding hides the sorter, cancels queued/active work and
requires explicit Resume. This is deliberately foreground work, not a persistent
Android background service. Source selection and the destination deck are restored
when reopening that folder; no library import is required.

### Button help and labels

The **More → Preferences → Button labels** switch changes organization
buttons between icons with labels and icons alone. Labels start enabled; the
choice is saved in the protected app preferences and follows you between folders.
Destination names remain visible in either mode. Hover over a toolbar/navigation
button with the mouse, or long press it with touch or pen, to show its tooltip.
Long pressing a toolbar button shows help without activating its action.
The small action strip wraps in narrow or split-screen windows. Advanced actions
remain secondary. The gallery refreshes saved reviews after returning from a
viewer; it does not overwrite newer session revisions from another window.

### Rename and collections

**Batch rename** previews up to 200 filenames, using `{name}`, `{ext}`,
`{counter:03}` and `{modified:yyyyMMdd}` (UTC modification date, not EXIF capture
date). Counter start/step and destination are configurable. Renamed copies are
the default; raw-path moves retain originals. Duplicate/unsafe names and sources
changed since preview are refused. Staging does not execute the rename.

**Collections and saved searches** keep references without moving media. Static
collections capture identity/content; dynamic searches cover protected reviews in
previously opened folders, not an automatic disk-wide library. Results currently
provide a read-only photo preview. Changed/unavailable references are reported,
not rebound by name. At most two collection previews inspect media concurrently.

## File safety

| Storage access | Copy | Interrupted transfer | Move / Undo |
| --- | --- | --- | --- |
| Direct filesystem access | Exclusive create; SHA-256 read-back | Verify recorded ownership and complete existing prefix before append | Allowed only with same-filesystem atomic no-overwrite rename; retained Trash |
| Android local/SD/USB document tree | Fresh name/ID checks; direct descriptors; SHA-256 read-back | A complete owned output can be rechecked; partial append is refused | Copy-only; provider move/undo is refused |

The picker prefers a usable direct path, otherwise keeps the granted document
tree. It accepts Android's external-storage provider, not arbitrary cloud
providers. Android permissions, filesystem capabilities and read-only media may
still refuse an action. Unknown provider sizes fail closed. Raw capacity is checked
when available, but storage may disappear or fill after a check.

A move copies and verifies the destination and source before retaining the
original under the source folder's `.MediaOrganizerTrash/<random-id>/` directory.
Undo verifies content and identity, restores an unoccupied original name, and
retains the sorted output in destination-side Trash. There is **no permanent
media deletion** in this organizer. Trash consumes space and is not automatically
emptied. Do not remove it while an operation may need recovery or undo.

Journal intent precedes file creation and quarantine; the creation receipt
precedes writing. A crash in that gap may leave an unowned empty output. Recovery
does not adopt or remove it. Source changes, modified partial outputs, renamed
outputs, occupied restore names and uncertain ownership stop automatic action.
Read-only reconciliation can acknowledge an already completed move/undo; it never
replays a filesystem mutation. Failed transfers retain all bytes and locations.
Raw creation, reserved Trash directory entries and encrypted journal publication
flush their parent directories. Storage that refuses required directory syncing
stops the operation; it does not silently receive a weaker durability guarantee.

## Privacy and architecture decisions

- Reuse the Flutter Android UI and native engine. Do not add a second Qt UI or a
  second cryptographic implementation to this app. Linux delivery remains later.
- Keep organizer logic separate from widgets and injected platform access. The
  pure Kotlin transfer engine runs on a serial worker; hashing and file I/O never
  run on Flutter's UI thread. Transfers use 256 KiB buffers, cleared after use.
- Sessions, destinations, ratings, tags and file fingerprints use the existing
  Keystore-backed AES-GCM protected metadata service. No plaintext JSON catalog
  or thumbnail/temp fallback is introduced. Invalid/unreadable protected state
  refuses editing instead of replacing it with an empty catalog.
- Per-operation journals are AES-GCM ciphertext in
  `noBackupFilesDir/organizer-journal-v1/<opaque-id>.enc`. AtomicFile's temporary
  and backup records contain ciphertext too. Plaintext serialization is encrypted
  before any file write, then durably flushed and read back. Privacy reset expires
  queued worker generations before clearing journals. It never deletes media.
- These encrypted app-owned records live **outside a media container**. Their
  Android Keystore key is device/app bound; they are not independently encrypted
  by the media-container password. UI locking is not cryptographic re-locking of
  that key. Uninstall, key invalidation or app-data clearing can lose history.
- Original files, chosen outputs and source-side Trash inherit their selected
  storage's protection. Ordinary SD/USB folders are not made encrypted by sorting
  them. This checkpoint excludes sorting inside mounted encrypted vaults; the
  host's existing vault viewer remains available.
- The existing strict scratch policy remains. Scratch-dependent recording,
  archive and audio/video export paths stay blocked; no disk fallback was added.
  Android/provider caches, OS snapshots, RAM, swap, compromised devices and other
  apps with access to the same media are outside this app-level guarantee. Full
  external-write tracing and all inherited host features have not been audited.
- No AI, telemetry, account, server or network permission was added. SMB/rclone
  remain deferred. Existing optional host integrations are not new organizer
  guarantees. No permission for an external app or script is implied by a shortcut.

Current metadata is a bounded protected record per folder, not a scalable SQLite
tag catalog: at most 9 destinations, 200 staged decisions, 128 folder sessions,
256 KiB per folder record, and 2,000 journal plans. Limits refuse additional data
without evicting existing data. Collections allow 32 groups, 500 members per group,
1,000 total references and the same 256 KiB record bound. Large catalogs need a
versioned encrypted SQLite implementation before limits are raised. Sessions read
schema 1 and write schema 2; earlier APKs refuse schema 2 rather than erase it.

Quick ratings/tags inspect filesystem identity, size and modification time rather
than hashing a large video. These are metadata-bound reviews, not proof of equal
content; same-size/time in-place edits can evade that lightweight check. Such
reviews never auto-relocate. Transfer preparation obtains a full content binding.
Replacing a path archives the earlier review as an explicit candidate, visible
under **More → Earlier file reviews**; limits refuse edits rather than discard it.

Strong identity tracking follows a rename **within the opened folder** only
when filesystem identity and full SHA-256 both match uniquely. Changed files and
ambiguous/hard-link/hash-only matches remain unresolved review candidates. Saving
a candidate review explicitly reapplies it to the current file. Verified app
transfers carry reviews to the destination only when content matches. This is not
global discovery across arbitrary folders, drives, unavailable devices or SAF URI
changes. Strong matching is kept separate from uncertain suggestions.

## Roadmap coverage

| ID | This checkpoint | Remaining |
| --- | --- | --- |
| F01 | Named destination deck, shortcuts, persistent folders | Fuzzy routing, presets, inline folder creation |
| F02 / A02 | Visible queue + Run queue, serial progress, cancellation, journal, guarded recovery/undo | Durable background scheduling and provider-specific capabilities |
| F03 / A08 | Review states, stars, filters, folder session restoration | Larger catalog/session management |
| F04 | Protected tags, suggestions, batch editing, text filtering | SQLite tag catalog, xattr/filename export |
| F08 | Batch templates/counters/UTC modification date, previews, collision/source checks, combined routing | EXIF capture-date templates and larger batches |
| F09 | Protected static photo collections, saved review searches and read-only result previews | Scalable catalog, full media playback/actions within collections |
| A01 / A07 | Scoped strong identity tracking and storage-specific transfer policy | Cross-folder relocation reconciliation, unavailable device tracking |
| F05 / F06 / F11 / F12 | Existing video viewer only | Contact sheets, safe clip extraction, scene sampling and storyboard wall |
| F07 / F10 / F13 / F14 | Not implemented by this checkpoint | Duplicate duel, rules/CLI, tag views, sync/backup |
| A03 / A04 / A05 / A06 | Existing host capabilities only | Organizer edit decisions, command palette/remapping/scripts, metadata inspector and persistent jobs |

## Build and validation

Use Java 21, the pinned `.flutter` submodule, and the Android SDK/NDK versions in
the repository. Follow [TABLET-PREVIEW.md](TABLET-PREVIEW.md) for the full ARM64
release build and signing checks. The original `1.50.0+61` needed a full native
build. The guarded Dart updater now pins that exact full build, verifies native
sources/engine payloads and preserves its Android/native entries byte-for-byte.
It must refuse any future native-source or dependency change. See the build
receipt for actual validation and artifact provenance of this UI revision.
An upgrade must use the same preview package and signing certificate; no uninstall
is needed. An unsigned build is not an installable release.

Run the full Flutter suite and analyzer, `scripts/check_code_boundaries.py`, the
Python privacy guards, the host `no_replace_test.cpp` and `ram_scratch_test.cpp`
fixtures, and Gradle `:app:testDebugUnitTest`. CI includes these boundaries.
Test doubles validate UI/domain behavior; real JVM temporary-filesystem tests
exercise copying, collisions, corruption, cancellation, Trash and undo. The host
rename fixture exercises the actual Linux no-overwrite syscall, Unicode filenames
and occupied symlink destinations. They do not simulate Android document providers.

Hardware acceptance, using synthetic fixtures only:

- Internal/SD/USB: copy, unplug, read-only storage, full storage, revoked grant.
- Introduce a destination collision after preparation; verify no overwrite.
- Pause/background/force-stop during a large transfer; inspect both locations,
  resume supported outputs, and verify completed bytes independently.
- Direct path: move, inspect source Trash, undo, then modify an output and check
  undo is refused. Check an occupied source name is never replaced.
- Repeat with Book Cover keyboard/trackpad, S Pen, touch, DeX and split screen.
- Trace app/provider I/O and inspect private metadata/atomic backups for plaintext.
  These hardware/privacy-trace checks remain open, not passed by inference.
