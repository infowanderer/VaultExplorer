import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'organizer.dart';
import 'rename_plan.dart';

class BatchRenameDialog extends StatefulWidget {
  const BatchRenameDialog({
    super.key,
    required this.controller,
    required this.paths,
  });
  final OrganizerController controller;
  final List<String> paths;
  @override
  State<BatchRenameDialog> createState() => _BatchRenameDialogState();
}

class _BatchRenameDialogState extends State<BatchRenameDialog> {
  final template = TextEditingController(text: 'Photo-{counter:03}.{ext}');
  final start = TextEditingController(text: '1');
  final step = TextEditingController(text: '1');
  final versions = <String, Map<String, dynamic>>{};
  bool loading = true, saving = false, move = false;
  int destination = 0;
  String? error;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    try {
      if (widget.paths.isEmpty || widget.paths.length > 200) {
        throw const FormatException('Select between 1 and 200 photographs.');
      }
      for (final path in widget.paths) {
        if (!mounted) return;
        versions[path] = await widget.controller.bridge.inspect(
          widget.controller.root,
          path,
        );
      }
    } catch (_) {
      error =
          'Could not inspect this batch. Select up to 200 accessible photographs and reopen the preview.';
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  void dispose() {
    template.dispose();
    start.dispose();
    step.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.controller;
    final destinations = [
      OrganizerFolder(model.root, model.folder, 'Current folder'),
      ...model.state.destinations,
    ];
    final target = destinations[destination.clamp(0, destinations.length - 1)];
    final sameFolder =
        organizerAddress(target.root, target.path) ==
        organizerAddress(model.root, model.folder);
    List<RenameRow> rows = [];
    String? previewError;
    if (!loading && error == null) {
      try {
        rows = buildRenamePlan(
          [
            for (final path in widget.paths)
              RenameInput(path, versions[path]!['modified'] as int),
          ],
          template.text,
          start: int.tryParse(start.text) ?? -1,
          step: int.tryParse(step.text) ?? 0,
        );
      } on FormatException catch (failure) {
        previewError = failure.message;
      }
    }
    final changed = rows.where((r) => !sameFolder || !r.unchanged).toList();
    final valid =
        !loading &&
        !saving &&
        error == null &&
        previewError == null &&
        changed.isNotEmpty &&
        rows.every((r) => r.error == null);
    return AlertDialog(
      title: Text('Batch rename ${widget.paths.length} photographs'),
      content: SizedBox(
        width: 700,
        height: MediaQuery.sizeOf(context).height * .65,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Changes are staged. Review the operation queue, then choose Run queue.',
              ),
              const SizedBox(height: 8),
              TextField(
                controller: template,
                enabled: !saving,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Filename template',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const Text(
                '{name} original stem · {ext} extension · {counter:03} padded counter · {modified:yyyyMMdd} UTC modification date',
                style: TextStyle(fontSize: 12),
              ),
              Wrap(
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 100,
                    child: TextField(
                      controller: start,
                      enabled: !saving,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Start counter',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  SizedBox(
                    width: 100,
                    child: TextField(
                      controller: step,
                      enabled: !saving,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Counter step',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  SizedBox(
                    width: 260,
                    child: DropdownButton<bool>(
                      isExpanded: true,
                      value: move,
                      items: [
                        const DropdownMenuItem(
                          value: false,
                          child: Text('Create renamed copies'),
                        ),
                        DropdownMenuItem(
                          value: true,
                          enabled: !model.root.startsWith('content://'),
                          child: const Text(
                            'Rename via move · retain originals',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      onChanged: saving
                          ? null
                          : (value) => setState(() => move = value ?? false),
                    ),
                  ),
                ],
              ),
              DropdownButton<int>(
                isExpanded: true,
                value: destination,
                items: [
                  for (var i = 0; i < destinations.length; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text(
                        destinations[i].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: saving
                    ? null
                    : (value) => setState(() => destination = value ?? 0),
              ),
              if (widget.paths.any(model.state.decisions.containsKey))
                const Text(
                  'Staging will replace existing decisions for the selected photographs.',
                ),
              if (error != null || previewError != null)
                Text(
                  error ?? previewError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (loading || saving) const LinearProgressIndicator(),
              if (!loading)
                Text(
                  '${changed.length} changes · destination collisions are checked before commit',
                ),

              for (final row in rows)
                ListTile(
                  dense: true,
                  title: Text(row.path.split('/').last),
                  subtitle: Text(
                    row.error ??
                        (sameFolder && row.unchanged
                            ? '${row.name} · unchanged'
                            : '→ ${row.name}'),
                  ),
                  textColor: row.error == null
                      ? null
                      : Theme.of(context).colorScheme.error,
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: !valid
              ? null
              : () async {
                  setState(() => saving = true);
                  final okay = await model.stage(
                    changed.map((r) => r.path).toList(),
                    target,
                    move: move,
                    nextSelected: model.state.selected,
                    outputNames: {
                      for (final row in changed) row.path: row.name,
                    },
                    expectedVersions: versions,
                  );
                  if (!context.mounted) return;
                  if (okay) {
                    Navigator.pop(context);
                  } else {
                    setState(() {
                      saving = false;
                      error = model.error ?? 'Could not stage this batch.';
                    });
                  }
                },
          child: Text(
            saving
                ? 'Saving…'
                : 'Stage ${changed.length} ${move ? 'renames' : 'renamed copies'}',
          ),
        ),
      ],
    );
  }
}
