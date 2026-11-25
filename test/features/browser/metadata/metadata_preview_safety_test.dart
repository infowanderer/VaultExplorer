import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/config/application_identity.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/metadata/metadata_edit_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('preview refuses metadata timestamp writes before platform access', () async {
    expect(ApplicationIdentity.isPreview, isTrue,
        reason: 'Run with --dart-define=VAULTEXPLORER_PREVIEW=true');
    const channel = MethodChannel('metadata-preview-safety');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      throw StateError('No platform access allowed');
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final container = MountedContainer(
      uri: 'content://synthetic', displayName: 'Fixture', volId: 1,
      rootFiles: const [], mountedAt: DateTime(2026),
      totalSpace: 1000, freeSpace: 1000,
    );
    final service = MetadataEditService(const VaultFileIoApi(channel));
    expect(await service.setModifiedTime(container, 'photo.jpg', 123), isFalse);
    expect(calls, isEmpty);
  }, skip: !ApplicationIdentity.isPreview);
}
