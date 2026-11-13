"""Regression checks for SDK manifest formats and unsafe package rejection."""
import unittest
from unittest.mock import patch
import check_preview_apk as checker


class ApkCheckerTests(unittest.TestCase):
    def test_expanded_namespace_and_literal_false(self):
        tree = '''E: application
  A: http://schemas.android.com/apk/res/android:allowBackup(0x01010280)=false
  E: provider
    A: http://schemas.android.com/apk/res/android:authorities(0x01010018)="example.documents" (Raw: "example.documents")
'''
        app, provider = checker.manifest_nodes(tree)
        self.assertTrue(checker.is_false(app['attributes']['android:allowBackup']))
        self.assertEqual('example.documents', provider['attributes']['android:authorities'])

    def test_typed_boolean_and_unknown_values(self):
        self.assertTrue(checker.is_false('(type 0x12)0x0'))
        for value in ['true', '(type 0x12)0xffffffff', '@0x7f050001', '', '0']:
            self.assertFalse(checker.is_false(value))

    def test_old_and_new_signer_report_formats(self):
        digest = 'a' * 64
        prefix = 'Number of signers: 1\nVerified using v2 scheme (APK Signature Scheme v2): true\n'
        for line in ['Signer #1 certificate SHA-256 digest: ' + digest,
                     'V3.0 Signer: certificate SHA-256 digest: ' + digest]:
            self.assertEqual(digest, checker.signer_certificate(prefix + line))
        with self.assertRaises(ValueError):
            checker.signer_certificate(prefix.replace('signers: 1', 'signers: 2') + line)

    def test_network_permissions_are_rejected_before_opening_the_archive(self):
        prefix = "package: name='" + checker.PACKAGE + "'\napplication-label:'Media Organizer Preview'\n"
        for line in ["uses-permission: name='android.permission.INTERNET'",
                     "uses-permission-sdk-23: name='android.permission.ACCESS_NETWORK_STATE'"]:
            with patch.object(checker, 'run', return_value=prefix + line):
                with self.assertRaisesRegex(ValueError, 'Network permission'):
                    checker.verify('does-not-exist.apk', 'aapt2', 'apksigner')

    def test_normal_application_package_is_not_a_preview(self):
        with patch.object(checker, 'run', return_value="package: name='com.aeidolon.vaultexplorer'"):
            with self.assertRaisesRegex(ValueError, 'Unexpected application package'):
                checker.verify('does-not-exist.apk', 'aapt2', 'apksigner')


if __name__ == '__main__':
    unittest.main()
