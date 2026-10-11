import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Authoring widget only. The application plays the generated transparent atlases.
class MiuPetSequenceFrame extends StatefulWidget {
  const MiuPetSequenceFrame(
      {super.key, required this.mood, required this.seconds, this.blend = 1});
  final int mood;
  final double seconds, blend;
  @override
  State<MiuPetSequenceFrame> createState() => _MiuPetSequenceFrameState();
}

class _MiuPetSequenceFrameState extends State<MiuPetSequenceFrame> {
  ui.Image? _image;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bytes = await rootBundle.load('assets/miu_cat_head.png');
    final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    if (!mounted) {
      image.dispose();
      return;
    }
    setState(() => _image = image);
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frame = _PetFrame()..seconds = widget.seconds;
    frame.moods[0] = 1 - widget.blend;
    frame.moods[widget.mood] += widget.blend;
    return SizedBox(
        width: 196,
        height: 192,
        child: _image == null
            ? const SizedBox.shrink()
            : CustomPaint(painter: _PetPainter(_image!, frame)));
  }
}

class _PetFrame {
  double seconds = 0;
  final gaze = Offset.zero;
  final moods = List<double>.filled(10, 0);
}

class _PetPainter extends CustomPainter {
  _PetPainter(this.image, this.frame);

  final ui.Image image;
  final _PetFrame frame;
  static const _navy = Color(0xFF143571);
  double get t => frame.seconds;
  double mood(int index) => frame.moods[index];

