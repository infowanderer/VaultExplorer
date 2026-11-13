import 'dart:async';
import 'package:vaultexplorer/core/widgets/thumbnail/priority_task_queue.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'sort_session.dart';
import '../browser/viewer/media_input.dart';

typedef PhotoPreviewLoader = Future<Uint8List?> Function(String path, int size);

/// Experimental read-only integration. Decisions stay in memory; no disk cache,
/// copy/move/delete API, export, or network operation is exposed by this screen.
class PhotoSorterScreen extends StatefulWidget {
  const PhotoSorterScreen({
    super.key,
    required this.photos,
    required this.folderName,
    required this.loadPreview,
    this.destinations = const ['Favorites', 'Share', 'Sort later'],
  });
  final List<String> photos;
  final String folderName;
  final PhotoPreviewLoader loadPreview;
  // Named routing buckets in this spike, not resolved filesystem destinations.
  final List<String> destinations;
  @override
  State<PhotoSorterScreen> createState() => _PhotoSorterScreenState();
}

class _PhotoSorterScreenState extends State<PhotoSorterScreen>
    with WidgetsBindingObserver {
  late final session = SortSession(widget.photos);
  final scroll = ScrollController();
  final imageTransform = TransformationController();
  Size imageViewport = Size.zero;
  final previewQueue = PriorityTaskQueue(2);

  Future<Uint8List?> loadPreview(String path, int size) async {
    final turn = Completer<void>();
    await previewQueue.acquire(turn);
    try {
      if (!mounted || suspended) return null;
      return await widget.loadPreview(path, size);
    } finally {
      previewQueue.release(turn);
    }
  }

  bool viewing = false;
  bool suspended = false;
  int columns = 1;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    imageTransform.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && mounted) {
      setState(() {
        suspended = true;
        session.clear();
      });
    }
  }

  void navigate(int delta) {
    setState(() {
      session.navigate(delta);
      imageTransform.value = Matrix4.identity();
    });
    if (!viewing && scroll.hasClients) {
      final top = (session.selected ~/ columns) * 180.0;
      final bottom = top + 180;
      final offset = scroll.offset;
      if (top < offset || bottom > offset + scroll.position.viewportDimension) {
        scroll.jumpTo(top.clamp(0.0, scroll.position.maxScrollExtent));
      }
    }
  }

  void stage(String destination) {
    setState(() => session.stage(destination));
    navigate(0);
  }

  Future<void> leave() async {
    final leave =
        session.decisions.isEmpty ||
        await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Discard staged decisions?'),
                content: const Text(
                  'This preview keeps decisions only while this screen is open.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Stay'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Discard'),
                  ),
                ],
              ),
            ) ==
            true;
    if (leave && mounted) {
      setState(session.clear);
      if (mounted) Navigator.pop(context);
    }
  }

  void showQueue() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Staged decisions'),
        content: SizedBox(
          width: 560,
          height: 360,
          child: Column(
            children: [
              const Text(
                'Preview only. Folder destinations and verified transfers are not connected yet.',
              ),
              Expanded(
                child: ListView(
                  children: session.decisions.entries
                      .map(
                        (entry) => ListTile(
                          title: Text(entry.key.split('/').last),
                          subtitle: Text(entry.value),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (suspended) {
      return Scaffold(
        appBar: AppBar(title: const Text('Photo sorter')),
        body: const Center(
          child: Text(
            'Preview closed when the app left the foreground.\nReturn to the folder and reopen it.',
          ),
        ),
      );
    }
    return PopScope(
      canPop: session.decisions.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) leave();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              navigate(1),
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              navigate(-1),
          const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
              navigate(columns),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
              navigate(-columns),
          const SingleActivator(LogicalKeyboardKey.space): () =>
              setState(() => viewing = !viewing),
          const SingleActivator(LogicalKeyboardKey.escape): leave,
          const SingleActivator(LogicalKeyboardKey.backspace): () =>
              setState(session.clearCurrent),
          for (var i = 0; i < widget.destinations.length && i < 9; i++)
            SingleActivator(
              [
                LogicalKeyboardKey.digit1,
                LogicalKeyboardKey.digit2,
                LogicalKeyboardKey.digit3,
                LogicalKeyboardKey.digit4,
                LogicalKeyboardKey.digit5,
                LogicalKeyboardKey.digit6,
                LogicalKeyboardKey.digit7,
                LogicalKeyboardKey.digit8,
                LogicalKeyboardKey.digit9,
              ][i],
            ): () =>
                stage(widget.destinations[i]),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              title: Text('Sort photos · ${widget.folderName}'),
              actions: [
                IconButton(
                  tooltip: 'Preview queue',
                  onPressed: showQueue,
                  icon: Badge(
                    label: Text('${session.decisions.length}'),
                    child: const Icon(Icons.playlist_add_check),
                  ),
                ),
              ],
            ),
            body: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text(
                    'Experimental preview · decisions stay in memory · no files are changed.\n'
                    'Tap or pen to select; double tap or Space to view; arrows to navigate; 1–3 to sort.',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < widget.destinations.length; i++)
                        FilledButton.tonal(
                          onPressed: session.current == null
                              ? null
                              : () => stage(widget.destinations[i]),
                          child: Text('${i + 1} · ${widget.destinations[i]}'),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: session.photos.isEmpty
                      ? const Center(
                          child: Text('No photographs in this folder.'),
                        )
                      : viewing
                      ? MediaInputScope(
                          onCommand: (command) {
                            if (command == MediaInputCommand.forward ||
                                command == MediaInputCommand.backward) {
                              navigate(
                                command == MediaInputCommand.forward ? 1 : -1,
                              );
                            } else {
                              final zoomIn =
                                  command == MediaInputCommand.controlForward ||
                                  command == MediaInputCommand.controlWheelUp;
                              imageTransform.value = steppedMediaZoom(
                                imageTransform.value,
                                imageViewport,
                                zoomIn ? 1 : -1,
                              );
                            }
                            return true;
                          },
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              imageViewport = constraints.biggest;
                              return InteractiveViewer(
                                scaleFactor: MediaInputScope.wheelScaleFactor(
                                  context,
                                ),
                                transformationController: imageTransform,
                                maxScale: 8,
                                child: MediaPointerRegion(
                                  child: Center(
                                    child: _Preview(
                                      key: ValueKey(
                                        'viewer-${session.current}',
                                      ),
                                      path: session.current!,
                                      size: 1600,
                                      load: loadPreview,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            columns = (constraints.maxWidth / 200)
                                .floor()
                                .clamp(1, 12);
                            return GridView.builder(
                              controller: scroll,
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: columns,
                                    mainAxisExtent: 180,
                                    crossAxisSpacing: 8,
                                    mainAxisSpacing: 8,
                                  ),
                              padding: const EdgeInsets.all(8),
                              itemCount: session.photos.length,
                              itemBuilder: (context, index) {
                                final path = session.photos[index];
                                final destination = session.decisions[path];
                                return Semantics(
                                  selected: index == session.selected,
                                  label: path.split('/').last,
                                  child: InkWell(
                                    onTap: () => setState(() {
                                      session.select(index);
                                      imageTransform.value = Matrix4.identity();
                                    }),
                                    onDoubleTap: () => setState(() {
                                      session.select(index);
                                      imageTransform.value = Matrix4.identity();
                                      viewing = true;
                                    }),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          width: 3,
                                          color: index == session.selected
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.primary
                                              : Colors.transparent,
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          Expanded(
                                            child: _Preview(
                                              key: ValueKey(path),
                                              path: path,
                                              size: 300,
                                              load: loadPreview,
                                            ),
                                          ),
                                          Text(
                                            path.split('/').last,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (destination != null)
                                            Text(
                                              destination,
                                              style: TextStyle(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      alignment: WrapAlignment.center,
                      children: [
                        IconButton(
                          tooltip: 'Previous photo',
                          onPressed: () => navigate(-1),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Text(
                          session.current == null
                              ? '0 / 0'
                              : '${session.selected + 1} / ${session.photos.length}',
                        ),
                        IconButton(
                          tooltip: 'Next photo',
                          onPressed: () => navigate(1),
                          icon: const Icon(Icons.chevron_right),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () => setState(() => viewing = !viewing),
                          child: Text(viewing ? 'Grid' : 'View'),
                        ),
                        TextButton(
                          onPressed: () => setState(session.clearCurrent),
                          child: const Text('Clear decision'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Preview extends StatefulWidget {
  const _Preview({
    super.key,
    required this.path,
    required this.size,
    required this.load,
  });
  final String path;
  final int size;
  final PhotoPreviewLoader load;
  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  late final Future<Uint8List?> bytes = widget.load(widget.path, widget.size);
  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: bytes,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError || snapshot.data == null) {
        return const Center(child: Icon(Icons.broken_image_outlined));
      }
      return Image.memory(
        snapshot.data!,
        fit: BoxFit.contain,
        cacheWidth: widget.size,
        errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
      );
    },
  );
}
