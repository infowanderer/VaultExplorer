import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'organizer.dart';

String reviewLabel(ReviewState value) => switch (value) {
  ReviewState.unreviewed => 'Unreviewed',
  ReviewState.keep => 'Keep',
  ReviewState.sortLater => 'Sort later',
  ReviewState.deleteCandidate => 'Delete candidate',
};

class OrganizerQueueDialog extends StatelessWidget {
  const OrganizerQueueDialog({super.key, required this.controller});
  final OrganizerController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final ready =
          controller.state.decisions.isNotEmpty &&
          controller.state.decisions.values.every((d) => d['jobId'] != null);
      return AlertDialog(
        title: const Text('Operation preview & history'),
        content: SizedBox(
          width: 700,
          height: MediaQuery.sizeOf(context).height * .58,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Copies are read back and SHA-256 verified. Moves retain originals in source-side .MediaOrganizerTrash; undo retains sorted copies in Trash. Nothing is permanently deleted. Destination photos inherit the selected storage’s protection.',
              ),
              if (controller.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    controller.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (controller.running) ...[
                const LinearProgressIndicator(),
                Text(
                  controller.progress == null
                      ? 'Checking storage…'
                      : '${controller.progress![0]} / ${controller.progress![1]} bytes',
                ),
              ],
              Expanded(
                child: ListView(
                  children: [
                    for (final entry in controller.state.decisions.entries)
                      ListTile(
                        leading: Icon(
                          entry.value['move'] == true
                              ? Icons.drive_file_move_outline
                              : Icons.copy,
                        ),
                        title: Text(entry.key.split('/').last),
                        subtitle: Text(
                          '${entry.value['move'] == true ? 'Move' : 'Copy'} → ${(entry.value['folder'] as Map)['name']}\n${(entry.value['folder'] as Map)['root']}/${(entry.value['folder'] as Map)['path']}/${entry.value['name']}\n${entry.value['jobId'] == null ? 'Not checked yet' : 'Prepared — rechecked at commit'}',
                        ),
                        trailing: PopupMenuButton<String>(
                          tooltip: 'Staged file actions',
                          enabled: !controller.running && !controller.saving,
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'rename',
                              child: Text('Rename output…'),
                            ),
                            PopupMenuItem(
                              value: 'remove',
                              child: Text('Unstage'),
                            ),
                          ],
                          onSelected: (action) async {
                            if (action == 'remove') {
                              await controller.clearDecision(entry.key);
                              return;
                            }
                            var name = entry.value['name'] as String;
                            final updated = await showDialog<String>(
                              context: context,
                              builder: (dialog) => AlertDialog(
                                title: const Text('Output filename'),
                                content: TextFormField(
                                  initialValue: name,
                                  autofocus: true,
                                  onChanged: (value) => name = value,
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(dialog),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(dialog, name),
                                    child: const Text('Save'),
                                  ),
                                ],
                              ),
                            );
                            if (updated != null) {
                              await controller.renameDecision(
                                entry.key,
                                updated,
                              );
                            }
                          },
                        ),
                      ),
                    const Divider(),
                    const Text('Durable history / recovery'),
                    for (final job in controller.jobs)
                      _JobTile(controller: controller, job: job),
                    if (controller.jobs.isEmpty)
                      const Text('No file operations have been prepared yet.'),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (controller.running)
            TextButton(
              onPressed: controller.pause,
              child: const Text('Pause safely'),
            ),
          if (!controller.running && !ready)
            FilledButton.tonal(
              onPressed: controller.state.decisions.isEmpty
                  ? null
                  : () => controller.prepare(),
              child: const Text('Check & preview'),
            ),
          if (!controller.running && ready)
            FilledButton(
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialog) => AlertDialog(
                    title: const Text('Commit these operations?'),
                    content: Text(
                      '${controller.state.decisions.length} staged files will be copied or moved to the destinations shown. Moves retain originals in recoverable Trash. Existing names are refused. Partial copies are retained for recovery.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialog, false),
                        child: const Text('Back'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialog, true),
                        child: const Text('Commit'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) await controller.commit();
              },
              child: const Text('Commit…'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

class _JobTile extends StatelessWidget {
  const _JobTile({required this.controller, required this.job});
  final OrganizerController controller;
  final Map<String, dynamic> job;
  @override
  Widget build(BuildContext context) {
    final source = job['source'] as Map;
    final target =
        (['undoing', 'undone'].contains(job['state'])
                ? job['destination']
                : (job['created'] ?? job['destination']))
            as Map;
    final canResume = [
      'planned',
      'interrupted',
      'copying',
      'verifying',
      'copied',
      'quarantining',
    ].contains(job['state']);
    return ListTile(
      title: Text(
        '${job['move'] == true ? 'Move' : 'Copy'} ${source['path']} · ${job['state']}',
      ),
      subtitle: Text(
        '${target['root']}/${target['path']}\n${job['message'] ?? (job['state'] == 'complete' ? 'Read-back verified' : 'Originals / partial outputs retained')}${job['trash'] == null ? '' : '\nRetained original: ${(job['trash'] as Map)['root']}/${(job['trash'] as Map)['path']}'}',
      ),
      trailing: controller.running || controller.saving
          ? null
          : canResume
          ? TextButton(
              onPressed: () async {
                final confirmed = await _confirm(
                  context,
                  'Resume this operation?',
                  'The source, recorded output identity and content will be checked again. Partial outputs are never overwritten if they were modified.',
                );
                if (confirmed) await controller.runJobs([job['id'] as String]);
              },
              child: const Text('Resume…'),
            )
          : ['needsReview', 'creating', 'undoing'].contains(job['state'])
          ? TextButton(
              onPressed: () => controller.reconcile(job['id'] as String),
              child: const Text('Verify recovery'),
            )
          : job['state'] == 'complete' && job['undoSupported'] == true
          ? TextButton(
              onPressed: () async {
                final confirmed = await _confirm(
                  context,
                  'Undo this transfer?',
                  'An occupied original name or changed output will refuse undo. The sorted copy is retained in destination-side Trash. Nothing is permanently deleted.',
                );
                if (confirmed) await controller.undo(job['id'] as String);
              },
              child: const Text('Undo…'),
            )
          : null,
    );
  }

  Future<bool> _confirm(
    BuildContext context,
    String title,
    String message,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      ) ==
      true;
}

class PhotoReviewDialog extends StatefulWidget {
  const PhotoReviewDialog({
    super.key,
    required this.controller,
    required this.paths,
  });
  final OrganizerController controller;
  final List<String> paths;
  @override
  State<PhotoReviewDialog> createState() => _PhotoReviewDialogState();
}

class _PhotoReviewDialogState extends State<PhotoReviewDialog> {
  late final initial =
      widget.controller.state.reviews[widget.paths.first] ??
      const PhotoReview();
  late ReviewState review = initial.state;
  late int rating = initial.rating;
  late final tags = TextEditingController(text: initial.tags.join(', '));
  bool saving = false;
  String? error;
  @override
  void dispose() {
    tags.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final suggestions =
        widget.controller.state.reviews.values
            .expand((r) => r.tags)
            .toSet()
            .toList()
          ..sort();
    return AlertDialog(
      title: Text(
        widget.paths.length == 1
            ? 'Review photograph'
            : 'Review ${widget.paths.length} photographs',
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.controller.reviewWarnings.containsKey(
                widget.paths.first,
              ))
                Text(
                  '${widget.controller.reviewWarnings[widget.paths.first]} Saving explicitly reapplies these values to the current file.',
                ),
              Wrap(
                spacing: 8,
                children: [
                  for (final state in ReviewState.values)
                    ChoiceChip(
                      label: Text(reviewLabel(state)),
                      selected: review == state,
                      onSelected: saving
                          ? null
                          : (_) => setState(() => review = state),
                    ),
                ],
              ),
              Wrap(
                children: [
                  TextButton(
                    onPressed: saving ? null : () => setState(() => rating = 0),
                    child: const Text('Unrated'),
                  ),
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      tooltip: '$i stars',
                      onPressed: saving
                          ? null
                          : () => setState(() => rating = i),
                      icon: Icon(rating >= i ? Icons.star : Icons.star_border),
                    ),
                ],
              ),
              TextField(
                controller: tags,
                enabled: !saving,
                maxLength: 800,
                decoration: const InputDecoration(
                  labelText: 'Tags, separated by commas',
                  helperText: 'Up to 20 tags; 40 characters each.',
                ),
              ),
              if (suggestions.isNotEmpty)
                Wrap(
                  spacing: 6,
                  children: [
                    for (final tag in suggestions.take(20))
                      ActionChip(
                        label: Text(tag),
                        onPressed: saving
                            ? null
                            : () {
                                final values =
                                    tags.text
                                        .split(',')
                                        .map((s) => s.trim())
                                        .where((s) => s.isNotEmpty)
                                        .toSet()
                                      ..add(tag);
                                tags.text = values.join(', ');
                              },
                      ),
                  ],
                ),
              if (widget.paths.length > 1)
                const Text(
                  'These values replace the review, rating and tags on every selected photograph.',
                ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
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
          onPressed: saving
              ? null
              : () async {
                  final values = tags.text
                      .split(',')
                      .map((s) => s.trim())
                      .where((s) => s.isNotEmpty)
                      .toSet()
                      .toList();
                  if (values.length > 20 ||
                      values.any(
                        (s) => s.length > 40 || s.codeUnits.any((c) => c < 32),
                      )) {
                    setState(
                      () =>
                          error = 'Use at most 20 tags of 40 characters each.',
                    );
                    return;
                  }
                  setState(() => saving = true);
                  final saved = await widget.controller.review(
                    widget.paths,
                    PhotoReview(state: review, rating: rating, tags: values),
                  );
                  if (!context.mounted) return;
                  if (saved) {
                    Navigator.pop(context);
                  } else {
                    setState(() {
                      saving = false;
                      error =
                          widget.controller.error ??
                          'Another operation is busy; wait and retry.';
                    });
                  }
                },
          child: Text(saving ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}

Future<void> showReviewWarnings(
  BuildContext context,
  OrganizerController controller,
  String? current,
) => showDialog<void>(
  context: context,
  builder: (dialog) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => AlertDialog(
      title: const Text('Review identity checks'),
      content: SizedBox(
        width: 600,
        height: 400,
        child: ListView(
          children: [
            const Text(
              'Unique identity and full-content matches can restore reviews after a rename. Other candidates need your decision; saved metadata is retained.',
            ),
            for (final entry in controller.reviewWarnings.entries)
              ListTile(
                title: Text(entry.key),
                subtitle: Text(
                  '${entry.value}\n${controller.state.reviews[entry.key]?.tags.join(', ') ?? ''}',
                ),
                trailing:
                    current == null || controller.running || controller.saving
                    ? null
                    : TextButton(
                        onPressed: () async {
                          final candidate = controller.state.reviews[entry.key];
                          if (candidate == null) return;
                          final okay = await showDialog<bool>(
                            context: context,
                            builder: (confirm) => AlertDialog(
                              title: const Text('Reapply saved review?'),
                              content: Text(
                                'Apply the saved rating, tags and review from ${entry.key} to $current? Its current content and identity will be verified and bound to this review. A different old path keeps its candidate metadata.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(confirm, false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(confirm, true),
                                  child: const Text('Reapply'),
                                ),
                              ],
                            ),
                          );
                          if (okay == true) {
                            await controller.review([current], candidate);
                          }
                        },
                        child: const Text('Use for current…'),
                      ),
              ),
            if (controller.error != null) Text(controller.error!),
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
  ),
);
