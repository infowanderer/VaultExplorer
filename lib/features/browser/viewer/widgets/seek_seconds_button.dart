import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Exact entry complements the slider on tablet/touch and keyboard layouts.
class SeekSecondsButton extends StatelessWidget {
  const SeekSecondsButton({
    super.key,
    required this.seconds,
    required this.label,
    required this.onChanged,
  });
  final int seconds;
  final String label;
  final Future<void> Function(int seconds) onChanged;

  @override
  Widget build(BuildContext context) => TextButton(
    child: Text('${seconds}s'),
    onPressed: () async {
      final form = GlobalKey<FormState>();
      var text = '$seconds';
      final value = await showDialog<int>(
        context: context,
        builder: (dialogContext) {
          void submit() {
            if (form.currentState!.validate())
              Navigator.pop(dialogContext, int.parse(text));
          }

          return AlertDialog(
            title: Text(label),
            content: Form(
              key: form,
              child: TextFormField(
                autofocus: true,
                initialValue: text,
                decoration: const InputDecoration(labelText: 'Seconds (1–600)'),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                onChanged: (value) => text = value,
                onFieldSubmitted: (_) => submit(),
                validator: (value) {
                  final parsed = int.tryParse(value ?? '');
                  return parsed == null || parsed < 1 || parsed > 600
                      ? 'Enter 1–600 seconds'
                      : null;
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              TextButton(onPressed: submit, child: const Text('Save')),
            ],
          );
        },
      );
      if (value != null && context.mounted) await onChanged(value);
    },
  );
}
