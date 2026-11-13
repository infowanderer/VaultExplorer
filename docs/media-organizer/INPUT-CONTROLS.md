# Keyboard and mouse preview

| Input | Photograph viewer | Video/audio viewer |
| --- | --- | --- |
| Left / Right | Previous / next photo | Back / forward one normal jump |
| Wheel up / down over media | Previous / next photo | Back / forward one normal jump |
| Ctrl + Left / Right | Zoom out / in | Back / forward one Ctrl jump |
| Ctrl + wheel up / down over media | Zoom in / out | Back / forward one Ctrl jump |
| Escape in photo sorter | Return to the underlying gallery | Not a new video shortcut |

Normal and Ctrl video jumps default to **5 and 30 seconds**. Change them separately
in **Media Player Controls → Playback & Gestures**, in the keyboard/mouse tiles
under video gestures. Each accepts 1–600 whole seconds: use the slider or tap its
seconds button to type an exact value. Existing double-tap jump settings remain
independent. New values use the existing Keystore-encrypted toolbar settings blob;
this feature adds no disk cache, logs or plaintext settings files.

Wheel routing applies over the media canvas. Menus, settings sliders, text fields
and gallery grids keep their normal scrolling/editing behavior. Trackpad gesture
events remain available for panning/pinching; hardware that reports trackpad
scrolls as mouse-wheel events follows the wheel mapping. Unsupported modifiers
are left alone. Locked controls, layout editing, menus and covered routes do not
accept media commands. Repeated native seeks are serialized and coalesced, clamp
to the clip duration, and are dropped when the active media changes.

The photo sorter remains an in-memory, read-only preview with provisional
destination labels. Escape exits directly even from its enlarged image view;
staged decisions trigger the existing discard confirmation. It does not commit
file transfers. Touch and pen interaction remain available.

## Later commands and video inspection

The route-local command layer is a small starting point for A04 command bindings.
A complete user-editable key/modifier registry, profiles, conflict detection and
script actions are **planned, not implemented**. Android-reserved system keys
cannot all be reassigned. Android script actions need an explicit supported
runtime or approved integration and scoped storage grants; they cannot promise
unrestricted desktop shell access or silently export decrypted media. Linux can
eventually offer explicitly configured local script commands.

Subtitle Contact Sheet Qt-inspired workflows remain on the roadmap: F05 clickable
timestamp grids, F11 uniform/scene/hybrid sampling and optional subtitle overlays,
F12 folder storyboard walls, and F06 in/out clip extraction retaining originals.
These are future Flutter/native implementations in this fork, not an embedded Qt
application or features included in this keyboard update. Any persistent frames,
contact sheets, journals and processing scratch must obey the protected-storage
policy; unavailable protected storage must fail closed.

## Validation and packaging

Widget tests cover arrow repeats, Ctrl mapping, wheel ownership against the real
InteractiveViewer, text/modal focus, exact seconds validation, sorter navigation,
zoom and Escape/discard behavior. Unit tests cover settings compatibility and
malformed values, endpoint clamping, serialized seek bursts and media changes.
No Samsung hardware, Android emulator, real S Pen or Book Cover Keyboard was
available; physical-device input and real playback seek timing remain unverified.

This update changes Dart code only. Its APK rebuilds release ARM64 AOT code and
Flutter assets with the repository's pinned SDK and reuses the verified preview's
unchanged Android/native binaries. `tool/privacy/update_preview_dart.py` checks
the precise base APK SHA-256, refuses native/dependency/SDK source changes, checks
the SDK engine's runtime load segments against the stripped packaged engine, and
verifies every retained ZIP member. This is **not** a fresh full native build.

Reproduce the Dart payload, then prepare an unsigned update:

```sh
CI=true FLUTTER_SUPPRESS_ANALYTICS=true .flutter/bin/flutter assemble \
  --output=build/media-input-release \
  -dTargetPlatform=android-arm64 -dBuildMode=release -dTargetFile=lib/main.dart \
  -dDartDefines=VkFVTFRFWFBMT1JFUl9QUkVWSUVXPXRydWU= \
  -dExtraGenSnapshotOptions=--strip -dTreeShakeIcons=true \
  android_aot_bundle_release_android-arm64
python3 tool/privacy/update_preview_dart.py /path/to/verified-base.apk \
  build/media-input-release \
  .flutter/bin/cache/artifacts/engine/android-arm64-release/flutter.jar \
  /path/to/unsigned-update.apk
```

Use official Android build-tools `zipalign -P 16 -f 4`, sign with the existing
private preview certificate, verify the signature and matching certificate, run
`zipalign -c -P 16 -v 4`, then run `tool/privacy/check_preview_apk.py`. The package,
manifest, permissions, DEX and eight other native libraries remain byte-for-byte
unchanged. The same package/version/signing certificate permits installing over
the previous preview without uninstalling and losing its private data.

Observed checks for this input update:

- Full Flutter suite: **3,827 passed**; no failures.
- Flutter analysis with the repository's nonfatal-info/warning CI flags: exit 0,
  zero errors; 464 warnings/informational diagnostics remain across the repository.
- Plaintext-staging source guards: 10 passed; APK-validator tests: 5 passed;
  code-boundary and whitespace checks passed.
- Signed APK checker and 16 KiB ZIP alignment: passed. Package/signing certificate
  match the previous preview; network, backup and debuggable flags remain disabled.
- APK: 29,447,914 bytes; SHA-256 `d9c9b2d2e188bfec657ea2e1d5328b9843dd35a7ba3f525279ae48f97400fd9d`.
- No native source changed, so Android Gradle/native test suites were not rerun
  for this Dart-only update. Existing native binaries are verified retained bytes.
