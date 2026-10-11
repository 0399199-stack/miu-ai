import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Authoring rig for the original black/red texture: angular brows and eyes
/// remain part of the supplied illustration, rather than Luna's rounded face.
class MiuVoidSequencePainter extends CustomPainter {
  MiuVoidSequencePainter(this.image, this.mood, this.seconds, this.blend);
  final ui.Image image;
  final int mood;
  final double seconds, blend;
  double weight(int index) => mood == index ? blend : 0;
  double get phase => seconds * math.pi * 2 / 2.4;

  double _feather(double value, double inner, double outer) {
    final t = ((value.abs() - inner) / (outer - inner)).clamp(0.0, 1.0);
    return 1 - t * t * (3 - 2 * t);
  }

  @override
  void paint(Canvas canvas, Size size) {
    const grid = 80;
    final points = Float32List((grid + 1) * (grid + 1) * 2);
    final texture = Float32List(points.length);
    final indices = Uint16List(grid * grid * 6);
    final blinkDistance = ((seconds - 1.7).abs() / .15).clamp(0.0, 1.0);
    final blink = .5 + .5 * math.cos(blinkDistance * math.pi);
    final sleepy = weight(4);
    final relaxed = weight(6);
    final angry = weight(9);
    final alert = weight(2);
    final roar = weight(5);
    final joy = weight(7);
    final skeptical = weight(8);
    final thinking = weight(3);
    final smug = weight(1);
    var v = 0;
    for (var row = 0; row <= grid; row++) {
      for (var col = 0; col <= grid; col++) {
        final x = col / grid;
        final y = row / grid;
        var dx = 0.0, dy = 0.0;
        for (final side in [-1, 1]) {
          final cx = side < 0 ? .326 : .648;
          final eye = _feather(x - cx, .095, .17) *
              _feather(y - .653, .058, .125);
          final closure = (blink + sleepy * .93 + relaxed * .95 +
              angry * .42 + joy * .37 +
              (side > 0 ? smug * .68 + skeptical * .80 : thinking * .48))
              .clamp(0.0, .97);
          final slant = (side < 0 ? 1 : -1) * .35;
          final lidY = .652 + (x - cx) * slant;
          dy += (-(y - lidY) * closure +
                  alert * ((y - .64) * .65 - .007) - angry * .022 +
                  thinking * (side < 0 ? .015 : -.020) +
                  skeptical * (side < 0 ? -.025 : .012)) * eye;
          dx += (math.sin(phase) * .002 + thinking * .012 - skeptical * .009) * eye;

          final earX = side < 0 ? .22 : .76;
          final ear = _feather(x - earX, .08, .23) *
              _feather(y - .24, .13, .27);
          final angle = (math.sin(phase + side * .5) * .018 +
              alert * side * -.018 + sleepy * side * .045 +
              roar * math.sin(phase * 2) * .012 + angry * side * -.023);
          dx += (-(y - .43) * angle) * ear;
          dy += ((x - earX) * angle) * ear;
        }
        final mouth = _feather(x - .488, .071, .14) *
            _feather(y - .741, .03, .072);
        dx += (x - .488) * (smug * .05 - sleepy * .16 - relaxed * .12) * mouth;
        dy += ((x - .488) * (smug * -.11 + skeptical * .1) +
            math.sin(phase) * .0018 * (1 - sleepy) + joy * .002) * mouth;
        points[v] = (x + dx) * 178 + size.width / 2 - 89;
        points[v + 1] = (y + dy) * 178 + size.height / 2 - 89;
        texture[v] = x * image.width;
        texture[v + 1] = y * image.height;
        v += 2;
      }
    }
    var i = 0;
    for (var y = 0; y < grid; y++) {
      for (var x = 0; x < grid; x++) {
        final a = y * (grid + 1) + x;
        for (final vertex in [a, a + 1, a + grid + 1, a + 1, a + grid + 2, a + grid + 1]) {
          indices[i++] = vertex;
        }
      }
    }
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(joy * (-.07 + math.sin(phase) * .02) +
        thinking * .04 - skeptical * .035);
    canvas.translate(-size.width / 2, -size.height / 2);
    canvas.drawVertices(
        ui.Vertices.raw(ui.VertexMode.triangles, points,
            textureCoordinates: texture, indices: indices),
        BlendMode.srcOver,
        Paint()
          ..filterQuality = FilterQuality.high
          ..shader = ImageShader(image, TileMode.clamp, TileMode.clamp,
              Float64List.fromList([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])));

    canvas.save();
    canvas.translate(size.width / 2 - 89, size.height / 2 - 89);
    canvas.scale(178);
    if (roar + joy + angry > 0) _expressiveMouth(canvas, roar, joy, angry);
    _marks(canvas);
    canvas.restore();
    canvas.restore();
  }

