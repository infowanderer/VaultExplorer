"""Structural privacy guards, not a substitute for Android I/O tracing."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
NATIVE = ROOT / 'android/app/src/main/kotlin/com/aeidolon/vaultexplorer'

class NoStagingTests(unittest.TestCase):
    def assert_no_staging(self, path):
        source = (NATIVE / path).read_text()
        for forbidden in ('createTempFile(', '.cacheDir', 'getTemporaryDirectory('):
            self.assertNotIn(forbidden, source, f'{path} reintroduced disk staging')
        return source

    def test_document_provider_has_no_plaintext_file_fallback(self):
        source = self.assert_no_staging('container/ContainerDocumentsProvider.kt')
        self.assertNotIn('extractToFile(', source)
        self.assertNotIn('decodeFile(', source)

    def test_export_handlers_have_no_cache_staging(self):
        self.assert_no_staging('handlers/ImportExportHandlers.kt')

    def test_transfer_module_has_no_filesystem_dependency(self):
        source = self.assert_no_staging('privacy/VaultReadInputStream.kt')
        for forbidden in ('java.io.File', 'java.nio.file', 'android.content.Context'):
            self.assertNotIn(forbidden, source)

    def test_legacy_copy_and_import_spools_removed(self):
        source = self.assert_no_staging('container/ContainerEngine.kt')
        self.assertNotIn('copyFileViaBackend(', source)
        self.assertNotIn('"vc_import_"', source)
        self.assertNotIn('"ve_copy_"', source)

    def test_recording_edit_and_archive_staging_uses_denying_policy(self):
        files = ('handlers/ArchiveHandlers.kt', 'handlers/VideoEditHandlers.kt',
                 'handlers/AudioEditHandlers.kt', 'camera/VaultVideoRecorder.kt',
                 'camera/SegmentedVideoEngine.kt', 'camera/VaultCameraSession.kt',
                 'audiocapture/VaultAudioRecorder.kt')
        for path in files:
            source = (NATIVE / path).read_text()
            self.assertNotIn('File.createTempFile(', source)
            self.assertIn('PlaintextScratch', source)
        archives = (NATIVE / 'handlers/ArchiveHandlers.kt').read_text()
        self.assertNotIn('File(activity.cacheDir, "arch_', archives)
        self.assertIn('"PRIVACY_BLOCKED"', archives)

    def test_cryfs_never_falls_back_to_filesystem_scratch(self):
        source = (ROOT / 'android/app/src/main/cpp/foldervault/fv_cryfs_vault.cpp').read_text()
        self.assertNotIn('mkstemp(', source)
        self.assertIn('vault_privacy::RamScratch', source)
        helper = (ROOT / 'android/app/src/main/cpp/privacy/ram_scratch.h').read_text()
        self.assertNotIn('::open(', helper)
        self.assertNotIn('::mkstemp(', helper)
        self.assertIn('SYS_memfd_create', helper)

    def test_private_metadata_services_have_no_plaintext_writer(self):
        for path in ('lib/data/services/container_repository.dart',
                     'lib/data/services/external_storage_repository.dart',
                     'lib/data/services/discrete_mode_repository.dart',
                     'lib/features/photo_sorter/organizer.dart',
                     'lib/features/photo_sorter/organizer_catalog.dart',
                     'lib/features/decoy/local/decoy_local_marks_service.dart'):
            source = (ROOT / path).read_text()
            self.assertIn('SecureMetadataStore', source)
            self.assertNotIn('writeAsString(', source)
            self.assertNotIn('writeAsBytes(', source)

    def test_organizer_streams_never_stage_or_permanently_delete_media(self):
        for path in ('organizer/OrganizerTransfer.kt', 'organizer/RawOrganizerFiles.kt',
                     'organizer/AndroidOrganizerFiles.kt'):
            source = self.assert_no_staging(path)
            for forbidden in ('Files.delete(', 'deleteDocument(', '.delete(', 'deleteRecursively('):
                self.assertNotIn(forbidden, source, f'{path} introduced permanent media deletion')
        saf = (NATIVE / 'organizer/AndroidOrganizerFiles.kt').read_text()
        self.assertIn('com.android.externalstorage.documents', saf)

    def test_organizer_atomic_journal_writes_ciphertext_in_private_storage(self):
        source = self.assert_no_staging('organizer/OrganizerJournalFiles.kt')
        self.assertIn('context.noBackupFilesDir', source)
        self.assertIn('AtomicFile(base)', source)
        self.assertIn('encrypt(value)', source)
        self.assertIn('output.write(encrypted.toByteArray', source)
        self.assertNotIn('output.write(value', source)
        self.assertLess(source.index('encrypt(value)'), source.index('atomic.startWrite()'))

    def test_providers_follow_the_application_package(self):
        import xml.etree.ElementTree as ET
        manifest = ET.parse(ROOT / 'android/app/src/main/AndroidManifest.xml').getroot()
        android = '{http://schemas.android.com/apk/res/android}'
        for provider in manifest.findall('./application/provider'):
            self.assertTrue(provider.get(android + 'authorities').startswith('${applicationId}.'))
        usb = (NATIVE / 'handlers/UsbContainerHandlers.kt').read_text()
        self.assertNotIn('${activity.packageName}.UsbAttachAlias', usb)
        self.assertIn('"com.aeidolon.vaultexplorer.UsbAttachAlias"', usb)
        for path in NATIVE.rglob('*.kt'):
            source = path.read_text()
            for authority in ('documents', 'shareprovider', 'stream'):
                self.assertNotIn('"com.aeidolon.vaultexplorer.' + authority + '"', source)

    def test_main_manifest_removes_network_permissions(self):
        import xml.etree.ElementTree as ET
        manifest = ET.parse(ROOT / 'android/app/src/main/AndroidManifest.xml').getroot()
        android = '{http://schemas.android.com/apk/res/android}'
        tools = '{http://schemas.android.com/tools}'
        permissions = {p.get(android + 'name'): p for p in manifest.findall('uses-permission')}
        for name in ('android.permission.INTERNET', 'android.permission.ACCESS_NETWORK_STATE'):
            self.assertEqual('remove', permissions[name].get(tools + 'node'))

    def test_split_volume_mirror_refuses_external_staging(self):
        source = (NATIVE / 'LocalSplitFuseCallback.kt').read_text()
        self.assertNotIn('dir = File(context.cacheDir, "split_rw_mirror_', source)
        self.assertIn('PlaintextScratch.file(context.cacheDir, "split_rw_mirror_', source)

if __name__ == '__main__':
    unittest.main(verbosity=2)
