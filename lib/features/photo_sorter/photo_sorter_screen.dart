import 'dart:async';
import 'package:vaultexplorer/core/widgets/thumbnail/priority_task_queue.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'sort_session.dart';
import 'organizer.dart';
import 'organizer_widgets.dart';
import 'organizer_action_button.dart';
import 'batch_rename_dialog.dart';
import 'collections_dialog.dart';
import 'organizer_catalog.dart';
import 'media_organization_controls.dart';
import 'media_organization_shortcuts.dart';
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
  bool searchVisible = false;
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

  List<String> get currentPaths => selectedPhotos.isEmpty
      ? [if (session.current != null) session.current!]
      : selectedPhotos.toList();
  void sortMedia() {
    if (organizer == null || currentPaths.isEmpty) return;
    final next = session
        .photos[(session.selected + 1).clamp(0, session.photos.length - 1)];
    unawaited(
      showMediaSortSheet(
        context,
        organizer!,
        currentPaths,
        addDestination: addDestination,
        nextSelected: next,
      ),
    );
  }

  void tagMedia() {
    if (organizer != null && currentPaths.isNotEmpty) {
      unawaited(showMediaTagsSheet(context, organizer!, currentPaths));
    }
  }

  Future<void> preferences() async {
    if (organizer == null) return;
    bool confirm;
    try {
      confirm = await organizer!.repository.loadConfirmDeletion();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Protected preferences are unavailable. Previous settings are retained.',
            ),
          ),
        );
      }
      return;
    }
    String? preferenceError;
    var savingPreference = false;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Organization preferences'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: const Text('Button labels'),
                  value: showButtonLabels,
                  onChanged: savingPreference
                      ? null
                      : (value) async {
                          update(() => savingPreference = true);
                          await organizer!.setButtonLabels(value);
                          if (context.mounted) {
                            update(() {
                              savingPreference = false;
                              preferenceError = organizer!.error;
                            });
                          }
                        },
                ),
                SwitchListTile(
                  title: const Text('Confirm permanent deletion'),
                  subtitle: const Text(
                    'Permanent deletion has no Undo. Organizer moves retain originals in Trash.',
                  ),
                  value: confirm,
                  onChanged: savingPreference
                      ? null
                      : (value) async {
                          update(() => savingPreference = true);
                          try {
                            await organizer!.repository.saveConfirmDeletion(
                              value,
                            );
                            if (context.mounted) {
                              update(() {
                                confirm = value;
                                preferenceError = null;
                              });
                            }
                          } catch (_) {
                            if (context.mounted) {
                              update(
                                () => preferenceError =
                                    'Could not save. Your previous deletion setting is retained.',
                              );
                            }
                          } finally {
                            if (context.mounted) {
                              update(() => savingPreference = false);
                            }
                          }
                        },
                ),
                if (preferenceError != null)
                  Text(
                    preferenceError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  void previousReviews() {
    showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Earlier file reviews'),
        content: SizedBox(
          width: 480,
          height: 360,
          child: ListView(
            children: [
              const Text(
                'These reviews belonged to an earlier file at the same path. They are retained as candidates and are not applied to the replacement.',
              ),
              for (final item in organizer!.state.previousReviews)
                ListTile(
                  title: Text(item['path'] as String),
                  subtitle: Text(() {
                    final note = PhotoReview.fromJson(
                      Map<String, dynamic>.from(item['review'] as Map),
                    );
                    return '${reviewLabel(note.state)} · ${note.rating} stars · ${note.tags.join(', ')}';
                  }()),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void filterMedia() {
    showDialog<void>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Filter media'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<ReviewState?>(
                isExpanded: true,
                value: stateFilter,
                items: [
                  const DropdownMenuItem<ReviewState?>(
                    value: null,
                    child: Text('All review states'),
                  ),
                  for (final value in ReviewState.values)
                    DropdownMenuItem(
                      value: value,
                      child: Text(reviewLabel(value)),
                    ),
                ],
                onChanged: (value) {
                  update(() => stateFilter = value);
                  organizerChanged();
                },
              ),
              DropdownButton<int>(
                isExpanded: true,
                value: minimumRating,
                items: [
                  for (var i = 0; i <= 5; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text(i == 0 ? 'Any rating' : '$i+ stars'),
                    ),
                ],
                onChanged: (value) {
                  update(() => minimumRating = value ?? 0);
                  organizerChanged();
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  Widget get moreMenu => PopupMenuButton<String>(
    tooltip: 'More organization tools',
    icon: const Icon(Icons.more_vert),
    itemBuilder: (_) => [
      const PopupMenuItem(
        value: 'filter',
        child: Text('Filter by state or rating'),
      ),
      if (organizer != null) ...[
        const PopupMenuItem(
          value: 'review',
          child: Text('Review states and details (R)'),
        ),
        const PopupMenuItem(value: 'rename', child: Text('Batch rename')),
        const PopupMenuItem(
          value: 'collections',
          child: Text('Collections and saved searches'),
        ),
        const PopupMenuItem(value: 'find', child: Text('Find renamed files')),
        if (organizer!.state.previousReviews.isNotEmpty)
          const PopupMenuItem(
            value: 'previous',
            child: Text('Earlier file reviews'),
          ),
        const PopupMenuItem(value: 'preferences', child: Text('Preferences')),
      ],
      const PopupMenuItem(
        value: 'unstage',
        child: Text('Unstage current file (Backspace)'),
      ),
    ],
    onSelected: (value) {
      if (value == 'filter') filterMedia();
      if (value == 'review') unawaited(editReview());
      if (value == 'unstage') clearDecision();
      if (value == 'preferences') unawaited(preferences());
      if (value == 'find') unawaited(organizer!.verifySavedReviews());
      if (value == 'previous') previousReviews();
      if (value == 'rename' && session.photos.isNotEmpty) {
        showDialog<void>(
          context: context,
          builder: (_) => BatchRenameDialog(
            controller: organizer!,
            paths: selectedPhotos.isEmpty
                ? List.of(session.photos)
                : selectedPhotos.toList(),
          ),
        );
      }
      if (value == 'collections') {
        showDialog<void>(
          context: context,
          builder: (_) => CollectionsDialog(
            controller: organizer!,
            paths: currentPaths,
            filter: CollectionFilter(
              query: query,
              reviewState: stateFilter?.name,
              minimumRating: minimumRating,
            ),
          ),
        );
      }
    },
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
    return MediaOrganizationShortcuts(
      enabled: organizer?.ready == true && !typing,
      onRating: (rating) async {
        await organizer!.setRating(currentPaths, rating);
      },
      onSort: sortMedia,
      onTags: tagMedia,
      child: PopScope(
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
                      MediaOrganizationShortcuts.digits[i],
                      alt: true,
                    ): () =>
                        stage(destinations[i]),
                },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              appBar: AppBar(
                title: Text(
                  widget.folderName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                actions: [
                  IconButton(
                    tooltip: viewing
                        ? 'Show thumbnail grid (Space)'
                        : 'Enlarge current photo (Space)',
                    icon: Icon(
                      viewing ? Icons.grid_view : Icons.photo_outlined,
                    ),
                    onPressed: () => setState(() => viewing = !viewing),
                  ),
                  IconButton(
                    tooltip: 'Search filename or tag',
                    icon: const Icon(Icons.search),
                    onPressed: () =>
                        setState(() => searchVisible = !searchVisible),
                  ),
                  if (organizer != null && organizer!.reviewWarnings.isNotEmpty)
                    IconButton(
                      tooltip: 'Review identity warnings',
                      icon: const Icon(Icons.warning_amber_outlined),
                      onPressed: () => showReviewWarnings(
                        context,
                        organizer!,
                        session.current,
                      ),
                    ),
                  IconButton(
                    tooltip: organizer == null
                        ? 'Preview queue'
                        : 'Operation queue & history',
                    onPressed: showQueue,
                    icon: Badge(
                      label: Text('${session.decisions.length}'),
                      child: const Icon(Icons.playlist_add_check),
                    ),
                  ),
                  moreMenu,
                ],
              ),
              body: Column(
                children: [
                  if (searchVisible)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
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
                  if (organizer?.error != null)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        organizer!.error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (organizer?.saving == true ||
                      organizer?.verifyingReviews == true)
                    const LinearProgressIndicator(),
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
                                    command ==
                                        MediaInputCommand.controlForward ||
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
                                  final note = organizer?.reviewFor(path);
                                  final details = [
                                    if ((note?.rating ?? 0) > 0)
                                      '${note!.rating}★',
                                    if (note != null &&
                                        note.state != ReviewState.unreviewed)
                                      reviewLabel(note.state),
                                    if (note?.tags.isNotEmpty == true)
                                      note!.tags.join(', '),
                                  ].join(' · ');
                                  return Semantics(
                                    selected: index == session.selected,
                                    label: path.split('/').last,
                                    value: details,
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
                                        imageTransform.value =
                                            Matrix4.identity();
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
                                            SizedBox(
                                              height: organizer == null
                                                  ? 24
                                                  : 44,
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Text(
                                                    path.split('/').last,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  if (organizer != null)
                                                    Text(
                                                      details,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: Theme.of(
                                                        context,
                                                      ).textTheme.bodySmall,
                                                    ),
                                                ],
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

                  if (viewing)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          tooltip: 'Previous photo',
                          icon: const Icon(Icons.chevron_left),
                          onPressed: () => navigate(-1),
                        ),
                        Text(
                          session.current == null
                              ? '0 / 0'
                              : '${session.selected + 1} / ${session.photos.length}',
                        ),
                        IconButton(
                          tooltip: 'Next photo',
                          icon: const Icon(Icons.chevron_right),
                          onPressed: () => navigate(1),
                        ),
                      ],
                    ),
                  if (organizer != null)
                    MediaOrganizationControls(
                      model: organizer!,
                      paths: currentPaths,
                      onSort: sortMedia,
                      onTags: tagMedia,
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          for (var i = 0; i < destinations.length; i++)
                            FilledButton.tonal(
                              onPressed: () => stage(destinations[i]),
                              child: Text('${i + 1} · ${destinations[i]}'),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
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
