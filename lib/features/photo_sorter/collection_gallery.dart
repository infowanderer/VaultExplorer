import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import '../browser/viewer/media_input.dart';
import 'organizer.dart';
import 'organizer_catalog.dart';
import 'organizer_action_button.dart';
import 'package:vaultexplorer/core/widgets/thumbnail/priority_task_queue.dart';

final _collectionPreviews = PriorityTaskQueue(2);

/// Collection membership does not grant access or trust a replacement file.
class ReferenceImage extends StatefulWidget {
  const ReferenceImage({
    super.key,
    required this.reference,
    required this.bridge,
    this.size = 300,
  });
  final MediaReference reference;
  final OrganizerBridge bridge;
  final int size;
  @override
  State<ReferenceImage> createState() => _ReferenceImageState();
}

class _ReferenceImageState extends State<ReferenceImage> {
  late Future<Uint8List?> future = load();
  Future<Uint8List?> load() async {
    final turn = Completer<void>();
    await _collectionPreviews.acquire(turn);
    try {
      if (!mounted) return null;
      final ref = widget.reference;
      final before = ref.pending
          ? await widget.bridge.inspect(ref.root, ref.path)
          : await widget.bridge.fingerprint(ref.root, ref.path);
      if (!ref.matches(before)) {
        throw StateError('The saved media identity changed');
      }
      final bytes = await widget.bridge.referenceThumbnail(
        ref,
        size: widget.size,
      );
      final after = await widget.bridge.inspect(ref.root, ref.path);
      if (before['identity'] != after['identity'] ||
          before['size'] != after['size'] ||
          before['modified'] != after['modified']) {
        bytes?.fillRange(0, bytes.length, 0);
        throw StateError('Media changed during preview');
      }
      return bytes;
    } finally {
      _collectionPreviews.release(turn);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return const Center(
          child: Text('Changed or unavailable', textAlign: TextAlign.center),
        );
      }
      final bytes = snapshot.data;
      if (bytes == null) {
        return const Center(child: Text('Preview unavailable'));
      }
      return Image.memory(
        bytes,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        cacheWidth: widget.size,
        errorBuilder: (_, _, _) =>
            const Center(child: Text('Preview unavailable')),
      );
    },
  );
}

class CollectionGalleryScreen extends StatefulWidget {
  const CollectionGalleryScreen({
    super.key,
    required this.name,
    required this.members,
    required this.bridge,
    this.showLabels = true,
  });
  final String name;
  final List<MediaReference> members;
  final OrganizerBridge bridge;
  final bool showLabels;
  @override
  State<CollectionGalleryScreen> createState() =>
      _CollectionGalleryScreenState();
}

class _CollectionGalleryScreenState extends State<CollectionGalleryScreen>
    with WidgetsBindingObserver {
  int? selected;
  bool paused = false;
  final transform = TransformationController();
  Size viewport = Size.zero;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    transform.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && mounted) {
      setState(() => paused = true);
      widget.bridge.cancelAll().catchError((Object _) {
        /* The app-level lifecycle also cancels native reads. */
      });
    }
  }

  void navigate(int delta) {
    setState(() {
      selected = ((selected ?? 0) + delta).clamp(0, widget.members.length - 1);
      transform.value = Matrix4.identity();
    });
  }

  void leave() {
    if (selected != null) {
      setState(() => selected = null);
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (paused) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.name)),
        body: Center(
          child: TextButton(
            onPressed: () => setState(() => paused = false),
            child: const Text('Resume collection'),
          ),
        ),
      );
    }
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): leave,
        if (selected != null)
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              navigate(-1),
        if (selected != null)
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              navigate(1),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              '${widget.name} · ${widget.members.length}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              if (selected != null)
                OrganizerActionButton(
                  label: 'Grid',
                  tooltip: 'Return to collection grid (Escape)',
                  icon: const Icon(Icons.grid_view),
                  showLabel: widget.showLabels,
                  onPressed: () => setState(() => selected = null),
                ),
            ],
          ),
          body: widget.members.isEmpty
              ? const Center(
                  child: Text(
                    'No matching saved photographs. Review and tag photographs in their folders to build saved-search results.',
                  ),
                )
              : selected == null
              ? LayoutBuilder(
                  builder: (_, constraints) => GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: (constraints.maxWidth / 220)
                          .floor()
                          .clamp(1, 8),
                      mainAxisExtent: 220,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: widget.members.length,
                    itemBuilder: (_, i) {
                      final ref = widget.members[i];
                      return InkWell(
                        onTap: () => setState(() => selected = i),
                        child: Column(
                          children: [
                            Expanded(
                              child: ReferenceImage(
                                key: ValueKey(ref.key),
                                reference: ref,
                                bridge: widget.bridge,
                              ),
                            ),
                            Text(
                              ref.path.split('/').last,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              ref.root,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                )
              : MediaInputScope(
                  onCommand: (command) {
                    if (command == MediaInputCommand.forward ||
                        command == MediaInputCommand.backward) {
                      navigate(command == MediaInputCommand.forward ? 1 : -1);
                    } else {
                      transform.value = steppedMediaZoom(
                        transform.value,
                        viewport,
                        (command == MediaInputCommand.controlForward ||
                                command == MediaInputCommand.controlWheelUp)
                            ? 1
                            : -1,
                      );
                    }
                    return true;
                  },
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      viewport = constraints.biggest;
                      return InteractiveViewer(
                        transformationController: transform,
                        maxScale: 8,
                        scaleFactor: MediaInputScope.wheelScaleFactor(context),
                        child: MediaPointerRegion(
                          child: Center(
                            child: ReferenceImage(
                              key: ValueKey(widget.members[selected!].key),
                              reference: widget.members[selected!],
                              bridge: widget.bridge,
                              size: 1600,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ),
    );
  }
}
