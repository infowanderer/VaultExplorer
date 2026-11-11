import 'secure_metadata_store.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// One entry in the decoy reader's "recent files" list.
///
/// Display names and URIs are private metadata even without a vault linkage.
/// The repository below now persists them using protected native storage.
class DecoyRecentFile {
  final String uri;
  final String displayName;
  final DateTime openedAt;

  const DecoyRecentFile({
    required this.uri,
    required this.displayName,
    required this.openedAt,
  });

  Map<String, dynamic> toJson() => {
    'uri': uri,
    'displayName': displayName,
    'openedAt': openedAt.millisecondsSinceEpoch,
  };

  factory DecoyRecentFile.fromJson(Map<String, dynamic> j) => DecoyRecentFile(
    uri: j['uri'] as String? ?? '',
    displayName: j['displayName'] as String? ?? 'Document.pdf',
    openedAt: DateTime.fromMillisecondsSinceEpoch(j['openedAt'] as int? ?? 0),
  );
}

/// Caps how many recent entries are kept, oldest dropped first.
const int _kMaxRecents = 20;

/// Loads/saves the decoy reader's recent-files list. Static, file-backed,
/// same shape as `AppSettingsService` -- see that class's doc comment for
/// the precedent this follows.
class DiscreteModeRepository {
  static Future<File> get _recentsFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/discrete_mode_recents.json');
  }

  static final _metadata = SecureMetadataStore(
    key: 'private_metadata_recents_v1',
    legacyFile: () => _recentsFile,
  );

  static Future<List<DecoyRecentFile>> loadRecents() async {
    try {
      final serialized = await _metadata.read();
      if (serialized == null) return [];
      final raw = jsonDecode(serialized);
      if (raw is! List) return [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(DecoyRecentFile.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Records [file] as most-recently-opened, de-duplicating by uri and
  /// trimming to [_kMaxRecents].
  static Future<void> recordOpened(DecoyRecentFile file) async {
    try {
      await _metadata.update((serialized) {
        final current = serialized == null
            ? <DecoyRecentFile>[]
            : (jsonDecode(serialized) as List)
                  .map(
                    (e) => DecoyRecentFile.fromJson(
                      Map<String, dynamic>.from(e as Map),
                    ),
                  )
                  .toList();
        final next = [
          file,
          ...current.where((r) => r.uri != file.uri),
        ].take(_kMaxRecents);
        return jsonEncode(next.map((r) => r.toJson()).toList());
      });
    } catch (_) {
      // Best-effort, same as AppSettingsService.saveSettings -- a failure
      // to remember a recent file should never block opening it.
    }
  }

  /// Removes a single entry by [uri] from recents.
  static Future<void> removeRecent(String uri) async {
    try {
      await _metadata.update((serialized) {
        final current = serialized == null
            ? <dynamic>[]
            : jsonDecode(serialized) as List;
        return jsonEncode(
          current.where((r) => (r as Map)['uri'] != uri).toList(),
        );
      });
    } catch (_) {
      // Best-effort persistence: if this write/delete fails, the on-disk
      // recents list may lag the in-memory intent, but nothing here is
      // security- or correctness-critical enough to surface as an error.
    }
  }

  static Future<void> clearRecents() async {
    try {
      await _metadata.write('[]');
    } catch (_) {
      // Same reasoning as removeRecent() above.
    }
  }
}
