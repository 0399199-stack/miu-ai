import 'dart:async';
import 'dart:math';

/// One independent companionship opportunity every 30–90 minutes.
class MiuPetProactiveTimer {
  MiuPetProactiveTimer({required this.onDue, Random? random})
      : _random = random ?? Random();

  final Future<void> Function() onDue;
  final Random _random;
  Timer? _timer;
  bool _enabled = false;
  bool _disposed = false;

  void update(bool enabled) {
    if (_disposed || enabled == _enabled) return;
    _enabled = enabled;
    _timer?.cancel();
    if (enabled) _schedule();
  }

  void _schedule() {
    if (_disposed || !_enabled) return;
    _timer?.cancel();
    _timer = Timer(Duration(seconds: 1800 + _random.nextInt(3601)), () async {
      try {
        await onDue();
      } finally {
        _schedule();
      }
    });
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}
