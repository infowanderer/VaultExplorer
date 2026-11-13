import 'dart:async';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Shared by the gallery, image/slideshow viewer and video viewer. Text entry,
/// covered routes and system modifiers keep their own input semantics.
class MediaOrganizationShortcuts extends StatelessWidget {
  const MediaOrganizationShortcuts({
    super.key,
    required this.child,
    required this.onRating,
    required this.onSort,
    required this.onTags,
    this.onDestination,
    this.enabled = true,
  });
  final Widget child;
  final Future<void> Function(int) onRating;
  final VoidCallback onSort, onTags;
  final ValueChanged<int>? onDestination;
  final bool enabled;
  static const digits = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];
  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onKeyEvent: (_, event) {
      if (!enabled ||
          event is! KeyDownEvent ||
          ModalRoute.of(context)?.isCurrent == false) {
        return KeyEventResult.ignored;
      }
      final focus = FocusManager.instance.primaryFocus?.context;
      if (focus?.widget is EditableText ||
          focus?.findAncestorWidgetOfExactType<EditableText>() != null) {
        return KeyEventResult.ignored;
      }
      final keys = HardwareKeyboard.instance;
      if (keys.isControlPressed || keys.isMetaPressed || keys.isShiftPressed) {
        return KeyEventResult.ignored;
      }
      final digit = digits.indexOf(event.logicalKey);
      if (keys.isAltPressed) {
        if (digit >= 0 && onDestination != null) {
          onDestination!(digit);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }
      if (digit >= 0 && digit < 5) {
        unawaited(onRating(digit + 1));
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyS) {
        onSort();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyT) {
        onTags();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: child,
  );
}
