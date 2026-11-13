# Photo workflow checkpoint 61 — build receipt

Built on 2026-11-13 from the draft `media-organizer/tablet-spike` branch. This is
a **full Android/Flutter/Kotlin/JNI rebuild**, not a Dart-only APK replacement.

| Property | Verified value |
| --- | --- |
| Package | `com.aeidolon.vaultexplorer.preview` |
| Launcher | Media Organizer Preview |
| Version | `1.50.0`, Android version code `61` |
| ABI | ARM64 only |
| Signed APK bytes | `30078698` |
| APK SHA-256 | `87cb150291016f22045554dba6cb8b8b76a2acb037d75d52957d18bcefe5c1ad` |
| Signing certificate SHA-256 | `5831f702dd6a23a806a4861525a5ab157e1c7fb5391fa595e0453c8115ca6b57` |

The development certificate matches the preceding preview. Install as an upgrade
over that preview; do not uninstall to update. The signing backup remains private
and is not in this repository. This is not a production key-distribution scheme.

## Actual checks

- Full Flutter suite: **3,850 passed**, no failures. Separate preview-identity
  define run: **4 passed**.
- Android Gradle tests: **34 passed**, no failures/errors/skips: 17 organizer
  synthetic-filesystem cases, 15 streaming privacy cases, 2 provider cases.
  The organizer cases include interrupted/resumed transfer, source mutation,
  collision, edited partial/output, retained Trash, undo/recovery, annotation
  binding, insufficient space and directory-sync failure. The standalone JVM run
  independently passes the same 17 organizer cases on real temporary files.
- Analyzer with repository CI flags: exit 0, **zero errors**, 63 warning and
  403 info diagnostics. This is not a warning-free repository.
- Twelve structural privacy guards, five APK-checker regression tests, code
  boundary checks and `git diff --check` pass. A pre-existing randomized Diceware
  word-count test now uses a space separator: the real EFF asset contains
  hyphenated words, making a hyphen-split count intermittently wrong. Generator
  behavior and entropy were not changed.
- Linux host fixtures pass: atomic no-overwrite rename (including Unicode names
  and occupied symlinks), anonymous RAM scratch bounds/cleanup. Only synthetic
  files were used for mutation tests.
- Full ARM64 native build and subsequent release rebuilds pass. Final Gradle
  `:app:assembleRelease` and targeted `:app:testDebugUnitTest` pass, including
  Kotlin compilation, native linking, Flutter AOT, R8, release lint and packaging.
- The signed APK passes `tool/privacy/check_preview_apk.py`: package/label,
  non-debuggable release, disabled backup and cleartext traffic, no Internet or
  network-state permission, isolated provider authorities, disabled exported
  automation entry points, ARM64 ELF libraries and APK v2/v3 signatures.
- ZIP alignment passes the SDK 16 KiB check. The nine packaged native libraries
  have their non-system dependencies bundled; the new organizer JNI export is
  present. ZIP alignment does not establish all upstream ELF page-size support.

Toolchain: pinned Flutter commit `d3b14c876900e553bc736ca19295fc09e3853e8e`,
Flutter 3.47.2 / Dart 3.13.2, Java 21, Gradle 9.4.1, Android SDK/build-tools 37,
NDK 28.2.13676358, CMake 3.22.1. Exact dependency versions remain in the repository
lock files. Normal setup/build commands are in [TABLET-PREVIEW.md](TABLET-PREVIEW.md).

No tablet, S Pen, DeX, SD/USB provider, performance, power-cut or Android I/O-trace
result is claimed. No remote CI pass is claimed. Use the hardware acceptance
checklist and storage/privacy limits in [PHOTO-WORKFLOW.md](PHOTO-WORKFLOW.md)
before moving valuable originals. Protected metadata is app-owned Keystore
ciphertext outside the media container, not container-passphrase encryption.
