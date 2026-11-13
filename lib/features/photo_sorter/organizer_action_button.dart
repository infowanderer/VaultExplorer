import 'package:material_ui/material_ui.dart';

/// Keep help available in both display modes, including on disabled actions.
class OrganizerActionButton extends StatelessWidget {
  const OrganizerActionButton({
    super.key,
    required this.label,
    required this.tooltip,
    required this.icon,
    required this.showLabel,
    required this.onPressed,
  });
  final String label, tooltip;
  final Widget icon;
  final bool showLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    triggerMode: TooltipTriggerMode.longPress,
    waitDuration: const Duration(milliseconds: 400),
    showDuration: const Duration(seconds: 4),
    child: showLabel
        ? TextButton.icon(
            onPressed: onPressed,
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            icon: icon,
            label: Text(label),
          )
        : IconButton(
            onPressed: onPressed,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: icon,
          ),
  );
}
