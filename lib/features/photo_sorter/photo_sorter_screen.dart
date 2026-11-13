import 'dart:async';
import 'package:vaultexplorer/core/widgets/thumbnail/priority_task_queue.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'sort_session.dart';
import 'organizer.dart';
import 'organizer_widgets.dart';
import 'organizer_action_button.dart';
import '../browser/viewer/media_input.dart';

typedef PhotoPreviewLoader = Future<Uint8List?> Function(String path, int size);

/// Photo workspace with injected protected state/transfer services. Without a
/// controller it remains an in-memory, read-only preview for isolated tests.
class PhotoSorterScreen extends StatefulWidget {
  const PhotoSorterScreen({
    super.key,
    required this.photos,
    required this.folderName,
    required this.loadPreview,
    this.organizer,
    this.pickDestination,
    this.destinations = const ['Favorites', 'Share', 'Sort later'],
  });
  final OrganizerController? organizer;
  final Future<OrganizerFolder?> Function()? pickDestination;
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
  late SortSession session = SortSession(widget.photos);
  final selectedPhotos = <String>{};
  String query = '';
  ReviewState? stateFilter;
  int minimumRating = 0;
  bool typing = false, moveMode = false;
  bool previewButtonLabels = true;
  bool get showButtonLabels =>
      organizer?.showButtonLabels ?? previewButtonLabels;
  OrganizerController? get organizer => widget.organizer;
  List<String> get destinations =>
      organizer?.state.destinations.map((d) => d.name).toList() ??
      widget.destinations;

  void organizerChanged() {
    if (!mounted) return;
    final model = organizer!;
    final restored = model.jobs
        .where((j) => j['state'] == 'undone')
        .map((j) => (j['source'] as Map)['path'] as String);
    final visible = <String>{...widget.photos, ...restored}
        .where((path) => model.matches(path, query, stateFilter, minimumRating))
        .toList();
    setState(() {
      session = SortSession(visible)
        ..restore(
          selected: model.state.selected,
          decisions: model.state.decisions.map(
            (key, value) =>
                MapEntry(key, (value['folder'] as Map)['name'] as String),
          ),
        );
      selectedPhotos.removeWhere((path) => !visible.contains(path));
    });
  }

  void choose(int index) {
    setState(() {
      session.select(index);
      imageTransform.value = Matrix4.identity();
      if (selectedPhotos.isNotEmpty) {
        final path = session.current!;
        if (!selectedPhotos.add(path)) selectedPhotos.remove(path);
      }
    });
    unawaited(organizer?.select(session.current) ?? Future<void>.value());
  }

