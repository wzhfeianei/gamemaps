import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';

class DrawPainter extends CustomPainter {
  final ui.Image image;
  final List<Offset> points;
  final Offset? currentPos; // 图片坐标系下的当前鼠标位置
  final ByteData? pixelData; // 图片像素数据
  final BoxFit fit;

  DrawPainter({
    required this.image,
    required this.points,
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

    // 坐标转换函数：图片坐标 -> Canvas 坐标
    Offset toCanvas(Offset p) {
      return Offset(p.dx * scale + dx, p.dy * scale + dy);
    }

    // 2. 绘制路径
    if (points.isNotEmpty) {
      final paintPath = Paint()
        ..color = Colors.greenAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final path = Path();
      if (points.isNotEmpty) {
        path.moveTo(toCanvas(points[0]).dx, toCanvas(points[0]).dy);
        for (int i = 1; i < points.length; i++) {
          final p = toCanvas(points[i]);
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(path, paintPath);
      
      // 绘制起点和终点
      final paintDot = Paint()..color = Colors.yellow..style = PaintingStyle.fill;
      canvas.drawCircle(toCanvas(points.first), 4, paintDot);
      canvas.drawCircle(toCanvas(points.last), 4, paintDot);
    }

    // 3. 绘制放大镜和信息 (如果当前有鼠标位置)
    if (currentPos != null && pixelData != null) {
       _drawMagnifier(canvas, toCanvas(currentPos!), currentPos!, scale, size);
    }
  }

  void _drawMagnifier(Canvas canvas, Offset canvasPos, Offset imgPos, double scale, Size canvasSize) {
    // 放大镜参数
    const double magnifierSize = 100.0; // 放大镜窗口大小
    // 实际上我们想要显示像素网格。
    const int pixelRange = 10; // 半径
    
    // 放大镜位置：默认在光标右下，如果靠边则调整
    Offset magPos = canvasPos + const Offset(20, 20);
    if (magPos.dx + magnifierSize > canvasSize.width) {
      magPos = Offset(canvasPos.dx - magnifierSize - 20, magPos.dy);
    }
    if (magPos.dy + magnifierSize + 60 > canvasSize.height) { // +60 for info text
      magPos = Offset(magPos.dx, canvasPos.dy - magnifierSize - 80);
    }

    // 绘制放大镜背景
    final bgPaint = Paint()..color = Colors.black;
    final borderPaint = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2;
    
    final magRect = Rect.fromLTWH(magPos.dx, magPos.dy, magnifierSize, magnifierSize);
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
          pixelSize
        );
        
        canvas.drawRect(rect, Paint()..color = color);
        // 可以画像素网格线
        if (pixelSize > 4) {
           canvas.drawRect(rect, Paint()..color = Colors.grey.withOpacity(0.2)..style = PaintingStyle.stroke..strokeWidth = 0.5);
        }
      }
    }
    
    // 绘制十字准星
    final center = magRect.center;
    final crossPaint = Paint()..color = Colors.cyanAccent..strokeWidth = 1.0;
    canvas.drawLine(Offset(center.dx, magRect.top), Offset(center.dx, magRect.bottom), crossPaint);
    canvas.drawLine(Offset(magRect.left, center.dy), Offset(magRect.right, center.dy), crossPaint);
    
    canvas.drawRect(magRect, borderPaint);

    // 绘制下方信息：坐标和色值
    final infoBgRect = Rect.fromLTWH(magPos.dx, magPos.dy + magnifierSize, magnifierSize, 60);
    canvas.drawRect(infoBgRect, Paint()..color = Colors.white);
    
    // 获取当前中心点颜色
    Color centerColor = Colors.black;
    if (imgPos.dx >= 0 && imgPos.dx < image.width && imgPos.dy >= 0 && imgPos.dy < image.height) {
      centerColor = _getPixelColor(imgPos.dx.floor(), imgPos.dy.floor());
    }
    
    // Hex 字符串
    String hex = '#${centerColor.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
    
    String infoText = '坐标: (${imgPos.dx.floor()}, ${imgPos.dy.floor()})\n色值: $hex';
    
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
    final offset = (y * image.width + x) * 4;
    if (offset + 3 >= pixelData!.lengthInBytes) return Colors.black;
    
    final r = pixelData!.getUint8(offset);
    final g = pixelData!.getUint8(offset + 1);
    final b = pixelData!.getUint8(offset + 2);
    final a = pixelData!.getUint8(offset + 3);
    
    return Color.fromARGB(a, r, g, b);
  }

  @override
  bool shouldRepaint(covariant DrawPainter oldDelegate) {
    return oldDelegate.image != image ||
           oldDelegate.points != points ||
           oldDelegate.currentPos != currentPos;
  }
}