  Offset _project(double x, double y, {double depth = 0}) => Offset(x, y);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2 - 89, size.height / 2 - 89);
    canvas.scale(178 / 126);
    final fullImage =
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    const target = Rect.fromLTWH(0, 0, 126, 126);
    final imagePaint = Paint()..filterQuality = FilterQuality.high;
    for (final side in [-1, 1]) {
      canvas.save();
      final pivot = Offset(side < 0 ? 38 : 88, 57);
      canvas.translate(pivot.dx, pivot.dy);
      canvas.rotate(math.sin(t * (math.pi * 2 / 2.4) + side * .6) * .016);
      canvas.translate(-pivot.dx, -pivot.dy);
      canvas.clipRect(Rect.fromLTWH(side < 0 ? 0 : 77, 0, 49, 61));
      canvas.drawImageRect(image, fullImage, target, imagePaint);
      canvas.restore();
    }
    canvas.save();
    canvas.clipPath(Path()
      ..addRect(const Rect.fromLTWH(0, 54, 126, 72))
      ..addRect(const Rect.fromLTWH(38, 0, 50, 126)));
    canvas.drawImageRect(image, fullImage, target, imagePaint);
    canvas.restore();
    _face(canvas);
    _reaction(canvas);
    canvas.restore();
  }

  void _face(Canvas canvas) {
    final blinkCycle = t % 6.7;
    double blinkAt(double at, double duration) {
      final distance = ((blinkCycle - at).abs() / duration).clamp(0.0, 1.0);
      return .5 + .5 * math.cos(distance * math.pi);
    }

    final blink = math.max(blinkAt(1.7, .14), blinkAt(5.65, .16));
    final sleepy = mood(4);
    void eye(double x, bool right) {
      final closure =
          (blink + sleepy * .92 + mood(7) * .97 + (right ? mood(1) * .98 : 0))
              .clamp(0.0, 1.0);
      final opening = 1 - closure;
      final center = _project(x, 75, depth: 3);
      final width = 19.0 + mood(5) * 2;
      final height = 25 * opening + 1;
      final eye = Rect.fromCenter(center: center, width: width, height: height);
      canvas.save();
      canvas.clipPath(Path()..addOval(eye.inflate(.6)));
      canvas.drawOval(eye, Paint()..color = Colors.white);
      final iris = eye.shift(
          Offset(frame.gaze.dx * 2.8, frame.gaze.dy * 1.6 - mood(3) * 1.5));
      canvas.drawOval(
          iris,
          Paint()
            ..shader = const RadialGradient(
              center: Alignment(.2, .55),
              radius: .95,
              colors: [Color(0xFF65E4FF), Color(0xFF208CE6), Color(0xFF132D72)],
              stops: [0, .45, 1],
            ).createShader(iris));
      canvas.drawOval(
          Rect.fromCenter(
              center: iris.center - Offset(0, 2 * opening),
              width: 8 + mood(2) * 2,
              height: 13 * opening),
          Paint()..color = const Color(0xFF122C61));
      canvas.drawOval(
          Rect.fromCenter(
              center: iris.center + Offset(-3, -6 * opening),
              width: 5,
              height: 6 * opening),
          Paint()..color = Colors.white.withOpacity(.95));
      canvas.drawOval(
          Rect.fromCenter(
              center: iris.center + Offset(4, 6 * opening),
              width: 2.8,
              height: 3 * opening),
          Paint()..color = const Color(0xCCBCEFFF));
      canvas.restore();
      final lid = Path()
        ..moveTo(center.dx - width / 2, center.dy - height * .13)
        ..quadraticBezierTo(center.dx, center.dy - height * .56 + closure * 6,
            center.dx + width / 2, center.dy - height * .13);
      canvas.drawPath(
          lid,
          Paint()
            ..color = _navy
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 1.5 + closure * 1.1);
    }

    eye(45, false);
    eye(81, true);
    final blush = mood(6) * .28 + mood(7) * .13;
    for (final x in [32.0, 94.0]) {
      final cheek =
          Rect.fromCenter(center: _project(x, 89), width: 18, height: 10);
      canvas.drawOval(
          cheek,
          Paint()
            ..shader = RadialGradient(
              colors: [
                Color.fromRGBO(255, 118, 168, blush),
                const Color(0x00FF76A8)
              ],
            ).createShader(cheek));
    }
    final worry = mood(3) + mood(8) + mood(9);
    final surprise = mood(2) + mood(5);
    final quiet = (mood(4) + mood(6) + worry).clamp(0.0, 1.0);
    final width = 9 - surprise * 4 - quiet * 2;
    final opening = (7 -
            quiet * 6 +
            surprise * 2 +
            mood(7) * 2 +
            math.sin(t * (math.pi * 2 / 2.4)) * (1 - quiet) * .45)
        .clamp(1.0, 11.0);
    final center = _project(63, 94, depth: 2);
    final mouth = Path()
      ..moveTo(center.dx - width, center.dy)
      ..quadraticBezierTo(
          center.dx, center.dy + 4 - worry * 8, center.dx + width, center.dy)
      ..quadraticBezierTo(
          center.dx, center.dy + opening * 2, center.dx - width, center.dy)
      ..close();
    canvas.drawPath(
        mouth,
        Paint()
          ..color = Color.lerp(
              const Color(0xFFE45680), const Color(0xFF9D6589), quiet)!);
    canvas.drawPath(
        mouth,
        Paint()
          ..color = _navy
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3
          ..strokeJoin = StrokeJoin.round);
    if (worry > .01) {
      final brow = _project(81, 57);
      canvas.drawPath(
          Path()
            ..moveTo(brow.dx - 8, brow.dy + 2 * mood(9))
            ..quadraticBezierTo(brow.dx, brow.dy - 4 * mood(3) + 3 * mood(8),
                brow.dx + 8, brow.dy + 2),
          Paint()
            ..color = _navy.withOpacity(worry.clamp(0.0, 1.0))
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 2);
    }
  }

  void _reaction(Canvas canvas) {
    final center = _project(107, 30);
    canvas.save();
    canvas.translate(
        center.dx, center.dy + math.sin(t * (math.pi * 2 / 2.4)) * 2);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final question = (mood(2) + mood(8)).clamp(0.0, 1.0);
    if (question > .01) {
      line.color = const Color(0xFF368DF3).withOpacity(question);
      canvas.drawPath(
          Path()
            ..moveTo(-5, -3)
            ..cubicTo(-3, -10, 8, -7, 5, 0)
            ..quadraticBezierTo(0, 3, 0, 5),
          line);
      canvas.drawCircle(const Offset(0, 10), 1.3, Paint()..color = line.color);
    }
    if (mood(4) > .01) {
      line.color = const Color(0xFF368DF3).withOpacity(mood(4));
      canvas.drawPath(
          Path()
            ..moveTo(-5, -3)
            ..lineTo(2, -3)
            ..lineTo(-5, 5)
            ..lineTo(2, 5),
          line);
    }
    if (mood(5) > .01) {
      line.color = const Color(0xFF368DF3).withOpacity(mood(5));
      canvas.drawLine(const Offset(0, -6), const Offset(0, 3), line);
      canvas.drawCircle(const Offset(0, 8), 1.5, Paint()..color = line.color);
    }
    if (mood(6) > .01) {
      canvas.drawPath(
          Path()
            ..moveTo(0, 9)
            ..cubicTo(-14, 0, -5, -10, 0, -3)
            ..cubicTo(5, -10, 14, 0, 0, 9)
            ..close(),
          Paint()..color = const Color(0xFFF47EAB).withOpacity(mood(6)));
    }
    if (mood(7) > .01) {
      canvas.drawPath(
          Path()
            ..moveTo(0, -7)
            ..lineTo(2, -1)
            ..lineTo(8, 1)
            ..lineTo(2, 3)
            ..lineTo(0, 9)
            ..lineTo(-2, 3)
            ..lineTo(-8, 1)
            ..lineTo(-2, -1)
            ..close(),
          Paint()..color = const Color(0xFF50BEFF).withOpacity(mood(7)));
    }
    canvas.restore();
    if (mood(9) > .01) {
      final drop =
          _project(92, 83 + (1 + math.sin(t * (math.pi * 2 / 2.4))) * 2);
      canvas.drawPath(
          Path()
            ..moveTo(drop.dx, drop.dy)
            ..quadraticBezierTo(drop.dx + 6, drop.dy + 9, drop.dx, drop.dy + 10)
            ..quadraticBezierTo(drop.dx - 5, drop.dy + 9, drop.dx, drop.dy),
          Paint()..color = const Color(0xFF64CFFF).withOpacity(mood(9)));
    }
  }

  @override
  bool shouldRepaint(_PetPainter oldDelegate) =>
      image != oldDelegate.image || frame != oldDelegate.frame;
}
