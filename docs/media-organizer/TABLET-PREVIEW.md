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

Synthetic test photos can be generated without reading personal media:
`python3 tool/fixtures/make_tablet_photos.py /path/to/test-photos.zip` (requires
Pillow). The helper refuses an existing output archive and includes 12 drawn JPEG
cards, an EXIF rotation case and one deliberately invalid JPEG.

## Keyboard and mouse update

The latest preview adds left/right and wheel photo navigation, Ctrl image zoom,
independent normal/Ctrl video seek durations, and direct Escape-to-gallery in the
photo sorter. See [input controls and validation](INPUT-CONTROLS.md) for exact
mappings, settings, future command/contact-sheet plans and updated APK provenance.
It installs over the preceding preview with the same package and certificate.

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

## Verified build

A release-mode ARM64 preview APK has been built and test-signed. APK SHA-256:
`2c68e6946b81ebdf774b2ba9251efb8237c72ae0bd498627a8aae74681dec73a`.

- Full Flutter suite: **3,815 pass**; preview identity suite: **4 pass**.
- Android Gradle privacy/provider tests: **17 pass**, zero failures/errors/skips.
- Ten structural guards and five APK-validator regression tests pass.
- All 1,221 native C/C++ build steps completed; release linking, R8, lint and
  APK packaging pass. The USB attach alias uses its class namespace correctly
  when the installed package has the preview suffix.
- The actual signed APK passes `tool/privacy/check_preview_apk.py`: package and
  launcher label, disabled backup/cleartext-traffic flags, no Internet/network-state
  permissions, seven isolated provider authorities, disabled exported automation
  entry points, ARM64 ELF libraries, AOT output and APK v2/v3 signatures.
- ZIP alignment passes the SDK's 16 KiB check. The nine packaged native libraries
  have all non-system dependencies bundled. This does not prove 16 KiB ELF support
  for every upstream library or runtime behavior on every Android device.
- Real Tab S8 Ultra, DeX, S Pen, keyboard, SD/USB and I/O-trace tests remain open.

The separate **private signing backup** retains the development key and generated
password for compatible future preview updates. Keep the whole archive private;
never put it in the public repository. It is not a vault key or media backup.

For repeatable package checks, use the SDK's `aapt2` and `apksigner`:

```sh
python3 tool/privacy/check_preview_apk.py /path/to/signed-preview.apk \
  --aapt2 "$ANDROID_HOME/build-tools/37.0.0/aapt2" \
  --apksigner "$ANDROID_HOME/build-tools/37.0.0/apksigner"
```

The pinned Flutter plugin's SDK validator emits a spurious `2147483647` hint when
legacy AGP plugin extensions return a null numeric compile SDK (its fallback is
`Int.MAX_VALUE`). Actual SDK 35/36/37.0 builds succeed; do not change the project
to that fictitious SDK. No SDK pin or cryptographic dependency was downgraded.
