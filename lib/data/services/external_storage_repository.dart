import 'secure_metadata_store.dart';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/data/models/external_storage_location.dart';

class ExternalStorageRepository {
  const ExternalStorageRepository();

  static const _kLogTag = 'ExternalStorageRepository';

  static Future<File> get _dataFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/external_storages.json');
  }

  SecureMetadataStore get _metadata => SecureMetadataStore(
    key: 'private_metadata_external_storages_v1',
    legacyFile: () => _dataFile,
  );

  Future<List<ExternalStorageLocation>> loadAll() async {
    try {
      final serialized = await _metadata.read();
      if (serialized == null) return const [];
      final raw = jsonDecode(serialized) as List<dynamic>;
      return raw
          .map(
            (e) => ExternalStorageLocation.fromJson(e as Map<String, dynamic>),
          )
          .toList();
    } catch (e) {
      VeLog.w(_kLogTag, 'Protected external storages could not be loaded');
      return const [];
    }
  }

  Future<void> saveAll(List<ExternalStorageLocation> list) async {
    try {
      await _metadata.update((previous) {
        // Refuse to replace a catalog that could not be decoded into locations.
        if (previous != null) {
          for (final item in jsonDecode(previous) as List) {
            ExternalStorageLocation.fromJson(item as Map<String, dynamic>);
          }
        }
        return jsonEncode(list.map((e) => e.toJson()).toList());
      });
    } catch (e) {
      VeLog.w(_kLogTag, 'Protected external storages could not be saved');
      rethrow;
    }
  }
}
