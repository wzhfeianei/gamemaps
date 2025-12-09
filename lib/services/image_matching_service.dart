import 'dart:typed_data';
import 'package:opencv_dart/opencv_dart.dart' as cv;

class MatchResult {
  final cv.Rect rect;
  final double confidence;

  MatchResult(this.rect, this.confidence);

  @override
  String toString() {
    return 'MatchResult(rect: $rect, confidence: $confidence)';
  }
}

class ImageMatchingService {
  /// 在源图像中查找模板图像
  /// [sourceBytes] 源图像数据
  /// [templateBytes] 模板图像数据
  /// [threshold] 匹配阈值，默认为 0.8
  /// 返回匹配结果，如果没有找到匹配项则返回 null
  static Future<MatchResult?> matchTemplate(
    Uint8List sourceBytes,
    Uint8List templateBytes, {
    double threshold = 0.8,
  }) async {
    try {
      // 解码图像
      final source = cv.imdecode(sourceBytes, cv.IMREAD_COLOR);
      final template = cv.imdecode(templateBytes, cv.IMREAD_COLOR);

      if (source.isEmpty || template.isEmpty) {
        print('Error: Source or template image is empty');
        return null;
      }

      // 确保源图像比模板图像大
      if (source.rows < template.rows || source.cols < template.cols) {
        print('Error: Source image must be larger than template image');
        return null;
      }

      // 模板匹配
      // 使用 TM_CCOEFF_NORMED 标准化相关系数匹配法，结果在 -1 到 1 之间，1 表示完全匹配
      final result = await cv.matchTemplateAsync(
        source,
        template,
        cv.TM_CCOEFF_NORMED,
      );

      // 获取最大匹配值和位置
      final minMax = await cv.minMaxLocAsync(result);
      final maxVal = minMax.$2;
      final maxLoc = minMax.$4;

      // 保存模板尺寸
      final templateCols = template.cols;
      final templateRows = template.rows;

      // 释放内存
      source.dispose();
      template.dispose();
      result.dispose();

      print('Match confidence: $maxVal');

      // 检查是否达到阈值
      if (maxVal >= threshold) {
        return MatchResult(
          cv.Rect(maxLoc.x, maxLoc.y, templateCols, templateRows),
          maxVal,
        );
      }

      return null;
    } catch (e) {
      print('Error matching template: $e');
      return null;
    }
  }
}
