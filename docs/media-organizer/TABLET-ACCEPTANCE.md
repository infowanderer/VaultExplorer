# Build 62: first tablet test

Install the signed ARM64 preview over the current preview; do not uninstall to
update. Confirm version 1.50.0 (62). No SDK or emulator is needed to test directly
on the Tab S8 Ultra. The APK is ARM64: an x86 emulator requires a separate build.

Use disposable media first. Generate synthetic photos with:

```sh
python3 tool/fixtures/make_tablet_photos.py /path/to/tablet-test.zip
```

Extract the ZIP on internal storage. Choose the generated Keep/Share/Later folders
as destinations. Leave the invalid JPEG in place: an error placeholder is expected.

## First pass

1. Open Photos and the sorter. Confirm thumbnails, portrait images and the rotated
   EXIF card display correctly. Hover or long-press buttons for help; enable labels
   under More → Preferences if useful.
2. Open a photo. Test arrows/wheel navigation and Ctrl zoom. Escape exits the
   viewer/slideshow; Escape from the sorter returns to the gallery.
3. Rate using 1–5; use T for tags and S for sorting. Return to the gallery and check
   that ratings/tags agree. Typing in a text field must not trigger shortcuts.
4. Stage copies, try destination search and Enter, then inspect the queue and run
   it. Sources must remain; destination bytes should match. Copy/move queue actions
   have no extra confirmation dialog. A pre-existing destination must survive.
5. On disposable fixtures only, try Move and Undo. Retain .MediaOrganizerTrash and
   partial outputs. Undo must refuse occupied restore names or changed files.
6. Stage another decision, background/reopen the app, and resume the organizer.
   Confirm saved decisions. During a larger disposable transfer, background the
   app and inspect Resume/Verify recovery before proceeding. Do not manually
   delete recovery files.
7. Make a second byte-identical copy of one test image with a different name.
   More → Find exact duplicates should group the pair and change no files.
8. Open a disposable video. Frames or V should pause it and show 6/12/24 previews.
   Tap a timestamp to seek; playback stays paused. Close/background during generation
   and confirm no stale frames return. Test normal and Ctrl skip settings, then Esc.

## Hardware pass

Repeat browsing and a disposable copy separately on microSD and USB. Test pen taps,
Book Cover keys/trackpad, landscape, portrait and DeX. During disposable transfers,
unplug a USB device: failure/recovery should be explicit, with no success claim or
silent overwrite. Reconnect before attempting recovery. Document-picker sources
support copies only; vault sorting remains disabled.

## Report only what failed

Send build number, storage type, view/action, expected result and actual result.
A screenshot helps; crop private filenames. Do not send personal media or raw logs
unless needed and reviewed. For a crash, note whether a queue was running and the
last visible action. Avoid uninstalling or clearing app data before recovery review.

## Privacy boundaries

Chosen ordinary media folders and source-side Trash are not automatically encrypted.
Organizer records use device Keystore protection outside containers, not the
container password. Contact-sheet buffers are memory-only with best-effort cleanup;
codec/GPU/OS memory is outside that guarantee. This checklist does not establish
that Android, document providers or external apps never write plaintext.

Previous release evidence is in BUILD-62-PROGRESS.md. Physical tablet, codecs,
DeX, pen and removable-provider checks remain unverified until exercised.
