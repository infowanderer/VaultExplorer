import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/api/vault_lifecycle_api.dart';
import 'organizer.dart';

Future<OrganizerFolder?> pickOrganizerDestination(
  BuildContext context,
  VaultLifecycleApi lifecycle,
  OrganizerBridge bridge,
) async {
  final picked = await lifecycle.pickExtractFolder();
  if (picked == null || !context.mounted) return null;
  final root = await bridge.chooseFolder(
    path: picked.path,
    treeUri: picked.treeUri,
  );
  if (!context.mounted) return null;
  var value = picked.displayName;
  final name = await showDialog<String>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Name this destination'),
      content: TextFormField(
        initialValue: value,
        autofocus: true,
        maxLength: 80,
        onChanged: (text) => value = text,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (value.trim().isNotEmpty) Navigator.pop(dialog, value.trim());
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
  return name == null ? null : OrganizerFolder(root, '', name);
}
