import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';

class CropPainter extends CustomPainter {
  final ui.Image image;
  final Offset? start;
  final Offset? end;
  final Offset? currentPos; // 图片坐标系下的当前鼠标位置
  final ByteData? pixelData; // 图片像素数据
  final BoxFit fit;

  CropPainter({
    required this.image,
    this.start,
    this.end,
    this.currentPos,
    this.pixelData,
    this.fit = BoxFit.contain,
  });

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
    // TODO: 支持其他 BoxFit

    // 坐标转换函数：图片坐标 -> Canvas 坐标
    Offset toCanvas(Offset p) {
      return Offset(p.dx * scale + dx, p.dy * scale + dy);
    }

    // 2. 绘制半透明遮罩
    // 如果没有选区，全黑半透明；如果有选区，挖空选区
    final paintMask = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..style = PaintingStyle.fill;

    Rect? selectionRect;
    if (start != null && end != null) {
      final p1 = toCanvas(start!);
      final p2 = toCanvas(end!);
      selectionRect = Rect.fromPoints(p1, p2);
    } else if (start != null && currentPos != null) {
      // 拖拽中
      final p1 = toCanvas(start!);
      final p2 = toCanvas(currentPos!);
      selectionRect = Rect.fromPoints(p1, p2);
    }

    if (selectionRect != null) {
      // 绘制挖空的遮罩
      // 方法：绘制整个矩形，然后用 dstOut 混合模式或者 Path
      // 这里用 Path 比较简单
      final path = Path()
        ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
        ..addRect(selectionRect)
        ..fillType = PathFillType.evenOdd;
      canvas.drawPath(path, paintMask);

      // 绘制选区边框
      final paintBorder = Paint()
        ..color = Colors.cyanAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawRect(selectionRect, paintBorder);

      // 3. 绘制左上角尺寸信息
      // 计算原始尺寸
      // 反算图片坐标
      double imgW = selectionRect.width / scale;
      double imgH = selectionRect.height / scale;

      final sizeText = '${imgW.round()} * ${imgH.round()}';
      _drawTooltip(
        canvas,
        selectionRect.topLeft - const Offset(0, 25),
        sizeText,
        isTop: true,
      );
    } else {
      // 全屏遮罩
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paintMask);
    }

    // 4. 绘制放大镜和信息 (如果当前有鼠标位置)
    if (currentPos != null && pixelData != null) {
      _drawMagnifier(canvas, toCanvas(currentPos!), currentPos!, scale, size);
    }
  }

  void _drawTooltip(
    Canvas canvas,
    Offset pos,
    String text, {
    bool isTop = true,
  }) {
    final textSpan = TextSpan(
      text: text,
      style: const TextStyle(color: Colors.black, fontSize: 12),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    final padding = 4.0;
    final bgRect = Rect.fromLTWH(
      pos.dx,
      pos.dy,
      textPainter.width + padding * 2,
      textPainter.height + padding * 2,
    );

    final bgPaint = Paint()..color = Colors.white;
    // 稍微调整位置，保证不超出边界? 暂时忽略
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(4)),
      bgPaint,
    );
    textPainter.paint(canvas, Offset(pos.dx + padding, pos.dy + padding));
  }

  void _drawMagnifier(
    Canvas canvas,
    Offset canvasPos,
    Offset imgPos,
    double scale,
    Size canvasSize,
  ) {
    // 放大镜参数
    const double magnifierSize = 100.0; // 放大镜窗口大小
    const double zoomLevel = 2.0; // 放大倍数 (相对于原始图片像素)
    // 实际上我们想要显示像素网格。
    // 假设我们在放大镜里显示 20x20 的像素区域。
    const int pixelRange = 10; // 半径

    // 放大镜位置：默认在光标右下，如果靠边则调整
    Offset magPos = canvasPos + const Offset(20, 20);
    if (magPos.dx + magnifierSize > canvasSize.width) {
      magPos = Offset(canvasPos.dx - magnifierSize - 20, magPos.dy);
    }
    if (magPos.dy + magnifierSize + 60 > canvasSize.height) {
      // +60 for info text
      magPos = Offset(magPos.dx, canvasPos.dy - magnifierSize - 80);
    }

    // 绘制放大镜背景
    final bgPaint = Paint()..color = Colors.black;
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final magRect = Rect.fromLTWH(
      magPos.dx,
      magPos.dy,
      magnifierSize,
      magnifierSize,
    );
    canvas.drawRect(magRect, bgPaint);

    // 绘制放大的像素
    // 这里的逻辑：遍历 imgPos 周围的像素，绘制矩形
    double pixelSize = magnifierSize / (pixelRange * 2); // 每个像素在放大镜中的大小

    for (int y = -pixelRange; y < pixelRange; y++) {
      for (int x = -pixelRange; x < pixelRange; x++) {
        int px = imgPos.dx.floor() + x;
        int py = imgPos.dy.floor() + y;

        Color color = Colors.black;
        if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
          color = _getPixelColor(px, py);
        }

        final rect = Rect.fromLTWH(
          magPos.dx + (x + pixelRange) * pixelSize,
          magPos.dy + (y + pixelRange) * pixelSize,
          pixelSize,
          pixelSize,
        );

        canvas.drawRect(rect, Paint()..color = color);
        // 可以画像素网格线
        if (pixelSize > 4) {
          canvas.drawRect(
            rect,
            Paint()
              ..color = Colors.grey.withOpacity(0.2)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.5,
          );
        }
      }
    }

    // 绘制十字准星
    final center = magRect.center;
    final crossPaint = Paint()
      ..color = Colors.cyanAccent
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(center.dx, magRect.top),
      Offset(center.dx, magRect.bottom),
      crossPaint,
    );
    canvas.drawLine(
      Offset(magRect.left, center.dy),
      Offset(magRect.right, center.dy),
      crossPaint,
    );

    canvas.drawRect(magRect, borderPaint);

    // 绘制下方信息：坐标和色值
    final infoBgRect = Rect.fromLTWH(
      magPos.dx,
      magPos.dy + magnifierSize,
      magnifierSize,
      60,
    );
    canvas.drawRect(infoBgRect, Paint()..color = Colors.white);

    // 获取当前中心点颜色
    Color centerColor = Colors.black;
    if (imgPos.dx >= 0 &&
        imgPos.dx < image.width &&
        imgPos.dy >= 0 &&
        imgPos.dy < image.height) {
      centerColor = _getPixelColor(imgPos.dx.floor(), imgPos.dy.floor());
    }

    // Hex 字符串
    String hex =
        '#${centerColor.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

    String infoText =
        '坐标: (${imgPos.dx.floor()}, ${imgPos.dy.floor()})\n色值: $hex';

    final textSpan = TextSpan(
      text: infoText,
      style: const TextStyle(color: Colors.black, fontSize: 10, height: 1.5),
    );
    final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
    tp.layout();
    tp.paint(canvas, Offset(magPos.dx + 4, magPos.dy + magnifierSize + 4));
  }

  Color _getPixelColor(int x, int y) {
    if (pixelData == null) return Colors.black;
    // 假设是 RGBA8888 或 BGRA8888
    // Flutter ui.Image.toByteData(format: ImageByteFormat.rawRgba) 默认是 RGBA
    // 需要确保获取时指定格式
    final offset = (y * image.width + x) * 4;
    if (offset + 3 >= pixelData!.lengthInBytes) return Colors.black;

    final r = pixelData!.getUint8(offset);
    final g = pixelData!.getUint8(offset + 1);
    final b = pixelData!.getUint8(offset + 2);
    final a = pixelData!.getUint8(offset + 3);

    return Color.fromARGB(a, r, g, b);
  }

  @override
  bool shouldRepaint(covariant CropPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.start != start ||
        oldDelegate.end != end ||
        oldDelegate.currentPos != currentPos;
  }
}
