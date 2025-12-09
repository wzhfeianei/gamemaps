import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class EraserCursorPainter extends CustomPainter {
  final ui.Image image;
  final ValueListenable<Offset?> positionNotifier; // 使用 ValueListenable
  final double eraserSize;
  final BoxFit fit;

  EraserCursorPainter({
    required this.image,
    required this.positionNotifier,
    required this.eraserSize,
    this.fit = BoxFit.contain,
  }) : super(repaint: positionNotifier);

  @override
  void paint(Canvas canvas, Size size) {
    final currentPos = positionNotifier.value;
    if (currentPos == null) return;

    final imageWidth = image.width.toDouble();
    final imageHeight = image.height.toDouble();

    // 1. 计算图片在 Canvas 上的显示区域 (src -> dst)
    final double scaleX = size.width / imageWidth;
    final double scaleY = size.height / imageHeight;
    double scale = 1.0;
    double dx = 0.0;
    double dy = 0.0;

    if (fit == BoxFit.contain) {
      scale = scaleX < scaleY ? scaleX : scaleY;
      final displayWidth = imageWidth * scale;
      final displayHeight = imageHeight * scale;
      dx = (size.width - displayWidth) / 2;
      dy = (size.height - displayHeight) / 2;
    }

    // 坐标转换函数：图片坐标 -> Canvas 坐标
    Offset toCanvas(Offset p) {
      return Offset(p.dx * scale + dx, p.dy * scale + dy);
    }

    final canvasPos = toCanvas(currentPos!);

    // 绘制橡皮擦光标 (虚线圆圈)
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final paintBlack = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // 实际显示在屏幕上的半径
    final displayRadius = eraserSize * scale;

    canvas.drawCircle(canvasPos, displayRadius, paintBlack);
    _drawDashedCircle(canvas, canvasPos, displayRadius, paint);
  }

  void _drawDashedCircle(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint,
  ) {
    const int dashCount = 20;
    final double step = (math.pi * 2) / dashCount;
    for (int i = 0; i < dashCount; i += 2) {
      final double startAngle = i * step;
      final double endAngle = (i + 1) * step;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        step,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant EraserCursorPainter oldDelegate) {
    return oldDelegate.positionNotifier != positionNotifier ||
        oldDelegate.eraserSize != eraserSize ||
        oldDelegate.image != image;
  }
}
