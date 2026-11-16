import 'dart:async';
import 'dart:typed_data';
import 'package:material_ui/material_ui.dart';
import 'contact_sheet_plan.dart';

/// Sequential, memory-only frame previews. No exports, cache files or FFmpeg
/// subprocesses. The host pauses playback and supplies a route-bound seek.
class ContactSheetDialog extends StatefulWidget {
  const ContactSheetDialog({
    super.key,
    required this.durationUs,
    required this.loadFrame,
    required this.seek,
  });
  final int durationUs;
  final Future<Uint8List?> Function(int timeUs) loadFrame;
  final Future<void> Function(int timeUs) seek;
  @override
  State<ContactSheetDialog> createState() => _ContactSheetDialogState();
}

class _ContactSheetDialogState extends State<ContactSheetDialog>
    with WidgetsBindingObserver {
  List<int> times = [];
  List<Uint8List?> frames = [];
  var count = 12, generation = 0, completed = 0;
  bool loading = true, stopped = false, seeking = false;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(load());
  }

  void clearFrames() {
    for (final bytes in frames.whereType<Uint8List>()) {
      unawaited(
        MemoryImage(bytes).evict().catchError((Object _) {
          // A failed/unused image may already have left the in-memory cache.
          return false;
        }),
      );
      bytes.fillRange(0, bytes.length, 0);
    }
    frames = [];
  }

  Future<void> load() async {
    final request = ++generation;
    clearFrames();
    error = null;
    stopped = false;
    loading = true;
    completed = 0;
    try {
      times = contactSheetTimes(widget.durationUs, count: count);
      frames = List.filled(times.length, null);
      for (var i = 0; i < times.length; i++) {
        if (!mounted || stopped || request != generation) return;
        Uint8List? bytes;
        try {
          bytes = await widget.loadFrame(times[i]);
        } catch (_) {
          /* An unsupported frame stays visibly unavailable. */
        }
        if (!mounted || stopped || request != generation) {
          bytes?.fillRange(0, bytes.length, 0);
          return;
        }
        setState(() {
          frames[i] = bytes;
          completed++;
        });
      }
    } catch (_) {
      if (mounted && request == generation)
        error = 'A valid video duration is needed to create previews.';
    } finally {
      if (mounted && request == generation) setState(() => loading = false);
    }
  }

  void stop() {
    generation++;
    stopped = true;
    loading = false;
    clearFrames();
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) stop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    generation++;
    clearFrames();
    super.dispose();
  }

  Future<void> choose(int timeUs) async {
    if (seeking || stopped) return;
    setState(() => seeking = true);
    try {
      await widget.seek(timeUs);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted)
        setState(() {
          seeking = false;
          error = 'Could not seek. The video may have changed.';
        });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Video contact sheet'),
    content: SizedBox(
      width: 900,
      height: MediaQuery.sizeOf(context).height * .68,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tap a frame to seek. Previews may use nearby keyframes. Playback stays paused; frames are held in memory only.',
          ),
          Row(
            children: [
              const Text('Frames: '),
              DropdownButton<int>(
                value: count,
                items: [
                  for (final n in [6, 12, 24])
                    DropdownMenuItem(value: n, child: Text('$n')),
                ],
                onChanged: loading || seeking || stopped
                    ? null
                    : (value) {
                        setState(() => count = value!);
                        unawaited(load());
                      },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  stopped
                      ? 'Preview closed'
                      : '$completed / ${times.length} previews',
                ),
              ),
            ],
          ),
          if (loading) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          Expanded(
            child: stopped
                ? const Center(
                    child: Text(
                      'Reopen contact sheet to generate previews again.',
                    ),
                  )
                : LayoutBuilder(
                    builder: (_, constraints) => GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: (constraints.maxWidth / 220)
                            .floor()
                            .clamp(1, 4),
                        mainAxisExtent: 165,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: times.length,
                      itemBuilder: (_, i) => Semantics(
                        button: true,
                        label: 'Seek near ${contactSheetTimeLabel(times[i])}',
                        child: InkWell(
                          onTap: seeking ? null : () => choose(times[i]),
                          child: Column(
                            children: [
                              Expanded(
                                child: Center(
                                  child: i >= completed
                                      ? const CircularProgressIndicator()
                                      : frames[i] == null
                                      ? const Text('Frame unavailable')
                                      : Image.memory(
                                          frames[i]!,
                                          cacheWidth: 320,
                                          fit: BoxFit.contain,
                                          errorBuilder: (_, _, _) =>
                                              const Text('Frame unavailable'),
                                        ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(contactSheetTimeLabel(times[i])),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    ),
    actions: [
      if (loading)
        TextButton(onPressed: stop, child: const Text('Stop previews')),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}
