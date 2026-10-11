import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Transparent 60 fps sequences with neutral transition frames between moods.
/// Pointer response is independent, so interaction never restarts the loop.
class MiuPetAvatar extends StatefulWidget {
  const MiuPetAvatar({super.key, required this.mood});
  final int mood;

  @override
  State<MiuPetAvatar> createState() => _MiuPetAvatarState();
}

class _MiuPetAvatarState extends State<MiuPetAvatar>
    with SingleTickerProviderStateMixin {
  final _frame = _PetFrame();
  late final Ticker _ticker;
  Duration _previous = Duration.zero;
  Offset _targetGaze = Offset.zero;
  bool _followingPointer = false;
  ui.Image? _current;
  ui.Image? _next;
  int _currentMood = 0;
  int _nextMood = 0;
  bool _loading = false;
  bool _loadFailed = false;
  double _loopSeconds = 0;
  double _transition = -1;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_advance)..start();
    _loadMood();
  }

  @override
  void didUpdateWidget(covariant MiuPetAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mood != widget.mood) {
      if (_transition == -2 && _nextMood != widget.mood) {
        _next?.dispose();
        _next = null;
        _transition = -1;
      }
      _loadMood();
    }
  }

  Future<void> _loadMood() async {
    if (_loading ||
        _next != null ||
        (_current != null && _currentMood == widget.mood)) return;
    _loading = true;
    final mood = widget.mood.clamp(0, 9);
    try {
      final bytes = await rootBundle.load('assets/miu_pet_sequences/$mood.png');
      final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
      final image = (await codec.getNextFrame()).image;
      codec.dispose();
      if (!mounted) {
        image.dispose();
        return;
      }
      if (_current != null && mood != widget.mood) {
        image.dispose();
        return;
      }
      if (_current == null) {
        _current = image;
        _currentMood = mood;
        _frame.image = image;
      } else {
        _next = image;
        _nextMood = mood;
        _transition = -2;
      }
      if (_loadFailed) setState(() => _loadFailed = false);
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      _loading = false;
      if (mounted &&
          !_loadFailed &&
          _transition < 0 &&
          _currentMood != widget.mood) _loadMood();
    }
  }

  void _advance(Duration elapsed) {
    final dt = ((elapsed - _previous).inMicroseconds / 1000000).clamp(0.0, .05);
    _previous = elapsed;
    _frame.seconds += dt;
    final target = _followingPointer
        ? _targetGaze
        : Offset(math.sin(_frame.seconds * .71) * .25,
            math.sin(_frame.seconds * .43) * .13);
    _frame.gaze += (target - _frame.gaze) * (1 - math.exp(-dt * 9));
    _frame.excitement += ((widget.mood == 7 ? 1 : 0) - _frame.excitement) *
        (1 - math.exp(-dt * 8));
    if (_transition >= 0 && _next != null) {
      _transition += dt;
      if (_transition >= .8 || (_nextMood == 0 && _transition >= .4)) {
        final previous = _current;
        _current = _next;
        _currentMood = _nextMood;
        _next = null;
        _transition = -1;
        _loopSeconds = 0;
        _frame.image = _current;
        _frame.index = 0;
        previous?.dispose();
        _loadMood();
      } else if (_transition < .4) {
        _frame.image = _current;
        _frame.index = 168 - (_transition / .4 * 24).floor().clamp(0, 24);
      } else {
        _frame.image = _next;
        _frame.index =
            144 + ((_transition - .4) / .4 * 24).floor().clamp(0, 24);
      }
    } else {
      final previousLoop = (_loopSeconds / 2.4).floor();
      _loopSeconds += dt;
      _frame.index = (_loopSeconds * 60).floor() % 144;
      if (_next != null && (_loopSeconds / 2.4).floor() > previousLoop) {
        _transition = _currentMood == 0 ? .4 : 0;
      }
    }
    _frame.refresh();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    _current?.dispose();
    _next?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
        onHover: (event) {
          _followingPointer = true;
          _targetGaze = Offset(
              ((event.localPosition.dx - 98) / 75).clamp(-1.0, 1.0),
              ((event.localPosition.dy - 96) / 75).clamp(-1.0, 1.0));
        },
        onExit: (_) => _followingPointer = false,
        child: RepaintBoundary(
            child: SizedBox(
          width: 196,
          height: 192,
          child: _loadFailed && _current == null
              ? Image.asset('assets/miu_cat_head.png')
              : CustomPaint(painter: _PetSequencePainter(_frame)),
        )),
      );
}

class _PetFrame extends ChangeNotifier {
  double seconds = 0;
  double excitement = 0;
  Offset gaze = Offset.zero;
  ui.Image? image;
  int index = 0;
  void refresh() => notifyListeners();
}

class _PetSequencePainter extends CustomPainter {
  _PetSequencePainter(this.frame) : super(repaint: frame);
  final _PetFrame frame;

  @override
  void paint(Canvas canvas, Size size) {
    final image = frame.image;
    if (image == null) return;
    final time = frame.seconds;
    final lift =
        math.sin(time * 1.8) * 2 + frame.excitement * math.sin(time * 4.6) * 3;
    final roll = math.sin(time * 1.2) * .018 + frame.gaze.dx * .035;
    canvas.save();
    canvas.translate(size.width / 2 + frame.gaze.dx * 2.5,
        size.height / 2 + lift + frame.gaze.dy * 1.5);
    canvas.rotate(roll);
    canvas.scale(1 + frame.excitement * .015, 1 + math.sin(time * 1.8) * .006);
    canvas.drawImageRect(
        image,
        Rect.fromLTWH(
            (frame.index % 13) * 256.0, (frame.index ~/ 13) * 256.0, 256, 256),
        Rect.fromCenter(
            center: Offset.zero, width: size.width, height: size.width),
        Paint()..filterQuality = FilterQuality.high);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PetSequencePainter oldDelegate) =>
      frame != oldDelegate.frame;
}
