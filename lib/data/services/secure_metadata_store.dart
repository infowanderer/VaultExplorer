import 'dart:convert';
import 'dart:io';
import 'app_secure_storage.dart';

/// Small app metadata stored through the existing Keystore-backed native store.
/// No plaintext write or fallback. Legacy JSON is removed only after verified
/// persistence and only if its contents have not changed during migration.
class SecureMetadataStore {
  const SecureMetadataStore({
    required this.key,
    this.legacyFile,
    this.secure = AppSecureStorage.instance,
    this.expectMap = false,
  });
  final String key;
  final Future<File> Function()? legacyFile;
  final AppSecureStorage secure;
  final bool expectMap;
  static const maxBytes = 256 * 1024;
  static final Map<String, Future<void>> _tails = {};

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = (_tails[key] ?? Future<void>.value()).then((_) => action());
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _tails[key] = tail;
    tail.then((_) {
      if (identical(_tails[key], tail)) _tails.remove(key);
    });
    return result;
  }

  void _validate(String value) {
    if (utf8.encode(value).length > maxBytes) {
      throw StateError('Metadata exceeds secure storage limit');
    }
    final decoded = jsonDecode(value);
    if (expectMap ? decoded is! Map : decoded is! List) {
      throw const FormatException('Unexpected metadata collection shape');
    }
  }

  Future<void> _writeVerified(String value) async {
    _validate(value);
    if (!await secure.writeVerified(key: key, value: value)) {
      throw StateError('Protected metadata was not persisted');
    }
    if (await secure.read(key: key) != value) {
      throw StateError('Protected metadata verification failed');
    }
  }

  Future<String?> _read() async {
    final value = await secure.read(key: key);
    if (value != null) {
      _validate(value);
      return value;
    }
    if (await secure.containsKey(key: key)) {
      throw StateError('Protected metadata is currently unavailable');
    }
    final loadLegacy = legacyFile;
    if (loadLegacy == null) return null;
    final file = await loadLegacy();
    if (!await file.exists()) return null;
    if (await file.length() > maxBytes) {
      throw StateError('Legacy metadata exceeds secure storage limit');
    }
    final legacy = await file.readAsString();
    _validate(legacy);
    await _writeVerified(legacy);
    // Failure to delete a legacy file must not undo a successful secure write.
    // Changed files are retained for reconciliation, not silently discarded.
    try {
      if (await file.exists() &&
          await file.length() <= maxBytes &&
          await file.readAsString() == legacy) {
        await file.delete();
      }
    } on FileSystemException {
      /* Reported as a possible residual in privacy docs. */
    }
    return legacy;
  }

  Future<String?> read() => _serialized(_read);
  Future<void> write(String value) => _serialized(() async {
    await _read(); // Refuse to overwrite an existing unreadable/corrupt store.
    await _writeVerified(value);
  });
  Future<void> update(String Function(String?) transform) =>
      _serialized(() async {
        final next = transform(await _read());
        await _writeVerified(next);
      });
}
