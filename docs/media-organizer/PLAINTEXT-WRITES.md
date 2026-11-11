# Reduce external plaintext staging

Changes are in the draft integration branch, not an installed Android release.
No personal media or existing temporary files were modified or deleted.

## Removed staging paths

- **Document-provider image previews:** all image sizes use bounded vault input
  streams for bounds and sampled decode. The former `thumb_*` extraction fallback
  is removed. Unknown/empty sizes return no preview rather than a disk fallback.
  Requested preview edges are clamped to 64–2048 pixels. Existing memory admission
  control is applied before pixel decode; refusal/OOM returns no preview. Stream
  chunk arrays are cleared after use. This does not prove that codec/internal RAM
  copies are erased. Thumbnail failure logging no longer includes source paths or
  exception text in the changed provider paths.
- **Vault → SAF folder export:** read chunks go directly to the user-requested
  document; the `export_*` cache copy is removed. Existing destination names are
  refused rather than deleted. A failed attempt cleans up only its newly created
  document on a best-effort basis. Source files are never removed by this code.
- **Vault → single document-picker export:** same streaming transfer, no cache
  staging. Null output streams, read/write/flush/close errors cannot report success.
  The selected output may remain partial after failure; it is not deleted because
  a document returned by a provider must not be assumed disposable.

The final export is intentionally plaintext if the user selects an unencrypted
folder/provider. Removing a scratch copy does not encrypt the chosen destination.
Third-party document providers may have their own caches and network behavior.

## Transfer behavior

Reads and transfer buffers are capped at 256 KiB; temporary byte arrays are cleared
on success and failure. Unexpected EOF, oversized read responses and unknown sizes
fail rather than triggering disk extraction. Export cancellation is checked
between chunks, and bulk export retains per-chunk progress. Size is checked after
copy; this is not a full cryptographic consistency/read-back verification and does
not detect every same-size concurrent source modification. Atomic publication,
provider durability and general cross-app concurrent editing remain separate work.

`Inside container` continues to select the existing in-container thumbnail cache;
there is no newly introduced app-cache fallback. This patch addresses thumbnail
source staging even when a different app invokes the document provider.

## Additional hardening in this work session

- Legacy folder-vault copy entry points now use the existing memory-streaming
  adapter. Zero-byte copies are validated rather than using a cache spool; unknown
  size is refused. Native/disk-image imports write encrypted destination chunks
  directly, removing `vc_import_*` and `ve_copy_*` spools.
- A non-configurable strict-privacy staging policy denies remaining reviewed
  plaintext temp-file/directory creation. Archive actions and audio/video edit
  exports return `PRIVACY_BLOCKED` at entry, before output modification. Recording
  is rejected before recorder setup. Crop-to-aspect capture returns an explanatory
  failure; ordinary uncropped still capture is retained. Low-level staging sites
  also route through the denying factory as defense in depth.
- CryFS incremental-write staging no longer uses `mkstemp` followed by unlink.
  It now uses anonymous `memfd` RAM storage, limited to 32 MiB per pending file and
  128 MiB in aggregate. If unavailable or over budget, the write fails; it never
  falls back to private cache or `/tmp`. Large CryFS chunk writes may therefore
  be unavailable. OS swap, hibernation and compromised-process access are outside
  this application-level guarantee. Source files are not deleted by the helper.

### Remaining boundaries

This is not a complete no-external-writes guarantee. Existing app metadata includes
location names/URIs in `external_storages.json`, container records in
`containers_v2.json`, local recents and local bookmark/mark data. Those pre-existing
persistence paths were identified but are not encrypted or migrated by this patch.
Existing settings/logging, third-party providers, and OS artifacts still need a
broader privacy audit. No existing metadata/media was deleted or migrated.

Split-volume mirror fallback is also denied because the code cannot assume every
source container representation is encrypted. Direct provider access is retained.

Encrypted scratch (e.g. Quick Capture's ciphertext scratchpad), encrypted container
creation and empty filesystem capability
probes are deliberately not blocked merely because they use a temporary path.
Their complete security properties have not been audited here.

The disabled archive/recording/edit-export features can return only after they
use bounded memory or approved encrypted storage. This is an intentional feature
restriction in this development branch, not a claim that those workflows have
already been rebuilt with full functionality.

## Validation

- 15 JVM tests pass for the exact production stream/transfer source: bounded reads,
  buffer clearing, short reads, mark/reset, skip, cancellation, output/flush failure,
  empty input, closed streams, invalid ranges, encrypted-destination chunking,
  failed import writes/finalization and denial before scratch creation. Compiled with official Kotlin
  2.3.20 and run with JUnit 4.13.2 on the available Java runtime.
- 7 structural privacy guards pass (`python3 tool/privacy/no_staging_test.py`):
  no temp/cache/extract fallback in document provider, no cache staging in export
  handlers, no filesystem dependency in the stream helper. These checks are not
  device-level I/O tracing or proof about indirect calls.
- Host C++ tests pass for anonymous RAM descriptors, CLOEXEC, read/write bounds,
  per-file and aggregate limits, and descriptor/budget cleanup. The modified
  `fv_cryfs_vault.cpp` passes host C++20 syntax checking.
- `git diff --check` passes.
- Full Android integration compilation, bitmap codec tests, document-provider
  tests and Tab S8 Ultra I/O tracing have not run; SDK/NDK/device are unavailable.
  Keep this work in draft until those checks pass.

Android references checked:
https://developer.android.com/reference/android/graphics/BitmapFactory
https://developer.android.com/reference/android/content/ContentResolver

### Reproduce checks

```sh
python3 tool/privacy/no_staging_test.py
g++ -std=c++20 -Wall -Wextra -Werror tool/privacy/ram_scratch_test.cpp -o /tmp/ram-scratch-test
/tmp/ram-scratch-test
# On an Android-SDK-equipped development VM:
cd android
./gradlew :app:testDebugUnitTest --tests 'com.aeidolon.vaultexplorer.privacy.*'
```

The host executable contains synthetic fixtures only. No runtime app media is
placed in `/tmp` by these tests. Build a separate-ID test APK before real-device
checks; do not replace an existing installed app or erase its vault data.
