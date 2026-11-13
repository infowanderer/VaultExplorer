import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'collection_gallery.dart';
import 'organizer.dart';
import 'organizer_catalog.dart';

class CollectionsDialog extends StatefulWidget {
  const CollectionsDialog({
    super.key,
    required this.controller,
    required this.paths,
    required this.filter,
  });
  final OrganizerController controller;
  final List<String> paths;
  final CollectionFilter filter;
  @override
  State<CollectionsDialog> createState() => _CollectionsDialogState();
}

class _CollectionsDialogState extends State<CollectionsDialog> {
  List<OrganizerCollection> items = [];
  bool busy = true;
  String? error;
  OrganizerCatalog get catalog => widget.controller.repository.catalog;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    try {
      final found = await catalog.list();
      if (mounted) {
        setState(() {
          items = found;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Protected collections are unavailable. Existing records are retained.',
        );
      }
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> perform(Future<void> Function() operation) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await operation();
      if (mounted) await load();
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error =
              'Could not save this collection. Check access, protected storage, unique names and collection limits.';
        });
      }
    }
  }

  Future<List<MediaReference>> references() async {
    if (widget.paths.isEmpty || widget.paths.length > 200) {
      throw StateError('Select 1–200 photographs');
    }
    final result = <MediaReference>[];
    for (final path in widget.paths) {
      if (!mounted) throw StateError('Collection action closed');
      final found = await widget.controller.bridge.fingerprint(
        widget.controller.root,
        path,
      );
      result.add(
        MediaReference.fromJson({
          ...found,
          'root': widget.controller.root,
          'path': path,
        }),
      );
    }
    return result;
  }

  Future<String?> name(String title, {String initial = ''}) async {
    var value = initial;
    return showDialog<String>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(title),
          content: TextFormField(
            initialValue: initial,
            autofocus: true,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'Collection name'),
            onChanged: (text) => update(() => value = text),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: validCollectionName(value)
                  ? () => Navigator.pop(dialog, value.trim())
                  : null,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> open(OrganizerCollection item) async {
    setState(() => busy = true);
    try {
      final members = item.filter == null
          ? item.members
          : await widget.controller.repository.searchReviewed(item.filter!);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CollectionGalleryScreen(
            name: item.name,
            members: members,
            bridge: widget.controller.bridge,
            showLabels: widget.controller.showButtonLabels,
          ),
        ),
      );
      if (mounted) setState(() => busy = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error =
              'Could not read the saved search. Existing metadata has not been changed.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Collections and saved searches'),
    content: SizedBox(
      width: 700,
      height: MediaQuery.sizeOf(context).height * .6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.paths.length} selected photographs. Collections reference files without copying or moving them. Saved searches use protected reviews across opened folders.',
          ),
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          Expanded(
            child: ListView(
              children: [
                for (final item in items)
                  ListTile(
                    leading: Icon(
                      item.isSearch
                          ? Icons.saved_search
                          : Icons.collections_bookmark_outlined,
                    ),
                    title: Text(item.name),
                    subtitle: Text(
                      item.isSearch
                          ? 'Dynamic saved search'
                          : '${item.members.length} saved references',
                    ),
                    onTap: busy ? null : () => open(item),
                    trailing: PopupMenuButton<String>(
                      tooltip: 'Collection actions',
                      enabled: !busy,
                      itemBuilder: (_) => [
                        if (!item.isSearch)
                          const PopupMenuItem(
                            value: 'add',
                            child: Text('Add selected photographs'),
                          ),
                        const PopupMenuItem(
                          value: 'rename',
                          child: Text('Rename collection'),
                        ),
                        const PopupMenuItem(
                          value: 'remove',
                          child: Text('Remove collection · keep files'),
                        ),
                      ],
                      onSelected: (action) async {
                        if (action == 'add') {
                          await perform(
                            () async =>
                                catalog.addMembers(item.id, await references()),
                          );
                        }
                        if (action == 'rename') {
                          final next = await name(
                            'Rename collection',
                            initial: item.name,
                          );
                          if (next != null && mounted) {
                            await perform(() => catalog.rename(item.id, next));
                          }
                        }
                        if (action == 'remove') {
                          await perform(() => catalog.remove(item.id));
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy || widget.paths.isEmpty
            ? null
            : () async {
                final next = await name('New collection from selection');
                if (next != null && mounted) {
                  await perform(() async {
                    await catalog.create(next, members: await references());
                  });
                }
              },
        child: const Text('Collect selected'),
      ),
      TextButton(
        onPressed: busy
            ? null
            : () async {
                final next = await name('Save current search');
                if (next != null && mounted) {
                  await perform(() async {
                    await catalog.create(next, filter: widget.filter);
                  });
                }
              },
        child: const Text('Save current search'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}
