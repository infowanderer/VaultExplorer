/// Must use the same Dart define passed through to Android Gradle.
abstract final class ApplicationIdentity {
  static const isPreview = bool.fromEnvironment('VAULTEXPLORER_PREVIEW');
  static const baseId = 'com.aeidolon.vaultexplorer';
  static const applicationId = isPreview ? '$baseId.preview' : baseId;
  static const documentsAuthority = '$applicationId.documents';

  static bool isOwnDocumentsProviderUri(String? value) {
    if (value == null || value.isEmpty) return false;
    return Uri.tryParse(value)?.authority == documentsAuthority;
  }
}
