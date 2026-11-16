import 'dart:async';
import 'dart:math';
import 'package:material_ui/material_ui.dart';
import 'organizer.dart';

/// Exact-content observations stay in memory and never authorize deletion.
class DuplicatesDialog extends StatefulWidget {
  const DuplicatesDialog({
    super.key,
    required this.controller,
    required this.paths,
  });
  final OrganizerController controller;
  final List<String> paths;
  @override
  State<DuplicatesDialog> createState() => _DuplicatesDialogState();
}

class _DuplicatesDialogState extends State<DuplicatesDialog>
    with WidgetsBindingObserver {
  final id =
      'dupes-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
  Timer? timer;
  bool busy = true, polling = false, stopped = false;
  String? error;
  List<int>? progress;
  List<({int size, List<String> paths})> groups = [];
  int examined = 0, hashed = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(scan());
  }

  Future<void> scan() async {
    try {
      if (widget.paths.isEmpty ||
          widget.paths.length > 500 ||
          widget.paths.toSet().length != widget.paths.length) {
        throw StateError('Choose 1–500 distinct files');
      }
      timer = Timer.periodic(const Duration(milliseconds: 350), (_) async {
        if (polling || !busy || !mounted) return;
        polling = true;
        try {
          final value = await widget.controller.bridge.progress(id);
          if (mounted &&
              busy &&
              value?.length == 2 &&
              value![0] >= 0 &&
              value[1] >= value[0]) {
            setState(() => progress = value);
          }
        } catch (_) {
          /* Progress is advisory; the final scan result is authoritative. */
        } finally {
          polling = false;
        }
      });
      final result = await widget.controller.bridge.exactDuplicates(
        id,
        widget.controller.root,
        List.of(widget.paths),
      );
      final found = <({int size, List<String> paths})>[];
      final seen = <String>{};
      for (final item in result['groups'] as List) {
        final group = Map<String, dynamic>.from(item as Map);
        final paths = List<String>.from(group['paths'] as List);
        if (group['size'] is! int ||
            (group['size'] as int) < 0 ||
            group['sha256'] is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(group['sha256'] as String) ||
            paths.length < 2 ||
            paths.any(
              (path) => !widget.paths.contains(path) || !seen.add(path),
            )) {
          throw const FormatException('Invalid duplicate report');
        }
        found.add((size: group['size'] as int, paths: paths));
      }
      if (result['examined'] != widget.paths.length ||
          result['hashed'] is! int ||
          (result['hashed'] as int) < seen.length ||
          (result['hashed'] as int) > widget.paths.length) {
        throw const FormatException('Incomplete duplicate report');
      }
      if (!mounted || stopped) return;
      setState(() {
        groups = found;
        examined = result['examined'] as int;
        hashed = result['hashed'] as int;
      });
    } catch (_) {
      if (mounted && !stopped) {
        setState(
          () => error =
              'Scan stopped. Select up to 500 accessible files and retry after checking storage. No files were changed.',
        );
      }
    } finally {
      timer?.cancel();
      if (mounted) setState(() => busy = false);
    }
  }

  void stop() {
    stopped = true;
    timer?.cancel();
    unawaited(
      widget.controller.bridge.cancel(id).catchError((Object _) {
        /* Session invalidation also cancels native work; no results are accepted after stop. */
      }),
    );
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) stop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    if (busy) {
      unawaited(
        widget.controller.bridge.cancel(id).catchError((Object _) {
          /* A completed/expired scan has no remaining native token to cancel. */
        }),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Exact duplicate review'),
    content: SizedBox(
      width: 600,
      height: MediaQuery.sizeOf(context).height * .6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Matching bytes when checked. Results are read-only; files may change afterward. No files are deleted or moved.',
          ),
          const SizedBox(height: 12),
          if (busy && !stopped) ...[
            const LinearProgressIndicator(),
            Text(
              progress == null
                  ? 'Checking file sizes…'
                  : '${progress![0]} / ${progress![1]} candidate files hashed',
            ),
          ],
          if (stopped) const Text('Scan cancelled. Reopen to scan again.'),
          if (error != null) Text(error!),
          if (!busy && !stopped && error == null)
            Text(
              '$examined files examined · $hashed hashed · ${groups.length} duplicate groups',
            ),
          Expanded(
            child: ListView(
              children: [
                if (!busy && !stopped && error == null && groups.isEmpty)
                  const ListTile(title: Text('No exact duplicates found')),
                if (!stopped)
                  for (var i = 0; i < groups.length; i++) ...[
                    ListTile(
                      leading: const Icon(Icons.content_copy),
                      title: Text(
                        'Group ${i + 1} · ${groups[i].paths.length} files',
                      ),
                      subtitle: Text(
                        '${groups[i].size} bytes each · copies may share the same physical storage',
                      ),
                    ),
                    for (final path in groups[i].paths)
                      ListTile(title: Text(path)),
                    const Divider(),
                  ],
              ],
            ),
          ),
        ],
      ),
    ),
    actions: [
      if (busy && !stopped)
        TextButton(onPressed: stop, child: const Text('Cancel scan')),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}
