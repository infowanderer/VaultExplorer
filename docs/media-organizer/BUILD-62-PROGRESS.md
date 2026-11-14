# Build 62 — signed release receipt

Included changes: fuzzy saved destinations, preserved Undo intent during failed
reconciliation, exact photo duplicate reports, interactive video contact sheets,
sanitized thumbnail diagnostics, and strict vault-copy stream close/cancellation.
All use existing cryptography and storage adapters. Vault
sorting remains disabled: current backend APIs do not yet provide exclusive
creation and persistent file ownership across supported vault formats.

Three new vault-copy stream regression tests failed before the fix. Closing a
stream now permanently revokes it; cancellation checks apply even to buffered
reads and after a native chunk fetch. Newly fetched bytes are wiped when revoked
before delivery, and the one-byte read buffer is wiped after use. Read/close are
serialized; argument validation precedes native reads.

Current evidence:

- 3,911 Flutter tests pass, including the previously pending destination tests,
  six exact-duplicate dialog cases and nine contact-sheet/control cases.
- 77 targeted Android debug unit tests pass, with no failures, errors or skips.
- 92 focused sorter tests and four preview-identity tests pass.
- Analyzer reports zero errors and 472 warning/info diagnostics; this is not a warning-free repository.
- 38 standalone JUnit tests pass: organizer transfer/recovery, exhaustive
  copy/move journal-boundary sweeps, duplicate scanning and vault-copy streaming.
- Thirteen structural privacy guards and five APK-checker unit tests pass.
- No personal media has been used in mutation tests.

The exact pinned Flutter dependencies were restored from 180 lockfile-checksummed
archives. SDK 37.0, build-tools 37.0.0, NDK 28.2.13676358, CMake 3.22.1 and a full
Java 21 JDK were installed for a fresh Android build. Java build downloads use the
runtime's proxy and OS trust store; TLS verification remains enabled.

The complete native/Gradle release build succeeds, including Kotlin, JNI/C++,
Flutter AOT, R8 and release lint. The signed ARM64 APK passes the preview identity,
offline/privacy, certificate, feature-payload and alignment checks. The one-page cheat sheet was rendered and visually inspected. The Dart-only updater
must refuse this source because production Kotlin and the version have changed.
No tablet, DeX, S Pen, removable-storage or Android I/O-trace pass is claimed.


## Installable artifact

- Version: **1.50.0+62**, ARM64, package `com.aeidolon.vaultexplorer.preview`.
- Install over the existing preview; signing identity is unchanged.
- Size: **30,054,122 bytes**.
- SHA-256: `912a012e95571814debc49403dce794f793f01d8c0636558528a4559ef3c52b8`.
- Certificate SHA-256: `5831f702dd6a23a806a4861525a5ab157e1c7fb5391fa595e0453c8115ca6b57`.
- APK v2/v3 signatures and 16 KiB ZIP alignment pass. The release is not debuggable; network permissions, cleartext traffic and backups remain disabled.

This is a full native rebuild, not a Dart-only patch. Interactive contact sheets
are uniform in-memory previews with seek; scene sampling, clip export and
subtitle overlays remain pending. Exact duplicate reports are read-only. Vault
sorting and physical Samsung validation remain release blockers for those claims.
