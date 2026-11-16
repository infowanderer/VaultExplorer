import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:vaultexplorer/core/api/vault_engine_channel.dart';
import 'package:vaultexplorer/data/models/external_storage_location.dart';
import 'package:vaultexplorer/data/services/external_storage_repository.dart';

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Paths(this.directory);
  final String directory;
  @override
  Future<String?> getApplicationDocumentsPath() async => directory;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const key = 'private_metadata_external_storages_v1';
  const location = ExternalStorageLocation(
    id: 'usb',
    path: '/storage/private-trip',
    treeUri: 'content://fixture/tree/private-trip',
    displayName: 'Vacation',
    volId: 1,
  );
  const repository = ExternalStorageRepository();
  late Directory directory;
  late PathProviderPlatform originalPaths;
  late Map<String, String> values;
  var allowWrite = true;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('external-metadata-');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    values = {};
    allowWrite = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kVaultEngineChannel, (call) async {
          final arguments = call.arguments as Map;
          final name = arguments['key'] as String;
          switch (call.method) {
            case 'readSecure':
              return values[name];
            case 'containsKeySecure':
              return values.containsKey(name);
            case 'writeSecure':
              if (!allowWrite) return false;
              values[name] = arguments['value'] as String;
              return true;
          }
          throw StateError('Unexpected method ${call.method}');
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kVaultEngineChannel, null);
    PathProviderPlatform.instance = originalPaths;
    directory.deleteSync(recursive: true);
  });
  test('storage names and URIs round-trip without a plaintext file', () async {
    await repository.saveAll([location]);
    final loaded = await repository.loadAll();
    expect(loaded.single.toJson(), location.toJson());
    expect(directory.listSync(), isEmpty);
    expect(values, contains(key));
  });
  test('legacy locations migrate before their file is removed', () async {
    final legacy = File('${directory.path}/external_storages.json');
    await legacy.writeAsString(jsonEncode([location.toJson()]));
    expect((await repository.loadAll()).single.path, location.path);
    expect(await legacy.exists(), isFalse);
    expect(values, contains(key));
  });
  test(
    'unavailable encryption preserves the legacy and reports save failure',
    () async {
      final legacy = File('${directory.path}/external_storages.json');
      final original = jsonEncode([location.toJson()]);
      await legacy.writeAsString(original);
      allowWrite = false;
      await expectLater(repository.saveAll([]), throwsStateError);
      expect(await legacy.readAsString(), original);
      expect(values, isEmpty);
    },
  );
  test('malformed entries cannot be replaced by an empty catalog', () async {
    values[key] = '[0]';
    expect(await repository.loadAll(), isEmpty);
    await expectLater(repository.saveAll([]), throwsA(isA<TypeError>()));
    expect(values[key], '[0]');
  });
}
