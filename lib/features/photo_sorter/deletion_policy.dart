import 'package:material_ui/material_ui.dart';
import 'organizer.dart';

/// The preference changes prompting, never the meaning of Delete or Trash.
/// Unavailable protected settings refuse deletion rather than assume consent.
Future<bool> allowMediaDeletion(
  BuildContext context,
  Future<bool> Function() prompt, {
  OrganizerRepository? repository,
}) async {
  try {
    final ask = await (repository ?? OrganizerRepository())
        .loadConfirmDeletion();
    if (!context.mounted) return false;
    return ask ? await prompt() : true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'Deletion settings are unavailable. Nothing was deleted.',
          ),
        ),
      );
    }
    return false;
  }
}
