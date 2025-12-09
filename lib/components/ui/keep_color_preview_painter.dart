import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class KeepColorPreviewPainter extends CustomPainter {
  final ui.Image? image;
  final ui.Image? maskImage; // 这里传入的是已经处理好的预览图像 (保留部分原样，剔除部分透明)
  final BoxFit fit;

  KeepColorPreviewPainter({
    required this.image,
    required this.maskImage,
    this.fit = BoxFit.contain,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (maskImage == null) return;

    final imageWidth = maskImage!.width.toDouble();
    final imageHeight = maskImage!.height.toDouble();

    // 计算显示区域 (src -> dst)
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

    final dstRect = Rect.fromLTWH(
      dx,
      dy,
      imageWidth * scale,
      imageHeight * scale,
    );

    // 绘制棋盘格背景，以突显透明区域
    _drawCheckerboard(canvas, dstRect);

    // 绘制预览图像
    canvas.drawImageRect(
      maskImage!,
      Rect.fromLTWH(0, 0, imageWidth, imageHeight),
      dstRect,
      Paint(),
    );
  }

  void _drawCheckerboard(Canvas canvas, Rect rect) {
    final Paint paintGray = Paint()..color = Colors.grey[300]!;
    final Paint paintWhite = Paint()..color = Colors.white;
    const double gridSize = 10.0;

    canvas.save();
    canvas.clipRect(rect);
    canvas.translate(rect.left, rect.top);

    for (double y = 0; y < rect.height; y += gridSize) {
      for (double x = 0; x < rect.width; x += gridSize) {
        if (((x / gridSize).floor() + (y / gridSize).floor()) % 2 == 0) {
          canvas.drawRect(Rect.fromLTWH(x, y, gridSize, gridSize), paintGray);
        } else {
          canvas.drawRect(Rect.fromLTWH(x, y, gridSize, gridSize), paintWhite);
        }
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant KeepColorPreviewPainter oldDelegate) {
    return oldDelegate.maskImage != maskImage;
  }
}
