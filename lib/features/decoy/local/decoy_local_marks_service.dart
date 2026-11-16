import 'package:vaultexplorer/data/services/secure_metadata_store.dart';
// Persistence for the bookmarks and pins of phone storage: the primary local
// storage container and any external storage locations. Kept entirely
// separate from [ContainerRepository]'s protected metadata record.
//
// Why this can't just reuse ContainerRepository: that file is exactly what
// VaultDashboardController.loadAll() reads to populate the real vault
// dashboard. If a decoy-mode bookmark/pin ever got persisted through it,
// a ContainerRecord for the local-storage pseudo-container would show up
// as a bogus, unopenable tile on the *real* dashboard after a genuine
// unlock -- a direct leak of "decoy mode was used" defeating the entire
// point of Mask Mode. Its protected metadata record never mixes with
// the real-vault dashboard records.
//
// The record maps a container's uri to its marks. It used to hold one shared
// list, so a bookmark made on an SD card also appeared in phone storage (and
// vice versa); keying by uri keeps each location's marks its own.
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:vaultexplorer/data/models/vault_marks.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';

class DecoyLocalMarksService {
  /// [fileLocator] exists so tests can point the service at a temp file.
  DecoyLocalMarksService({
    Future<File> Function()? fileLocator,
    this.secure = AppSecureStorage.instance,
  }) : _fileLocator = fileLocator ?? _defaultFile;

  final Future<File> Function() _fileLocator;
  final AppSecureStorage secure;
  SecureMetadataStore get _metadata => SecureMetadataStore(
    key: 'private_metadata_local_marks_v1',
    legacyFile: _fileLocator,
    secure: secure,
    expectMap: true,
  );

  static Future<File> _defaultFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/decoy_local_marks.json');
  }

  // Several locations share the one file, so read-modify-write cycles from
  // different containers must not interleave or one would drop the other's
  // update. Shared by every instance because they share the file.
  static Future<void> _tail = Future<void>.value();

  static Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<Map<String, Object?>> _readAll() async {
    final serialized = await _metadata.read();
    if (serialized == null) return <String, Object?>{};
    final raw = jsonDecode(serialized);
    if (raw is! Map) return <String, Object?>{};
    return Map<String, Object?>.from(raw);
  }

  Future<VaultMarks> load(String containerUri) => _serialized(() async {
    try {
      final all = await _readAll();
      final entry = all[containerUri];
      return entry == null ? VaultMarks.empty : VaultMarks.fromJson(entry);
    } catch (_) {
      return VaultMarks.empty;
    }
  });

  /// Best-effort, like every other caller of a marks store: returns whether
  /// the write landed.
  Future<bool> save(String containerUri, VaultMarks marks) =>
      _serialized(() async {
        try {
          await _metadata.update((serialized) {
            final all = serialized == null
                ? <String, Object?>{}
                : Map<String, Object?>.from(jsonDecode(serialized) as Map);
            if (marks.isEmpty) {
              all.remove(containerUri);
            } else {
              all[containerUri] = marks.toJson();
            }
            return jsonEncode(all);
          });
          return true;
        } catch (_) {
          return false;
        }
      });
}
