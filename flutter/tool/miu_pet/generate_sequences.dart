import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'sequence_frame.dart';

void main() {
  testWidgets('export transparent cat sequences', (tester) async {
    final output = Directory(
        Platform.environment['MIU_PET_FRAME_DIR'] ?? 'build/miu-pet-frames');
    output.createSync(recursive: true);
    final key = GlobalKey();
    final moods = int.parse(Platform.environment['MIU_PET_MOODS'] ?? '10');
    final character = Platform.environment['MIU_PET_CHARACTER'] ?? 'luna';
    for (var mood = 0; mood < moods; mood++) {
      Directory('${output.path}/$mood').createSync();
      for (var frame = 0; frame < 169; frame++) {
        await tester.pumpWidget(MaterialApp(
            home: Center(
          child: RepaintBoundary(
              key: key,
              child: MiuPetSequenceFrame(
                character: character,
                mood: mood,
                seconds: frame < 144 ? frame / 60 : 0,
                blend: frame < 144
                    ? 1
                    : Curves.easeInOutCubic.transform((frame - 144) / 24),
              )),
        )));
        if (mood == 0 && frame == 0) {
          await tester
              .runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
          await tester.pump();
        }
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 256 / 196);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          File('${output.path}/$mood/frame-${frame.toString().padLeft(4, '0')}.png')
              .writeAsBytesSync(data!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