  Future<void> editReview() async {
    if (organizer?.ready != true ||
        session.current == null ||
        organizer!.saving ||
        organizer!.running) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => PhotoReviewDialog(
        controller: organizer!,
        paths: selectedPhotos.isEmpty
            ? [session.current!]
            : selectedPhotos.toList(),
      ),
    );
  }

  Future<void> addDestination() async {
    if (organizer?.ready != true || organizer!.running || organizer!.saving) {
      return;
    }
    try {
      final folder = await widget.pickDestination?.call();
      if (!mounted || folder == null) return;
      await organizer!.addDestination(folder);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Choose an accessible local, SD or USB folder. Cloud providers are not enabled in this build.',
            ),
          ),
        );
      }
    }
  }

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
    organizer?.addListener(organizerChanged);
    if (organizer != null) unawaited(organizer!.open());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    organizer?.removeListener(organizerChanged);
    organizer?.dispose();
    imageTransform.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && mounted) {
      setState(() {
        suspended = true;
        if (organizer == null) session.clear();
      });
      organizer?.pause();
      if (organizer != null) unawaited(organizer!.saveSelection());
    }
  }

  void navigate(int delta) {
    setState(() {
      session.navigate(delta);
      imageTransform.value = Matrix4.identity();
    });
    unawaited(organizer?.select(session.current) ?? Future<void>.value());
    if (!viewing && scroll.hasClients) {
      final top = (session.selected ~/ columns) * 180.0;
      final bottom = top + 180;
      final offset = scroll.offset;
      if (top < offset || bottom > offset + scroll.position.viewportDimension) {
        scroll.jumpTo(top.clamp(0.0, scroll.position.maxScrollExtent));
      }
    }
  }

  Future<void> stage(String destination) async {
    if (organizer == null) {
      setState(() => session.stage(destination));
      navigate(0);
      return;
    }
    final model = organizer!;
    if (session.current == null || model.running || model.saving) return;
    final paths = selectedPhotos.isEmpty
        ? [session.current!]
        : selectedPhotos.toList();
    final next = session
        .photos[(session.selected + 1).clamp(0, session.photos.length - 1)];
    final target = model.state.destinations.firstWhere(
      (d) => d.name == destination,
    );
    if (await model.stage(paths, target, move: moveMode, nextSelected: next) &&
        mounted) {
      setState(() => selectedPhotos.clear());
    }
  }

  void clearDecision() {
    if (organizer == null) {
      setState(session.clearCurrent);
    } else if (session.current != null) {
      unawaited(organizer!.clearDecision(session.current!));
    }
  }

  Future<void> leave() async {
    if (organizer != null) {
      organizer!.pause();
      await organizer!.saveSelection();
      if (mounted) Navigator.pop(context);
      return;
    }
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
    if (organizer != null) {
      showDialog<void>(
        context: context,
        builder: (_) => OrganizerQueueDialog(controller: organizer!),
      );
      return;
    }
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

  Widget actionButton({
    required String label,
    required String tooltip,
    required Widget icon,
    required VoidCallback? onPressed,
  }) => OrganizerActionButton(
    label: label,
    tooltip: tooltip,
    icon: icon,
    showLabel: showButtonLabels,
    onPressed: onPressed,
  );

  Widget get toolbar => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        if (organizer != null)
          actionButton(
            label: 'Add destination',
            tooltip: 'Add destination folder',
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed:
                organizer!.running ||
                    organizer!.saving ||
                    destinations.length >= 9
                ? null
                : addDestination,
          ),
        if (organizer != null)
          actionButton(
            label: 'Review',
            tooltip: 'Review / rate / tag (R)',
            icon: const Icon(Icons.sell_outlined),
            onPressed: editReview,
          ),
        actionButton(
          label: 'Queue',
          tooltip: organizer == null
              ? 'Preview queue'
              : 'Operation queue & history',
          icon: Badge(
            label: Text('${session.decisions.length}'),
            child: const Icon(Icons.playlist_add_check),
          ),
          onPressed: showQueue,
        ),
        if (organizer != null)
          actionButton(
            label: 'Find renamed',
            tooltip: 'Verify reviews / find renamed files',
            icon: const Icon(Icons.find_replace),
            onPressed:
                organizer!.running ||
                    organizer!.saving ||
                    organizer!.verifyingReviews
                ? null
                : organizer!.verifySavedReviews,
          ),
        if (organizer != null && organizer!.reviewWarnings.isNotEmpty)
          actionButton(
            label: 'Warnings',
            tooltip: 'Review identity warnings',
            icon: const Icon(Icons.warning_amber_outlined),
            onPressed: () =>
                showReviewWarnings(context, organizer!, session.current),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (organizer != null && !organizer!.ready) {
      return Scaffold(
        appBar: AppBar(title: const Text('Photo organizer')),
        body: Center(
          child: organizer!.error == null
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(organizer!.error!),
                      TextButton(
                        onPressed: organizer!.open,
                        child: const Text('Retry protected storage'),
                      ),
                    ],
                  ),
                ),
        ),
      );
    }
    if (suspended && organizer != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Photo organizer paused')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Your saved decisions are protected. Transfers pause safely when this screen leaves the foreground.',
              ),
              TextButton(
                onPressed: organizer!.running
                    ? null
                    : () async {
                        await organizer!.open();
                        if (mounted && organizer!.ready) {
                          setState(() => suspended = false);
                        }
                      },
                child: const Text('Resume organizer'),
              ),
            ],
          ),
        ),
      );
    }
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
      canPop: organizer != null || session.decisions.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) leave();
      },
      child: CallbackShortcuts(
        bindings: typing
            ? const {}
            : {
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
                const SingleActivator(LogicalKeyboardKey.backspace):
                    clearDecision,
                if (organizer != null)
                  const SingleActivator(LogicalKeyboardKey.keyR): editReview,
                for (var i = 0; i < destinations.length && i < 9; i++)
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
                      stage(destinations[i]),
              },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              title: Text(
                'Sort photos · ${widget.folderName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              actions: [
                actionButton(
                  label: 'Labels',
                  tooltip: showButtonLabels
                      ? 'Hide button labels'
                      : 'Show button labels',
                  icon: Icon(
                    showButtonLabels
                        ? Icons.label_outline
                        : Icons.label_off_outlined,
                  ),
                  onPressed:
                      organizer?.saving == true || organizer?.running == true
                      ? null
                      : () async {
                          if (organizer != null) {
                            await organizer!.setButtonLabels(!showButtonLabels);
                          } else {
                            setState(
                              () => previewButtonLabels = !previewButtonLabels,
                            );
                          }
                        },
                ),
              ],
            ),
            body: Column(
              children: [
                toolbar,
                if (organizer == null)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'Experimental preview · decisions stay in memory · no files are changed.\nTap or pen to select; double tap or Space to view; arrows to navigate; 1–3 to sort.',
                    ),
                  )
                else ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Wrap(
                      spacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 290,
                          child: DropdownButton<bool>(
                            isExpanded: true,
                            value: moveMode,
                            items: [
                              const DropdownMenuItem(
                                value: false,
                                child: Text('Stage copies'),
                              ),
                              DropdownMenuItem(
                                value: true,
                                enabled: !organizer!.root.startsWith(
                                  'content://',
                                ),
                                child: const Text(
                                  'Stage moves · retain originals in Trash',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                            onChanged: organizer!.running || organizer!.saving
                                ? null
                                : (value) =>
                                      setState(() => moveMode = value ?? false),
                          ),
                        ),
                        Text(
                          organizer!.saving
                              ? 'Saving protected decisions…'
                              : 'Decisions saved · 1–9 destinations · R review · long press to select',
                        ),
                        if (selectedPhotos.isNotEmpty)
                          TextButton(
                            onPressed: () =>
                                setState(() => selectedPhotos.clear()),
                            child: Text(
                              'Clear ${selectedPhotos.length} selected',
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Wrap(
                      spacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 230,
                          child: Focus(
                            onFocusChange: (value) {
                              if (mounted) setState(() => typing = value);
                            },
                            child: TextField(
                              decoration: const InputDecoration(
                                labelText: 'Find filename or tag',
                              ),
                              onChanged: (value) {
                                query = value;
                                organizerChanged();
                              },
                            ),
                          ),
                        ),
                        DropdownButton<ReviewState?>(
                          value: stateFilter,
                          items: [
                            const DropdownMenuItem<ReviewState?>(
                              value: null,
                              child: Text('All review states'),
                            ),
                            for (final state in ReviewState.values)
                              DropdownMenuItem(
                                value: state,
                                child: Text(reviewLabel(state)),
                              ),
                          ],
                          onChanged: (value) {
                            stateFilter = value;
                            organizerChanged();
                          },
                        ),
                        DropdownButton<int>(
                          value: minimumRating,
                          items: [
                            for (var i = 0; i <= 5; i++)
                              DropdownMenuItem(
                                value: i,
                                child: Text(
                                  i == 0 ? 'Any rating' : '$i+ stars',
                                ),
                              ),
                          ],
                          onChanged: (value) {
                            minimumRating = value ?? 0;
                            organizerChanged();
                          },
                        ),
                      ],
                    ),
                  ),
                  if (organizer!.verifyingReviews)
                    const Text('Verifying saved reviews in the background…'),
                  if (organizer!.relocationNotice != null)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(organizer!.relocationNotice!),
                    ),
                  if (organizer!.reviewWarnings.isNotEmpty)
                    Text(
                      '${organizer!.reviewWarnings.length} saved reviews need reconciliation; their metadata is retained.',
                    ),
                  if (organizer!.error != null)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        organizer!.error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (destinations.isEmpty)
                    TextButton.icon(
                      onPressed: addDestination,
                      icon: const Icon(Icons.add),
                      label: const Text('Choose your first destination folder'),
                    ),
                ],
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < destinations.length; i++)
                        FilledButton.tonal(
                          onPressed: session.current == null
                              ? null
                              : () => stage(destinations[i]),
                          child: Text('${i + 1} · ${destinations[i]}'),
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
                                    mainAxisExtent: organizer == null
                                        ? 180
                                        : 210,
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
                                    onTap: () => choose(index),
                                    onLongPress: organizer == null
                                        ? null
                                        : () => setState(() {
                                            if (!selectedPhotos.add(path)) {
                                              selectedPhotos.remove(path);
                                            }
                                          }),
                                    onDoubleTap: () => setState(() {
                                      session.select(index);
                                      unawaited(
                                        organizer?.select(session.current) ??
                                            Future<void>.value(),
                                      );
                                      imageTransform.value = Matrix4.identity();
                                      viewing = true;
                                    }),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          width: 3,
                                          color:
                                              selectedPhotos.contains(path) ||
                                                  index == session.selected
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.primary
                                              : Colors.transparent,
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          Expanded(
                                            child: Stack(
                                              fit: StackFit.expand,
                                              children: [
                                                _Preview(
                                                  key: ValueKey(path),
                                                  path: path,
                                                  size: 300,
                                                  load: loadPreview,
                                                ),
                                                if (destination != null)
                                                  Positioned(
                                                    top: 6,
                                                    right: 6,
                                                    child: Container(
                                                      constraints:
                                                          const BoxConstraints(
                                                            maxWidth: 150,
                                                          ),
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                            vertical: 4,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .primaryContainer,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              12,
                                                            ),
                                                      ),
                                                      child: Text(
                                                        destination,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            path.split('/').last,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (organizer != null &&
                                              organizer!.reviewFor(path) !=
                                                  null)
                                            Text(
                                              '${reviewLabel(organizer!.reviewFor(path)!.state)} · ${organizer!.reviewFor(path)!.rating == 0 ? 'unrated' : '${organizer!.reviewFor(path)!.rating}★'} · ${organizer!.reviewFor(path)!.tags.join(', ')}',
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
                        actionButton(
                          label: 'Previous',
                          tooltip: 'Previous photo (Left arrow)',
                          onPressed: () => navigate(-1),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Text(
                          session.current == null
                              ? '0 / 0'
                              : '${session.selected + 1} / ${session.photos.length}',
                        ),
                        actionButton(
                          label: 'Next',
                          tooltip: 'Next photo (Right arrow)',
                          onPressed: () => navigate(1),
                          icon: const Icon(Icons.chevron_right),
                        ),
                        actionButton(
                          label: viewing ? 'Grid' : 'View',
                          tooltip: viewing
                              ? 'Show thumbnail grid (Space)'
                              : 'Enlarge current photo (Space)',
                          icon: Icon(
                            viewing ? Icons.grid_view : Icons.photo_outlined,
                          ),
                          onPressed: () => setState(() => viewing = !viewing),
                        ),
                        actionButton(
                          label: 'Unstage',
                          tooltip: 'Unstage current photo (Backspace)',
                          icon: const Icon(Icons.backspace_outlined),
                          onPressed: clearDecision,
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
