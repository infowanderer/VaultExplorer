import 'dart:async';

/// Serialize native seeks and accumulate rapid keys/wheel ticks even when the
/// player's position events have not caught up. Never carry work across media.
class MediaSeekStepper {
  Object? _owner;
  Duration? _target;
  DateTime? _lastInput;
  bool _running = false;
  int _generation = 0;

  void reset() {
    _generation++;
    _owner = null;
    _target = null;
    _lastInput = null;
    _running = false;
  }

  void step({
    required Object owner,
    required Duration position,
    required Duration duration,
    required Duration delta,
    required Future<void> Function(Duration target) seek,
    required void Function() onError,
  }) {
    if (duration <= Duration.zero) return;
    if (!identical(owner, _owner)) {
      reset();
      _owner = owner;
    }
    final now = DateTime.now();
    final recent =
        _lastInput != null &&
        now.difference(_lastInput!) < const Duration(milliseconds: 500);
    final base = (_running || recent) ? (_target ?? position) : position;
    _target = Duration(
      microseconds: (base + delta).inMicroseconds.clamp(
        0,
        duration.inMicroseconds,
      ),
    );
    _lastInput = now;
    if (!_running) unawaited(_drain(_generation, seek, onError));
  }

  Future<void> _drain(
    int generation,
    Future<void> Function(Duration) seek,
    void Function() onError,
  ) async {
    _running = true;
    try {
      while (generation == _generation) {
        final target = _target!;
        await seek(target);
        if (generation != _generation || target == _target) break;
      }
    } catch (_) {
      if (generation == _generation) {
        _target = null;
        _lastInput = null;
        onError();
      }
    } finally {
      if (generation == _generation) _running = false;
    }
  }
}
