import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../services/image_matching_service.dart';

class MatchPainter extends CustomPainter {
  final MatchResult? matchResult;
  final ui.Image? imageObj;
  final BoxFit fit;

  MatchPainter({this.matchResult, this.imageObj, this.fit = BoxFit.contain});

  @override
  void paint(Canvas canvas, Size size) {
    if (matchResult == null || imageObj == null) return;

    final imageWidth = imageObj!.width.toDouble();
    final imageHeight = imageObj!.height.toDouble();

    // 计算显示的图像尺寸和偏移量
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
    } else if (fit == BoxFit.cover) {
      scale = scaleX > scaleY ? scaleX : scaleY;
      // cover 模式下通常不需要居中偏移，而是裁剪，这里暂时假设是 contain
    } else if (fit == BoxFit.fill) {
      // fill 模式下 scaleX 和 scaleY 不同，不保持纵横比
      // 这里暂不处理 fill
    }

    final rect = matchResult!.rect;

    // 转换坐标
    final drawRect = Rect.fromLTWH(
      rect.x * scale + dx,
      rect.y * scale + dy,
      rect.width * scale,
      rect.height * scale,
    );

    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    canvas.drawRect(drawRect, paint);

    // 绘制置信度文本
    final textSpan = TextSpan(
      text: '${(matchResult!.confidence * 100).toStringAsFixed(1)}%',
      style: const TextStyle(
        color: Colors.red,
        fontSize: 14,
        fontWeight: FontWeight.bold,
        backgroundColor: Colors.white,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(drawRect.left, drawRect.top - 20));
  }

  @override
  bool shouldRepaint(covariant MatchPainter oldDelegate) {
    return oldDelegate.matchResult != matchResult ||
        oldDelegate.imageObj != imageObj;
  }
}
