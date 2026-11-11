# Tablet photo organizer integration

Reviewed baseline: `fbabd06a73fa8d2bb928c648b9c0f307c2bf62c0` of
https://github.com/infowanderer/VaultExplorer (main).

## Verdict

Integrate as a Flutter feature in the user's VaultExplorer fork. Do not embed a
second Qt UI in the Android application. Keep the original C++ prototype as a
reference for file-operation invariants; it is not linked into this spike.
Flutter is a change from the provisional stack, justified by existing Android
storage code, viewers, USB handling, and a native cryptographic engine. Linux
support remains a later adapter/UI delivery task; Android-specific native code
in VaultExplorer does not become desktop-compatible merely because Flutter is.

Alternative: retain separate applications and open VaultExplorer's unlocked
containers through its DocumentsProvider. The manifest and provider implementation
make this a plausible integration seam, but grant/lock/revocation behavior needs
real-device tests. This remains an option if a focused standalone organizer is
preferred later. A second copy of its crypto engine is unnecessary.

## Evidence in source

- `lib/core/api/vault_file_io_api.dart`: dispatch for vault, raw-local and SAF
  operations; image thumbnail API reused by this feature.
- `lib/core/filesystem/local_storage_container.dart`: explicit distinction between
  raw local storage and content URIs; session volume IDs are not durable identity.
- `android/app/src/main/AndroidManifest.xml`: USB host support, document provider,
  backup disabled, and many permissions unrelated to organizing photos.
- `lib/data/services/thumbnail_cache_service.dart`: encrypted app-cache mode,
  in-container mode, and memory behavior. Not all metadata follows the same policy.
- `lib/data/services/media_index/media_index_storage.dart`: metadata stored inside
  the current container. On ordinary storage, 'inside' does not imply encryption.
- `lib/data/services/app_cache_encryption.dart`: persistent key cached in process;
  requires lifecycle audit before claiming independent passphrase re-lock.
- `lib/data/services/file_operation_service.dart`: existing copy/move/conflict
  machinery. Not reused to commit sorting decisions until journal, no-overwrite,
  verification, cleanup and source-removal windows are independently validated.
- README explicitly documents plaintext scratch in private cache for some features.
  Later wiping is not equivalent to never writing plaintext, nor guaranteed flash
  erasure. This is a mismatch with our strict workspace requirement.
- `pubspec.yaml`, `.gitmodules`, `android/app/build.gradle.kts`: Flutter pinned
  submodule, Dart 3.12+, Java 21, NDK 28.2.13676358, SDK/build-tools 37 in this tree.
- LICENSE: existing GPLv3 code; additions stay under the repository's license.

This is a targeted integration review, not an audit of every cryptographic format,
exported Android component, permission, dependency, or upstream security claim.
No AI dependency was added. A targeted source search found no references to
MLKit/TensorFlow/TFLite/OpenAI/ONNX in the searched app/native source paths; this
is not a complete dependency audit.

## Implemented first slice

Local/SD/USB browser toolbar → photo icon ('Sort photos (preview)') → responsive
photo grid → tap/pen selection → double tap or Space to preview → keys 1/2/3 stage
Favorites/Share/Sort later → queue dialog. Left/right and up/down navigation,
Backspace clear, Escape back, on-screen buttons and pinch zoom. The feature
reuses host thumbnail reads directly and adds no disk writes or persistent cache.

Only raw-local and SAF storage sessions expose this action. Archives, cross-folder
search, and encrypted vaults are excluded for now. Unsupported image decode shows
a placeholder. Native SD/USB permission and thumbnail behavior is untested here.
Buckets are provisional labels, NOT chosen filesystem folders. No transfer commit,
rename, delete, saved session, rating, or source identity reconciliation is wired.

Closing with pending decisions asks before discarding. Leaving the foreground
blanks the feature, discards decisions and requires reopening. This conservative
prototype behavior must be replaced by protected persistent session storage before
v1. It does not prove the host's global image cache or process memory is zeroed.
The rest of the host app still contains its original tools and permissions; this
is not yet a focused v1 build or a security-hardened fork.

## Version 1 acceptance criteria

- Tab S8 Ultra: landscape, portrait, split screen and DeX; test Book Cover Keyboard
  and trackpad, key repeat, focus, wheel/scroll and disconnect/reconnect.
- S Pen: real-device tap, drag/scroll, selection, pinch alongside touch. Button and
  hover behavior must be tested before assigning shortcuts; no Air Actions promise.
- Internal storage, microSD and USB: persisted access, read-only media, unplug,
  permission revocation, process death and restart. Detect unsupported providers.
- Protected catalog/cache/journal: actual path tracing and key/lock lifecycle tests;
  no unencrypted scratch fallback. User-requested exports clearly identified.
- Named real destinations, durable staging, previews, collision refusal, verified
  copy, recoverable move and safe conditional undo. No source deletion by default.
- No rclone/SMB in v1. No mandatory server or account. No AI.

Next implementation: protected organizer-session repository and actual destination
picker, then provider-capability checks and verified copy journal. Do not wire
staged labels straight to the existing cut/paste operations as a shortcut.

## Validation notes

Flutter startup initially triggered its cloud build-machine metadata probe and was
blocked by automatic review. Inspection of the pinned `bot_detector.dart` showed
CI mode bypasses that probe. CI=true and FLUTTER_SUPPRESS_ANALYTICS=true permitted
startup with no need for credentials or broader permission. Tool reports Dart
3.13.2. Android SDK/NDK and tablet hardware have not been provisioned here.

Commands for reproducing focused tests:

```sh
CI=true FLUTTER_SUPPRESS_ANALYTICS=true .flutter/bin/flutter pub get
CI=true FLUTTER_SUPPRESS_ANALYTICS=true .flutter/bin/flutter test test/features/photo_sorter
```

Official input references:
https://docs.flutter.dev/ui/interactivity/actions-and-shortcuts
https://docs.flutter.dev/ui/adaptive-responsive/input

### Observed test results

- 8 new tests pass (3 decision-model, 5 widget/input/lifecycle/layout tests).
- 23 existing browser listing/app-bar tests pass.
- Static analysis of the new feature and its tests: no issues found.
- Expanded analysis including the two browser integration files found existing
  informational lint findings; the initial new test compile errors were corrected.
- `git diff --check` passes. No Android APK build or Samsung hardware test was run.
- Native storage reads, permission prompts, pen buttons and DeX remain unverified.

The shallow Flutter checkout initially reported an unknown SDK version; fetching
the official 3.47.2 tag matching its pinned commit fixed version discovery without
changing the submodule commit. Flutter tests ran in the actual repository, not a
substitute implementation. A temporary isolated test package was prepared during
dependency resolution but was not needed for the reported results.

Next build should use a separate application ID/signing setup for a test variant
so it can coexist with an existing VaultExplorer installation. No install/uninstall
or modification of a tablet's existing vault data was performed.
