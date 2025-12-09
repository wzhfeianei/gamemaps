import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class ImageEditorPainter extends CustomPainter {
  final ui.Image image;
  final List<Offset> eraserPath;
  final double eraserSize;
  final ValueListenable<Offset?> positionNotifier;
  final BoxFit fit;

  ImageEditorPainter({
    required this.image,
    required this.eraserPath,
    required this.eraserSize,
    required this.positionNotifier,
    this.fit = BoxFit.contain,
  }) : super(repaint: positionNotifier);

  @override
  void paint(Canvas canvas, Size size) {
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

    // 2. 绘制图片层
    // 使用 saveLayer 创建新的图层，以便 BlendMode.clear 只清除图片内容，不清除背景
    // 注意：saveLayer 有一定性能开销，但对于这种编辑场景通常是必要的
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());

    // 绘制原始图片
    // 注意：这里我们直接绘制图片到正确的位置
    final srcRect = Rect.fromLTWH(0, 0, imageWidth, imageHeight);
    final dstRect = Rect.fromLTWH(
      dx,
      dy,
      imageWidth * scale,
      imageHeight * scale,
    );
    canvas.drawImageRect(image, srcRect, dstRect, Paint());

    // 3. 绘制橡皮擦路径 (清除模式)
    if (eraserPath.isNotEmpty) {
      final paintClear = Paint()
        ..blendMode = BlendMode.clear
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap
            .square // 改为方形笔触
        ..strokeWidth = eraserSize * scale;

      // 如果点很多，建议使用 Path，这里简单处理
      // 为了平滑，我们可以构建 Path
      if (eraserPath.length > 1) {
        final path = Path();
        final start = toCanvas(eraserPath[0]);
        path.moveTo(start.dx, start.dy);

        for (int i = 1; i < eraserPath.length; i++) {
          final p = toCanvas(eraserPath[i]);
          path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path, paintClear);
      } else if (eraserPath.length == 1) {
        // 单个点绘制正方形
        final p = toCanvas(eraserPath[0]);
        final size = eraserSize * scale;
        canvas.drawRect(
          Rect.fromCenter(center: p, width: size, height: size),
          Paint()..blendMode = BlendMode.clear,
        );
      }
    }

    canvas.restore(); // 恢复图层，将合成结果绘制到 Canvas

    // 4. 绘制光标 (悬浮层)
    final currentPos = positionNotifier.value;
    if (currentPos != null) {
      final canvasPos = toCanvas(currentPos);
      // eraserSize 是边长 (如果是圆形则是直径/半径? 之前 radius = eraserSize. 这里假设 eraserSize 是直径/边长)
      // 之前的代码: displayRadius = eraserSize * scale. drawCircle(..., displayRadius) -> 直径是 2*eraserSize
      // 现在的代码:
      // 假设 _eraserSize 是“半径”或“大小因子”？
      // 原来: drawCircle(canvasPos, displayRadius, ...) -> 半径是 displayRadius
      // 原来: displayRadius = eraserSize * scale.
      // 所以原来圆的直径是 2 * eraserSize * scale.

      // 现在改为正方形:
      // 为了保持视觉大小一致，正方形边长应该接近圆的直径。
      // 所以 sideLength = 2 * eraserSize * scale.

      final displaySide = eraserSize * scale * 2; // 边长
      final rect = Rect.fromCenter(
        center: canvasPos,
        width: displaySide,
        height: displaySide,
      );

      final paintWhite = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      final paintBlack = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      canvas.drawRect(rect, paintBlack);
      _drawDashedRect(canvas, rect, paintWhite);
    }
  }

  void _drawDashedRect(Canvas canvas, Rect rect, Paint paint) {
    // 简单实现虚线矩形
    final path = Path()..addRect(rect);
    // 这里可以使用 dashPath 逻辑，或者简单分段绘制
    // 手动绘制四条边的虚线比较繁琐，这里简化处理：
    // 使用 drawPath 并配合 dash effect (需要 path_drawing 库或自己实现)
    // 为了不引入新库，我们手动绘制四边

    final double dashWidth = 5.0;
    final double dashSpace = 5.0;

    _drawDashedLine(
      canvas,
      rect.topLeft,
      rect.topRight,
      dashWidth,
      dashSpace,
      paint,
    );
    _drawDashedLine(
      canvas,
      rect.topRight,
      rect.bottomRight,
      dashWidth,
      dashSpace,
      paint,
    );
    _drawDashedLine(
      canvas,
      rect.bottomRight,
      rect.bottomLeft,
      dashWidth,
      dashSpace,
      paint,
    );
    _drawDashedLine(
      canvas,
      rect.bottomLeft,
      rect.topLeft,
      dashWidth,
      dashSpace,
      paint,
    );
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset p1,
    Offset p2,
    double dashWidth,
    double dashSpace,
    Paint paint,
  ) {
    final double dx = p2.dx - p1.dx;
    final double dy = p2.dy - p1.dy;
    final double distance = math.sqrt(dx * dx + dy * dy);
    final double angle = math.atan2(dy, dx);

    double currentDistance = 0;
    while (currentDistance < distance) {
      final double len = math.min(dashWidth, distance - currentDistance);
      final double startX = p1.dx + math.cos(angle) * currentDistance;
      final double startY = p1.dy + math.sin(angle) * currentDistance;
      final double endX = startX + math.cos(angle) * len;
      final double endY = startY + math.sin(angle) * len;

      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), paint);
      currentDistance += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant ImageEditorPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.eraserPath != eraserPath || // 列表引用变化或内容变化需要外部触发
        oldDelegate.eraserSize != eraserSize ||
        oldDelegate.positionNotifier != positionNotifier;
  }
}
