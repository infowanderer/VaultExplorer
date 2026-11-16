import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:vaultexplorer/data/services/secure_metadata_store.dart';

class MemoryStorage extends AppSecureStorage {
  final data = <String, String>{};
  bool persist = true, unreadable = false, badReadback = false;
  int writes = 0;
  Future<void> Function()? afterWrite;
  @override
  Future<String?> read({required String key}) async =>
      unreadable ? null : data[key];
  @override
  Future<bool> containsKey({required String key}) async =>
      data.containsKey(key);
  @override
  Future<bool> writeVerified({
    required String key,
    required String value,
  }) async {
    writes++;
    if (!persist) return false;
    data[key] = badReadback ? '{}' : value;
    await afterWrite?.call();
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late File legacy;
  late MemoryStorage secure;
  late SecureMetadataStore store;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('metadata-fixture-');
    legacy = File('${directory.path}/metadata.json');
    secure = MemoryStorage();
    store = SecureMetadataStore(
      key: directory.path,
      legacyFile: () async => legacy,
      secure: secure,
    );
  });
  tearDown(() => directory.deleteSync(recursive: true));
  test('new writes use secure store without a plaintext file', () async {
    await store.write('[{"name":"private-photo.jpg"}]');
    expect(await store.read(), '[{"name":"private-photo.jpg"}]');
    expect(directory.listSync(), isEmpty);
  });
  test('legacy is removed only after verified migration', () async {
    await legacy.writeAsString('["private-folder"]');
    expect(await store.read(), '["private-folder"]');
    expect(await legacy.exists(), isFalse);
    expect(secure.data[store.key], '["private-folder"]');
  });
  test('failed secure write preserves legacy', () async {
    await legacy.writeAsString('[1]');
    secure.persist = false;
    await expectLater(store.read(), throwsStateError);
    expect(await legacy.readAsString(), '[1]');
  });
  test('failed readback preserves legacy', () async {
    await legacy.writeAsString('[1]');
    secure.badReadback = true;
    await expectLater(store.read(), throwsStateError);
    expect(await legacy.readAsString(), '[1]');
  });
  test(
    'unavailable secure data cannot be overwritten or fall back to stale JSON',
    () async {
      secure.data[store.key] = '[1]';
      secure.unreadable = true;
      await legacy.writeAsString('[2]');
      await expectLater(store.write('[]'), throwsStateError);
      expect(secure.data[store.key], '[1]');
      expect(secure.writes, 0);
      expect(await legacy.exists(), isTrue);
    },
  );
  test(
    'corrupt legacy is preserved and never replaced with empty state',
    () async {
      await legacy.writeAsString('broken');
      await expectLater(store.write('[]'), throwsFormatException);
      expect(secure.writes, 0);
      expect(await legacy.readAsString(), 'broken');
    },
  );
  test('oversized values fail without filesystem fallback', () async {
    await expectLater(
      store.write(jsonEncode(['x' * SecureMetadataStore.maxBytes])),
      throwsStateError,
    );
    expect(secure.writes, 0);
    expect(directory.listSync(), isEmpty);
  });
  test('concurrent updates across instances do not lose entries', () async {
    final other = SecureMetadataStore(
      key: store.key,
      legacyFile: () async => legacy,
      secure: secure,
    );
    await Future.wait([
      for (var i = 0; i < 20; i++)
        (i.isEven ? store : other).update((old) {
          final items = old == null ? <dynamic>[] : jsonDecode(old) as List;
          return jsonEncode([...items, i]);
        }),
    ]);
    expect((jsonDecode((await store.read())!) as List).length, 20);
    expect(directory.listSync(), isEmpty);
  });
  test(
    'secure data is authoritative when a stale legacy file remains',
    () async {
      secure.data[store.key] = '[1]';
      await legacy.writeAsString('[2]');
      expect(await store.read(), '[1]');
      expect(await legacy.readAsString(), '[2]');
    },
  );
  test('wrong collection shape cannot replace existing metadata', () async {
    secure.data[store.key] = '{}';
    await expectLater(store.write('[]'), throwsFormatException);
    expect(secure.data[store.key], '{}');
    expect(secure.writes, 0);
  });
  test('map records validate their own collection shape', () async {
    final mapStore = SecureMetadataStore(
      key: store.key,
      legacyFile: () async => legacy,
      secure: secure,
      expectMap: true,
    );
    await expectLater(mapStore.write('[]'), throwsFormatException);
    await mapStore.write('{"folder":{}}');
    expect(await mapStore.read(), '{"folder":{}}');
    expect(directory.listSync(), isEmpty);
  });
  test('legacy changes during migration are retained', () async {
    await legacy.writeAsString('[1]');
    secure.afterWrite = () async {
      await legacy.writeAsString('[2]');
    };
    expect(await store.read(), '[1]');
    expect(await legacy.readAsString(), '[2]');
    expect(secure.data[store.key], '[1]');
  });
  test('oversized legacy is preserved without writing', () async {
    await legacy.writeAsString('x' * (SecureMetadataStore.maxBytes + 1));
    await expectLater(store.read(), throwsStateError);
    expect(await legacy.exists(), isTrue);
    expect(secure.writes, 0);
  });
  test('a failed update does not poison the serialization queue', () async {
    await expectLater(store.update((_) => 'broken'), throwsFormatException);
    await store.write('[1]');
    expect(await store.read(), '[1]');
  });
}
