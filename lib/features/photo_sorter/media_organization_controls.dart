import 'package:material_ui/material_ui.dart';

import 'organizer.dart';
import 'organizer_action_button.dart';
import 'destination_search.dart';

class MediaOrganizationControls extends StatelessWidget {
  const MediaOrganizationControls({
    super.key,
    required this.model,
    required this.paths,
    required this.onSort,
    required this.onTags,
    this.onQueue,
    this.overlay = false,
    this.enabled = true,
  });
  final OrganizerController model;
  final List<String> paths;
  final VoidCallback onSort, onTags;
  final VoidCallback? onQueue;
  final bool overlay, enabled;
  @override
  Widget build(BuildContext context) {
    final rating = paths.length == 1
        ? model.reviewFor(paths.first)?.rating ?? 0
        : 0;
    final active =
        enabled &&
        model.ready &&
        paths.isNotEmpty &&
        !model.running &&
        !model.saving;
    return Material(
      color: overlay ? Colors.black87 : Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!model.ready && model.error == null && paths.isNotEmpty)
                const LinearProgressIndicator(minHeight: 2),
              if (model.error != null)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        model.error!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: overlay
                              ? Colors.white
                              : Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: model.running || model.saving
                          ? null
                          : () => model.open(verifyContent: false),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 2,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var value = 1; value <= 5; value++)
                        IconButton(
                          tooltip:
                              'Rate $value ${value == 1 ? 'star' : 'stars'} ($value)',
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          icon: Icon(
                            value <= rating
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            color: value <= rating
                                ? (overlay
                                      ? Colors.amber
                                      : Theme.of(context).colorScheme.primary)
                                : overlay
                                ? Colors.white70
                                : null,
                          ),
                          onPressed: active
                              ? () => model.setRating(paths, value)
                              : null,
                        ),
                    ],
                  ),
                  OrganizerActionButton(
                    label: 'Sort',
                    foregroundColor: overlay ? Colors.white : null,
                    tooltip: 'Choose a destination (S)',
                    icon: const Icon(Icons.drive_file_move_outline),
                    showLabel: model.showButtonLabels,
                    onPressed: active ? onSort : null,
                  ),
                  OrganizerActionButton(
                    label: 'Tags',
                    foregroundColor: overlay ? Colors.white : null,
                    tooltip: 'Edit tags (T)',
                    icon: const Icon(Icons.sell_outlined),
                    showLabel: model.showButtonLabels,
                    onPressed: active ? onTags : null,
                  ),
                  if (onQueue != null)
                    OrganizerActionButton(
                      label: 'Queue',
                      foregroundColor: overlay ? Colors.white : null,
                      tooltip: 'Operation queue & history',
                      icon: Badge(
                        label: Text('${model.state.decisions.length}'),
                        child: const Icon(Icons.playlist_add_check),
                      ),
                      showLabel: model.showButtonLabels,
                      onPressed: enabled ? onQueue : null,
                    ),
                  if (model.saving)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showMediaSortSheet(
  BuildContext context,
  OrganizerController model,
  List<String> paths, {
  Future<void> Function()? addDestination,
  String? nextSelected,
}) async {
  var move = false;
  var staging = false;
  var query = '';
  String? error;
  Future<void> stageDestination(
    int index,
    BuildContext sheet,
    StateSetter update,
  ) async {
    if (staging) return;
    update(() {
      staging = true;
      error = null;
    });
    final okay = await model.stage(
      paths,
      model.state.destinations[index],
      move: move,
      nextSelected: nextSelected ?? model.state.selected,
    );
    if (!sheet.mounted) return;
    if (okay) {
      Navigator.pop(sheet);
    } else {
      update(() {
        staging = false;
        error = model.error ?? 'Could not stage these files.';
      });
    }
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => StatefulBuilder(
      builder: (context, update) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .75,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sort ${paths.length} ${paths.length == 1 ? 'file' : 'files'}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    autofocus: true,
                    enabled: !staging,
                    decoration: const InputDecoration(
                      labelText: 'Find destination',
                      hintText: 'Type a name; Enter chooses the first match',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) => update(() => query = value),
                    onSubmitted: (_) {
                      final matches = rankDestinations(
                        model.state.destinations.map((d) => d.name).toList(),
                        query,
                      );
                      if (matches.isNotEmpty)
                        stageDestination(matches.first, sheet, update);
                    },
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Copy'),
                        selected: !move,
                        onSelected: (_) => update(() => move = false),
                      ),
                      ChoiceChip(
                        label: const Text('Move'),
                        selected: move,
                        onSelected: model.root.startsWith('content://')
                            ? null
                            : (_) => update(() => move = true),
                      ),
                    ],
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        if (model.state.destinations.isNotEmpty &&
                            rankDestinations(
                              model.state.destinations
                                  .map((d) => d.name)
                                  .toList(),
                              query,
                            ).isEmpty)
                          const ListTile(
                            title: Text('No matching destinations'),
                          ),
                        for (final i in rankDestinations(
                          model.state.destinations.map((d) => d.name).toList(),
                          query,
                        ))
                          ListTile(
                            leading: const Icon(Icons.folder_outlined),
                            title: Text(model.state.destinations[i].name),
                            trailing: Text('Alt+${i + 1}'),
                            onTap: staging
                                ? null
                                : () => stageDestination(i, sheet, update),
                          ),
                      ],
                    ),
                  ),
                  if (model.state.destinations.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Choose a destination folder to start sorting.',
                      ),
                    ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (addDestination != null)
                    TextButton.icon(
                      onPressed: () async {
                        Navigator.pop(sheet);
                        await addDestination();
                      },
                      icon: const Icon(Icons.create_new_folder_outlined),
                      label: const Text('Add destination'),
                    ),
                  const Text(
                    'Added to your queue. Run the queue when ready.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> showMediaTagsSheet(
  BuildContext context,
  OrganizerController model,
  List<String> paths,
) async {
  var value = paths.length == 1
      ? model.reviewFor(paths.first)?.tags.join(', ') ?? ''
      : '';
  var saving = false;
  String? error;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => StatefulBuilder(
      builder: (context, update) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tags for ${paths.length} ${paths.length == 1 ? 'file' : 'files'}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              TextFormField(
                initialValue: value,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Tags, separated by commas',
                ),
                onChanged: (text) => value = text,
              ),
              if (paths.length > 1)
                const Text('Replaces tags on all selected files.'),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        final tags = value
                            .split(',')
                            .map((s) => s.trim())
                            .where((s) => s.isNotEmpty)
                            .toSet()
                            .toList();
                        if (tags.length > 20 ||
                            tags.any(
                              (s) =>
                                  s.length > 40 ||
                                  s.codeUnits.any((c) => c < 32),
                            )) {
                          update(
                            () => error = 'Use up to 20 tags, each at most 40 characters.',
                          );
                          return;
                        }
                        update(() => saving = true);
                        final okay = await model.setTags(paths, tags);
                        if (!sheet.mounted) return;
                        if (okay) {
                          Navigator.pop(sheet);
                        } else {
                          update(() {
                            saving = false;
                            error = model.error;
                          });
                        }
                      },
                child: Text(saving ? 'Saving…' : 'Save tags'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
