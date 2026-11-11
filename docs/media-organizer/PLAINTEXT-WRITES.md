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

## Remaining known external plaintext writes

Video/audio recording and editing, archive workflows, camera cropping, and legacy
backend copy/import fallback paths still exist. Most normal cross-backend copies
already stream in memory; the legacy fallback must not be described as every copy.
This patch is a reduction, not a global guarantee that no plaintext reaches private
storage. No camera/archive/editing capability was silently disabled.

## Validation

- 10 JVM tests pass for the exact production stream/transfer source: bounded reads,
  buffer clearing, short reads, mark/reset, skip, cancellation, output/flush failure,
  empty input, closed streams and invalid ranges. Compiled with official Kotlin
  2.3.20 and run with JUnit 4.13.2 on the available Java runtime.
- 3 structural privacy guards pass (`python3 tool/privacy/no_staging_test.py`):
  no temp/cache/extract fallback in document provider, no cache staging in export
  handlers, no filesystem dependency in the stream helper. These checks are not
  device-level I/O tracing or proof about indirect calls.
- `git diff --check` passes.
- Full Android integration compilation, bitmap codec tests, document-provider
  tests and Tab S8 Ultra I/O tracing have not run; SDK/NDK/device are unavailable.
  Keep this work in draft until those checks pass.

Android references checked:
https://developer.android.com/reference/android/graphics/BitmapFactory
https://developer.android.com/reference/android/content/ContentResolver
