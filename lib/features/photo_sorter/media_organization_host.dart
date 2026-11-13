import 'dart:async';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:path/path.dart' as p;
import 'package:material_ui/material_ui.dart';
import 'organizer.dart';
import 'organizer_widgets.dart';
import 'media_organization_controls.dart';
import 'media_organization_shortcuts.dart';

typedef OrganizationBuilder =
    Widget Function(
      BuildContext context,
      OrganizerController model,
      Widget controls,
    );

String? organizationPath(String root, String file) {
  if (root.startsWith('content://')) {
    if (Uri.tryParse(root)?.authority !=
        'com.android.externalstorage.documents') {
      return null;
    }
    final path = file.replaceFirst(RegExp(r'^/+'), '');
    return path.isEmpty ||
            path.split('/').any((part) => part == '..' || part == '.')
        ? null
        : path;
  }
  if (!p.posix.isAbsolute(root)) return null;
  final normalized = p.posix.normalize(file);
  if (p.posix.isAbsolute(normalized)) {
    if (!p.posix.isWithin(p.posix.normalize(root), normalized)) return null;
    return p.posix.relative(normalized, from: p.posix.normalize(root));
  }
  return normalized.isEmpty ||
          normalized == '.' ||
          normalized.split('/').contains('..')
      ? null
      : normalized;
}

String organizationFolder(String path) =>
    p.posix.dirname(path) == '.' ? '' : p.posix.dirname(path);

/// Shares one review/sort session between gallery and viewer chrome. The host
/// supplies the current selection; changing tracks cannot retarget an old edit.
class MediaOrganizationHost extends StatefulWidget {
  const MediaOrganizationHost({
    super.key,
    required this.root,
    required this.folder,
    required this.files,
    required this.selected,
    required this.bridge,
    required this.builder,
    this.repository,
    this.pickDestination,
    this.enabled = true,
    this.overlay = false,
  });
  final String root, folder;
  final List<String> files, selected;
  final OrganizerBridge bridge;
  final OrganizerRepository? repository;
  final OrganizationBuilder builder;
  final Future<OrganizerFolder?> Function(OrganizerBridge)? pickDestination;
  final bool enabled, overlay;
  @override
  State<MediaOrganizationHost> createState() => _MediaOrganizationHostState();
}

class _MediaOrganizationHostState extends State<MediaOrganizationHost>
    with WidgetsBindingObserver {
  late OrganizerController model;
  final galleryFocus = FocusNode(debugLabel: 'Gallery organization commands');
  bool paused = false;
  bool routeWasCurrent = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    create();
  }

  void create() {
    model = OrganizerController(
      root: widget.root,
      folder: widget.folder,
      photos: widget.files,
      bridge: widget.bridge,
      repository: widget.repository,
    )..addListener(changed);
    if (widget.selected.isNotEmpty) open();
  }

  void open() {
    final current = model;
    unawaited(
      current.open(verifyContent: false).then((_) {
        if (mounted && identical(current, model)) {
          if (widget.selected.length == 1)
            current.select(widget.selected.single);
          requestGalleryFocus();
        }
      }),
    );
  }

  void changed() {
    if (mounted) setState(() {});
  }

  void requestGalleryFocus() {
    if (!widget.enabled ||
        widget.overlay ||
        paused ||
        widget.selected.isEmpty ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus?.widget is EditableText ||
        focus?.findAncestorWidgetOfExactType<EditableText>() != null) {
      return;
    }
    galleryFocus.requestFocus();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    if (current && !routeWasCurrent) {
      // A viewer may have edited this gallery's protected folder session.
      // Reload on return instead of displaying or overwriting stale reviews.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            !paused &&
            !model.running &&
            !model.saving &&
            widget.selected.isNotEmpty) {
          open();
        }
      });
    }
    routeWasCurrent = current;
  }

  @override
  void didUpdateWidget(MediaOrganizationHost old) {
    super.didUpdateWidget(old);
    if (old.root != widget.root ||
        old.folder != widget.folder ||
        !listEquals(old.files, widget.files)) {
      model.removeListener(changed);
      model.dispose();
      create();
    } else if (old.selected.isEmpty &&
        widget.selected.isNotEmpty &&
        !model.ready) {
      open();
    } else if (widget.selected.length == 1) {
      unawaited(model.select(widget.selected.single));
    }
    if (!old.enabled && widget.enabled) requestGalleryFocus();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      paused = true;
      model.pause();
    } else if (paused) {
      paused = false;
      if (widget.selected.isNotEmpty) open();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    model.removeListener(changed);
    model.dispose();
    galleryFocus.dispose();
    super.dispose();
  }

  Future<void> addDestination() async {
    final picked = await widget.pickDestination?.call(widget.bridge);
    if (picked != null && mounted) await model.addDestination(picked);
  }

  void sort() {
    if (widget.selected.isNotEmpty) {
      unawaited(
        showMediaSortSheet(
          context,
          model,
          List.of(widget.selected),
          addDestination: addDestination,
        ),
      );
    }
  }

  void tags() {
    if (widget.selected.isNotEmpty) {
      unawaited(showMediaTagsSheet(context, model, List.of(widget.selected)));
    }
  }

  void queue() {
    showDialog<void>(
      context: context,
      builder: (_) => OrganizerQueueDialog(controller: model),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active =
        widget.enabled && model.ready && widget.selected.isNotEmpty && !paused;
    final controls = MediaOrganizationControls(
      model: model,
      paths: widget.selected,
      onSort: sort,
      onTags: tags,
      onQueue: queue,
      overlay: widget.overlay,
      enabled: active,
    );
    return MediaOrganizationShortcuts(
      enabled: active,
      onRating: (rating) async {
        await model.setRating(List.of(widget.selected), rating);
      },
      onSort: sort,
      onTags: tags,
      onDestination: (index) {
        if (index < model.state.destinations.length) {
          unawaited(
            model.stage(
              List.of(widget.selected),
              model.state.destinations[index],
              move: false,
            ),
          );
        }
      },
      child: Focus(
        focusNode: galleryFocus,
        child: widget.builder(context, model, controls),
      ),
    );
  }
}
