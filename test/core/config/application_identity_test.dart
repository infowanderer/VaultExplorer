import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/config/application_identity.dart';

void main() {
  test('package and provider identities match the selected build', () {
    const expected = bool.fromEnvironment('VAULTEXPLORER_PREVIEW')
        ? 'com.aeidolon.vaultexplorer.preview'
        : 'com.aeidolon.vaultexplorer';
    expect(ApplicationIdentity.applicationId, expected);
    expect(ApplicationIdentity.documentsAuthority, '$expected.documents');
  });
  test('own provider roots and subfolders are refused', () {
    final authority = ApplicationIdentity.documentsAuthority;
    for (final suffix in ['/root/a', '/tree/a/document/b', '/document/a?q=x']) {
      expect(
        ApplicationIdentity.isOwnDocumentsProviderUri(
          'content://$authority$suffix',
        ),
        isTrue,
      );
    }
  });
  test(
    'another installation and misleading authority prefixes remain distinct',
    () {
      final otherId = ApplicationIdentity.isPreview
          ? ApplicationIdentity.baseId
          : '${ApplicationIdentity.baseId}.preview';
      expect(
        ApplicationIdentity.isOwnDocumentsProviderUri(
          'content://$otherId.documents/tree/a',
        ),
        isFalse,
      );
      expect(
        ApplicationIdentity.isOwnDocumentsProviderUri(
          'content://${ApplicationIdentity.documentsAuthority}.other/tree/a',
        ),
        isFalse,
      );
    },
  );
  test('missing and malformed URIs do not match the own provider', () {
    for (final value in [null, '', 'not a URI', 'content://%']) {
      expect(ApplicationIdentity.isOwnDocumentsProviderUri(value), isFalse);
    }
  });
}
