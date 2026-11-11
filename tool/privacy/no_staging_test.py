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

if __name__ == '__main__':
    unittest.main(verbosity=2)
