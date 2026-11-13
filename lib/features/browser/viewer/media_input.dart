import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum MediaInputCommand {
  backward,
  forward,
  controlBackward,
  controlForward,
  controlWheelUp,
  controlWheelDown,
}

/// Route-local commands. No global keyboard hooks, disk writes or scripts.
class MediaInputScope extends StatefulWidget {
  const MediaInputScope({
    super.key,
    required this.onCommand,
    required this.child,
    this.onExit,
  });
  final bool Function(MediaInputCommand command) onCommand;
  final Widget child;
  final bool Function()? onExit;

  /// InteractiveViewer scales wheel input immediately, before signal resolution.
  /// An infinite divisor makes mouse-wheel scale exactly 1, preserving touch
  /// pinch zoom and explicit PointerScaleEvent support. Other routes keep the
  /// framework default. The canvas listener separately claims scrollables.
  static double wheelScaleFactor(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_MediaInputBinding>() == null
      ? kDefaultMouseScrollToScaleFactor
      : double.infinity;

  @override
  State<MediaInputScope> createState() => _MediaInputScopeState();
}

class _MediaInputScopeState extends State<MediaInputScope> {
  final _focus = FocusNode(debugLabel: 'Media canvas');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ModalRoute.of(context)?.isCurrent != false)
        _focus.requestFocus();
    });
  }

  bool dispatch(MediaInputCommand command) {
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    return widget.onCommand(command);
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _MediaInputBinding(
    state: this,
    child: Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (node, event) {
        // Escape belongs to the media route even when a toolbar button has
        // focus. Dialogs occupy their own route and retain Escape dismissal.
        if (event.logicalKey == LogicalKeyboardKey.escape &&
            !HardwareKeyboard.instance.isControlPressed &&
            !HardwareKeyboard.instance.isAltPressed &&
            !HardwareKeyboard.instance.isMetaPressed &&
            !HardwareKeyboard.instance.isShiftPressed &&
            widget.onExit != null &&
            ModalRoute.of(context)?.isCurrent != false) {
          if (event is KeyRepeatEvent || event is KeyUpEvent) {
            return KeyEventResult.handled;
          }
          return widget.onExit!()
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        }
        // Let focused fields, sliders, buttons and dialogs keep their keys.
        if (!node.hasPrimaryFocus || event is KeyUpEvent) {
          return KeyEventResult.ignored;
        }
        final keyboard = HardwareKeyboard.instance;
        if (keyboard.isAltPressed ||
            keyboard.isMetaPressed ||
            keyboard.isShiftPressed) {
          return KeyEventResult.ignored;
        }
        final forward = event.logicalKey == LogicalKeyboardKey.arrowRight;
        if (!forward && event.logicalKey != LogicalKeyboardKey.arrowLeft) {
          return KeyEventResult.ignored;
        }
        final command = keyboard.isControlPressed
            ? (forward
                  ? MediaInputCommand.controlForward
                  : MediaInputCommand.controlBackward)
            : (forward
                  ? MediaInputCommand.forward
                  : MediaInputCommand.backward);
        return dispatch(command)
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      },
      child: widget.child,
    ),
  );
}

class _MediaInputBinding extends InheritedWidget {
  const _MediaInputBinding({required this.state, required super.child});
  final _MediaInputScopeState state;
  @override
  bool updateShouldNotify(_MediaInputBinding oldWidget) =>
      state != oldWidget.state;
}

/// Place inside InteractiveViewer and pair with [MediaInputScope.wheelScaleFactor].
/// The resolver prevents an enclosing playlist Scrollable from also scrolling.
class MediaPointerRegion extends StatelessWidget {
  const MediaPointerRegion({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_MediaInputBinding>()
        ?.state;
    if (scope == null) return child;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => scope._focus.requestFocus(),
      onPointerSignal: (event) {
        if (event is! PointerScrollEvent ||
            event.kind != PointerDeviceKind.mouse ||
            event.scrollDelta.dy == 0)
          return;
        final keyboard = HardwareKeyboard.instance;
        if (keyboard.isAltPressed ||
            keyboard.isMetaPressed ||
            keyboard.isShiftPressed) {
          return;
        }
        final forward = event.scrollDelta.dy > 0;
        final command = keyboard.isControlPressed
            // Ctrl+wheel up zooms in; ordinary wheel down advances.
            ? (forward
                  ? MediaInputCommand.controlWheelDown
                  : MediaInputCommand.controlWheelUp)
            : (forward
                  ? MediaInputCommand.forward
                  : MediaInputCommand.backward);
        GestureBinding.instance.pointerSignalResolver.register(event, (_) {
          scope.dispatch(command);
        });
      },
      child: child,
    );
  }
}

class MediaZoomController extends ChangeNotifier {
  int direction = 1;
  void step(int value) {
    direction = value;
    notifyListeners();
  }
}

/// Scale around the visible center, preserving any existing pan offset.
Matrix4 steppedMediaZoom(
  Matrix4 current,
  Size viewport,
  int direction, {
  double minScale = 1,
  double maxScale = 8,
}) {
  final scale = current.getMaxScaleOnAxis();
  final target = (scale * (direction > 0 ? 1.2 : 1 / 1.2)).clamp(
    minScale,
    maxScale,
  );
  final ratio = target / scale;
  return Matrix4.identity()
    ..translateByDouble(viewport.width / 2, viewport.height / 2, 0, 1)
    ..scaleByDouble(ratio, ratio, 1, 1)
    ..translateByDouble(-viewport.width / 2, -viewport.height / 2, 0, 1)
    ..multiply(current);
}
