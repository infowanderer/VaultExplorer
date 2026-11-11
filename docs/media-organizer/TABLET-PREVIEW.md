# Isolated tablet preview

The opt-in preview uses package `com.aeidolon.vaultexplorer.preview` and launcher
name **Media Organizer Preview**. Its document/share/stream providers use the same
package prefix. Android app-private data and Keystore entries are separate from
an existing VaultExplorer installation; the preview does not migrate that app's
catalog or remembered credentials. The shared media or vault files you explicitly
select are still the same files, so use disposable fixtures for initial testing.

Build on an SDK-equipped machine:

```sh
CI=true FLUTTER_SUPPRESS_ANALYTICS=true .flutter/bin/flutter pub get
CI=true FLUTTER_SUPPRESS_ANALYTICS=true .flutter/bin/flutter build apk \
  --release --target-platform android-arm64 \
  --dart-define=VAULTEXPLORER_PREVIEW=true
```

Gradle reads the same encoded Dart define to select the Android identity; Dart
uses it for document URIs and own-provider checks. Missing/false keeps the normal
identity. Invalid or repeated preview values fail the Gradle configuration.
Preview automation receiver/capture entry points are disabled. Kotlin/Java class
names and native JNI names retain their original namespace.

The release manifest removes Internet and network-state permissions. Debug and
profile development overlays may request Internet for Flutter tooling; use a
release-mode preview for distribution. Without `android/key.properties`, release
output is unsigned and requires test signing before installation. Development
signing is not a production update/key-recovery scheme.

## What to exercise

1. Use a disposable test folder on internal storage; open the browser's photo
   sorting preview. Check the grid, tap/pen selection, image preview and zoom.
2. Attach the Book Cover Keyboard/trackpad. Check arrows, Space, 1/2/3 routing,
   Backspace and Escape, focus and scrolling. Repeat in landscape and DeX.
3. Open equivalent disposable fixtures on microSD and USB. Check read-only media,
   unplug/reconnect and revoked access. Unsupported storage should report failure.
4. Background/reopen the app and lock/unlock a disposable test vault. Check that
   previews hide and no reviewed operation falls back to plaintext scratch.

The sorter still stages labels in memory only; real destinations, committed
transfers, durable organizer sessions and undo are unfinished. Archive, recording,
edit-export and some other scratch-dependent host tools are blocked by the strict
privacy policy. SMB/rclone are deferred. See [PLAINTEXT-WRITES.md](PLAINTEXT-WRITES.md)
for encryption boundaries and existing artifact limits.

## Current validation

- Full Flutter suite: 3,815 pass; preview identity suite: 4 pass.
- Ten structural privacy/identity guards pass.
- Full release native build, packaged-permission checks, signing and tablet
  execution are in progress; do not infer these from the earlier Kotlin check.