  void _expressiveMouth(Canvas canvas, double roar, double joy, double angry) {
    final amount = roar + joy + angry;
    final opening = (.066 + (.5 + .5 * math.sin(phase)) * .02) * roar +
        (.045 + math.sin(phase) * .006) * joy +
        (.025 + math.sin(phase) * .004) * angry;
    final mouth = Path()
      ..moveTo(.393, .724)
      ..quadraticBezierTo(.488, .764 - opening * .32, .583, .724 - joy * .012)
      ..quadraticBezierTo(.586, .755 + opening, .488, .765 + opening)
      ..quadraticBezierTo(.394, .755 + opening, .393, .724);
    canvas.drawPath(mouth, Paint()..color = const Color(0xFF0A0508));
    canvas.drawPath(mouth, Paint()
      ..color = const Color(0xFF090609).withOpacity(amount)
      ..style = PaintingStyle.stroke..strokeWidth = .004);
    final teeth = Path()
      ..moveTo(.409, .732)..lineTo(.457, .744)..lineTo(.434, .767 + opening * .32)..close()
      ..moveTo(.568, .732 - joy * .007)..lineTo(.519, .744)
      ..lineTo(.542, .767 + opening * .32)..close();
    canvas.drawPath(teeth, Paint()..color = const Color(0xFFF3F2F5));
    if (angry > 0) {
      canvas.drawPath(Path()..moveTo(.432, .79)..lineTo(.458, .766)
        ..lineTo(.484, .788)..lineTo(.511, .766)..lineTo(.544, .79)..close(),
        Paint()..color = const Color(0xFFF3F2F5).withOpacity(angry));
    }
    if (roar + joy > 0) {
      final tongue = Rect.fromCenter(center: Offset(.488 + joy * .026, .77 + opening * .78),
          width: .073, height: opening * (.65 + joy * .55));
      canvas.drawOval(tongue, Paint()..color = const Color(0xFFCF1744));
      if (joy > 0) {
        canvas.drawLine(tongue.center - const Offset(0, .008),
            tongue.center + const Offset(0, .013), Paint()
              ..color = const Color(0xFF80112A)..strokeWidth = .0025);
      }
    }
  }

  void _marks(Canvas canvas) {
    final lift = math.sin(phase) * .008;
    final pen = Paint()..style = PaintingStyle.stroke..strokeWidth = .008
      ..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    canvas.save();
    canvas.translate(.82, .36 + lift);
    final question = weight(3) + weight(8);
    if (question > 0) {
      pen.color = const Color(0xFFFF3658).withOpacity(question);
      canvas.drawPath(Path()..moveTo(-.013, -.021)
        ..cubicTo(-.01, -.052, .038, -.052, .027, -.019)
        ..quadraticBezierTo(.004, -.004, .01, .012), pen);
      canvas.drawCircle(const Offset(.01, .033), .005, Paint()..color = pen.color);
    }
    if (weight(2) > 0) {
      pen.color = const Color(0xFFFF3150).withOpacity(weight(2));
      canvas.drawLine(const Offset(.01, -.036), const Offset(.01, .009), pen);
      canvas.drawCircle(const Offset(.01, .031), .005, Paint()..color = pen.color);
    }
    if (weight(4) > 0) {
      pen.color = const Color(0xFFFF6178).withOpacity(weight(4));
      canvas.drawPath(Path()..moveTo(-.025, -.025)..lineTo(.015, -.025)
        ..lineTo(-.025, .018)..lineTo(.018, .018), pen);
    }
    if (weight(9) > 0) {
      pen.color = const Color(0xFFFF2346).withOpacity(weight(9));
      for (final s in [-1, 1]) {
        canvas.drawPath(Path()..moveTo(s * .027, -.029)..lineTo(s * .027, -.009)
          ..lineTo(s * .006, -.009), pen);
        canvas.drawPath(Path()..moveTo(s * .027, .029)..lineTo(s * .027, .009)
          ..lineTo(s * .006, .009), pen);
      }
    }
    if (weight(7) > 0) {
      pen.color = const Color(0xFFFF2850).withOpacity(weight(7));
      canvas.drawPath(Path()..moveTo(.015, -.043)..lineTo(-.018, -.005)
        ..lineTo(.018, -.005)..lineTo(-.01, .036), pen);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(MiuVoidSequencePainter oldDelegate) => true;
}
