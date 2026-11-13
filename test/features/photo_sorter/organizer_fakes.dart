import 'dart:async';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:vaultexplorer/data/services/secure_metadata_store.dart';
import 'package:vaultexplorer/features/photo_sorter/organizer.dart';

class ProtectedMemory extends AppSecureStorage {
  final records = <String, String>{};
  bool available = true, persist = true;
  @override
  Future<String?> read({required String key}) async =>
      available ? records[key] : null;
  @override
  Future<bool> containsKey({required String key}) async =>
      records.containsKey(key);
  @override
  Future<bool> writeVerified({
    required String key,
    required String value,
  }) async {
    if (!available || !persist) return false;
    records[key] = value;
    return true;
  }

  OrganizerRepository repository() => OrganizerRepository(
    store: (key) =>
        SecureMetadataStore(key: key, secure: this, expectMap: true),
  );
}

class FixtureBridge extends OrganizerBridge {
  FixtureBridge() : super(const MethodChannel('organizer.fixture'));
  final rows = <Map<String, dynamic>>[];
  int inspections = 0,
      preparations = 0,
      executions = 0,
      undos = 0,
      cancellations = 0;
  bool refusePreparation = false, refuseInspection = false;
  final versionsByPath = <String, Map<String, dynamic>>{};
  final hashesByPath = <String, String>{};
  Completer<Map<String, dynamic>>? executeGate;
  Map<String, dynamic> version = {
    'identity': 'fixture:42',
    'size': 123,
    'modified': 1000,
  };
  @override
  Future<Map<String, dynamic>> inspect(String root, String path) async {
    inspections++;
    if (refuseInspection) throw StateError('Disconnected fixture');
    return Map.of(versionsByPath[path] ?? version);
  }

  @override
  Future<Map<String, dynamic>> fingerprint(String root, String path) async => {
    ...(versionsByPath[path] ?? version),
    'sha256': hashesByPath[path] ?? '${"a" * 64}',
  };
  @override
  Future<List<Map<String, dynamic>>> history() async =>
      rows.map((row) => Map<String, dynamic>.from(row)).toList();
  @override
  Future<Map<String, dynamic>> prepare(Map<String, dynamic> args) async {
    preparations++;
    if (refusePreparation) throw StateError('Fixture collision');
    final folder = args['directory'] as Map;
    final row = <String, dynamic>{
      'id': 'fixture-job-$preparations',
      'source': args['source'],
      'destination': {
        'root': folder['root'],
        'path': '${folder['path']}/${args['name']}',
      },
      'created': null,
      'state': 'planned',
      'move': args['move'],
      'size': 123,
      'sha256':
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'createdAt': preparations,
    };
    rows.add(row);
    return Map.of(row);
  }

  @override
  Future<Map<String, dynamic>> execute(String id) async {
    executions++;
    if (executeGate != null) return executeGate!.future;
    final row = rows.firstWhere((row) => row['id'] == id);
    row['state'] = 'complete';
    row['created'] = row['destination'];
    row['undoSupported'] = true;
    return Map.of(row);
  }

  @override
  Future<Map<String, dynamic>> undo(String id) async {
    undos++;
    final row = rows.firstWhere((row) => row['id'] == id);
    row['state'] = 'undone';
    return Map.of(row);
  }

  @override
  Future<void> cancel(String id) async {
    cancellations++;
  }

  @override
  Future<List<int>?> progress(String id) async => [12, 123];
}
