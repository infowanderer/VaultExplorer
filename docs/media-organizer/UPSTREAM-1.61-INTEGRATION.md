# Upstream v1.61.0 integration candidate

Upstream tag: 93d75aa (v1.61.0). Organizer parent: 8f5e8a9.
Candidate version: 1.61.0+63 to avoid reusing installed preview version code 62.

Merged upstream gallery indexing, metadata editing, nomedia visibility, per-tab
music state, resume privacy curtain, vault compatibility and container tools.
Resolved four merge conflicts: retained both browser imports, advanced version,
adopted upstream segmented-index tests (flush now awaits writes), and retained
organizer toolbar round-trip assertions.

Fresh checks: 18 privacy/APK-checker unit tests and code boundaries pass.
Flutter dependency resolution/test commands stalled without output in this
workspace; no Flutter, Android build or runtime pass is claimed for this merge.
Upstream whitespace warnings remain, including patch-file context whitespace.

Release gates: audit metadata replaceFileFromChunks and gallery-index storage
against protected-storage policy; preserve originals for metadata edits; review
new BitLocker expansion/format/repair paths; run complete Flutter and native
tests, rebuild and verify signed preview APK, then device acceptance.
MetadataEditService currently streams into a sibling temp and replaces originals;
this inherited behavior has NOT been approved as satisfying organizer safety.

This branch is an unverified source candidate, not an installable update.
Build 62 remains the released APK.

## Follow-up: preview metadata writes blocked

Review confirmed that replaceFileFromChunks deletes a predictable .tmp path,
then deletes the original before renaming; this is not an atomic replacement
and cannot satisfy preservation/recovery requirements. Preview metadata UI now
explains the limitation and the service refuses embedded metadata and modified-
time writes before I/O. Organizer catalog tags/ratings remain available.

Fresh verification: 18 existing structural/privacy checker tests and code
boundaries pass. A preview-only timestamp refusal regression was added but has
not run: Flutter startup/dependency resolution is still blocked in the restored
workspace, whose package cache is absent. No new APK or full-suite pass claimed.
Run the regression with --dart-define=VAULTEXPLORER_PREVIEW=true. The common
replacement helper and other callers still require review; this guard is not a
claim that the entire inherited write surface is safe.
