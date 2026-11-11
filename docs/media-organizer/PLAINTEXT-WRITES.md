# Reduce external plaintext staging

Changes are in the draft integration branch, not an installed Android release.
No personal media or existing temporary files were modified or deleted in this development session. At runtime, the metadata migration described below can remove its verified legacy JSON files.

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

This is not a complete no-external-writes guarantee. These four small metadata
collections now use the existing Android Keystore-backed AES-GCM store:

| Collection | Legacy plaintext file | Protected record key |
| --- | --- | --- |
| Container catalog | `containers_v2.json` | `private_metadata_containers_v1` |
| External storage names/paths/URIs | `external_storages.json` | `private_metadata_external_storages_v1` |
| Local reader recents | `discrete_mode_recents.json` | `private_metadata_recents_v1` |
| Local bookmarks and pins | `decoy_local_marks.json` | `private_metadata_local_marks_v1` |

`SecureMetadataStore` serializes operations per record, including updates from
multiple instances. New writes never create a plaintext metadata file. Migration
validates JSON collection shape and the 256 KiB limit, requires a successful native
commit and an exact decrypted read-back, then checks that the legacy file still
matches before deleting it. Changed/unreadable files are retained. This check
coordinates this app's callers; it cannot prevent a different process racing the
final filesystem check. An existing encrypted record that cannot be decrypted is
not treated as an absent record. Failed persistence, corruption and size limits
never trigger plaintext fallback. Malformed container records cannot trigger a
replacement catalog or credential deletion; malformed external-storage entries
cannot be replaced by an empty catalog.

These encrypted records live **outside the media container**, in app-private
SharedPreferences. Their fixed record names, lengths and access patterns remain
visible. The key belongs to Android Keystore; hardware backing depends on the
device. This is device-bound at-rest protection, **not** independent vault-password
protection. Vault locking does not revoke this app's ability to decrypt metadata.
Uninstall, key loss and device transfer can make it unrecoverable; this work does
not introduce a portable encrypted backup or key recovery mechanism.

Legacy files left by a failed cleanup, stale `.tmp` siblings and old cache/log
artifacts are not automatically swept. Deletion does not prove erasure on flash.
Existing secure-preference key names can encode vault identifiers/URIs even when
the values are encrypted; that key-namespace migration remains open. Existing
settings/lock behavior, logging, third-party providers, and OS artifacts need a
broader privacy audit. Ordinary storage folders remain ordinary plaintext storage.
The change does not encrypt the user's existing media in place.

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
  2.3.20 and run with JUnit 4.13.2 on the available Java runtime. The same
  **15 tests also pass through the real Android Gradle task**
  `:app:testDebugUnitTest --tests 'com.aeidolon.vaultexplorer.privacy.*'`
  (0 failures/errors/skips). These remain JVM tests, not device instrumentation.
- 10 structural privacy/identity guards pass (`python3 tool/privacy/no_staging_test.py`):
  no temp/cache/extract fallback in document provider, no cache staging in export
  handlers, no filesystem dependency in the stream helper, and no plaintext writer
  in the four migrated metadata services. These checks are not
  device-level I/O tracing or proof about indirect calls. A dedicated CI job now
  runs these guards and the standalone host RAM-scratch checks, without needing
  Android or Flutter setup. Local commands pass; no remote CI result is claimed.
- Host C++ tests pass for anonymous RAM descriptors, CLOEXEC, read/write bounds,
  per-file and aggregate limits, and descriptor/budget cleanup. The modified
  `fv_cryfs_vault.cpp` passes host C++20 syntax checking. With the actual NDK
  28.2.13676358 compiler, both the helper test source and CryFS translation unit
  also pass ARM64/API-26 syntax checking. This does not execute them on Android.
- Final full Flutter run: **3,815 tests pass**, plus 4 preview-identity tests. The initial run found one stale
  toolbar round-trip test, also reproduced against untouched baseline `fbabd06`.
  Its old top-bar expectation contradicted the current default and adjacent tests
  placing that button in More. The corrected test checks that both placements
  survive a round-trip; no production viewer behavior changed. Production metadata
  sources have no analyzer issues; expanded test analysis reports one pre-existing
  super-parameter suggestion.
- `git diff --check` and `scripts/check_code_boundaries.py` pass.
- 14 metadata-store contract tests and 4 external-storage repository tests pass,
  plus catalog-corruption, migration, bookmark, recent-file and dashboard regression
  coverage. These use fake native storage; they do not test Keystore cryptography.
- Full ARM64 release native linking, Flutter AOT assembly, Kotlin/Java compilation,
  R8, release lint and APK packaging pass. The signed isolated preview passes
  packaged identity, provider, ABI, no-network, signature and ZIP-alignment checks.
  Seventeen Android Gradle privacy/provider tests pass; five APK-validator regression
  tests pass. See [TABLET-PREVIEW.md](TABLET-PREVIEW.md) for exact artifact checks.
  Bitmap codec/device-provider integration tests and Tab S8 Ultra I/O tracing have
  not run. This is a test preview, not a completed secure-organizer release.
  Official SDK platform 37.0, build-tools 37.0.0 and NDK 28.2.13676358 were
  retrieved and checksum-verified during toolchain provisioning. Their presence
  does not establish a successful Android integration build. Original SDK pins
  have not been lowered.
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
