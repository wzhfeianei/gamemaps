import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'image_preprocessor.dart';

enum MatchingAlgorithm {
  /// 单尺度 + Mask (原生)
  /// 速度慢，精度高
  directMasked,

  /// 单尺度 + 无 Mask (全图)
  /// 速度极快(FFT)，但不支持透明背景
  directUnmasked,

  /// 金字塔 + 混合模式 (推荐)
  /// 粗筛(无Mask) -> 精筛(有Mask)
  /// 速度快，精度高，兼顾透明背景
  pyramidHybrid,

  /// 金字塔 + 全 Mask
  /// 粗筛(有Mask) -> 精筛(有Mask)
  /// 速度中等，精度最高
  pyramidMasked,
}

class MatchResult {
  // 使用自定义的 Rect 数据结构，确保跨 Isolate 安全
  final int x;
  final int y;
  final int width;
  final int height;
  final double confidence;

  MatchResult({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.confidence,
  });

  // 方便转换为 opencv 的 Rect
  cv.Rect get rect => cv.Rect(x, y, width, height);

  @override
  String toString() {
    return 'MatchResult(rect: ($x, $y, $width, $height), confidence: $confidence)';
  }
}

/// 预处理后的模板图像，包含原图灰度图和缩略灰度图
class ImageTemplate {
  final cv.Mat gray;
  final cv.Mat graySmall;
  final cv.Mat graySmallFilled; // 智能填充背景的缩略图 (无 Mask)
  final cv.Mat? mask;
  final cv.Mat? maskSmall;
  final double scale;
  final int originalWidth;
  final int originalHeight;

  ImageTemplate._({
    required this.gray,
    required this.graySmall,
    required this.graySmallFilled,
    this.mask,
    this.maskSmall,
    required this.scale,
    required this.originalWidth,
    required this.originalHeight,
  });

  /// 创建模板对象
  /// [bytes] 模板图像数据
  /// [scale] 缩放比例，默认为 0.5
  static ImageTemplate? create(Uint8List bytes, {double scale = 0.5}) {
    try {
      // 读取包含 Alpha 通道的原图
      final src = cv.imdecode(bytes, cv.IMREAD_UNCHANGED);
      if (src.isEmpty) return null;

      cv.Mat gray;
      cv.Mat? mask;

      // 检查通道数
      if (src.channels == 4) {
        // 分离通道
        final channels = cv.split(src);
        // Alpha 通道作为 Mask
        mask = channels[3];
        // 将 BGR/RGB 转换为灰度
        // 注意：imdecode 默认是 BGR 顺序 (OpenCV 习惯)
        // 这里的转换代码取决于 opencv_dart 的实现，通常 split 后前三个是 BGR
        // 但我们可以直接把 src (BGRA) 转为 Gray
        gray = cv.cvtColor(src, cv.COLOR_BGRA2GRAY);

        // 释放拆分出的通道 (mask 已经被引用，其他的释放)
        channels[0].dispose();
        channels[1].dispose();
        channels[2].dispose();
        // channels[3] is mask, keep it.
      } else {
        // 如果没有 Alpha，直接转灰度 (或者已经是灰度)
        if (src.channels == 3) {
          gray = cv.cvtColor(src, cv.COLOR_BGR2GRAY);
        } else {
          gray = src.clone(); // 已经是单通道
        }
      }

      // src 可以释放了，mask 和 gray 已经独立
      src.dispose();

      final width = gray.cols;
      final height = gray.rows;

      // 生成缩略图
      final smallWidth = (width * scale).toInt();
      final smallHeight = (height * scale).toInt();
      final graySmall = cv.resize(gray, (
        smallWidth,
        smallHeight,
      ), interpolation: cv.INTER_LINEAR);

      cv.Mat? maskSmall;
      if (mask != null) {
        maskSmall = cv.resize(mask, (
          smallWidth,
          smallHeight,
        ), interpolation: cv.INTER_NEAREST); // Mask 建议用最邻近插值保持边缘
      }

      // 生成智能填充的缩略图 (用于快速无 Mask 匹配)
      final graySmallFilled = maskSmall != null
          ? ImagePreprocessor.smartFillBackgroundFromGrayMask(
              graySmall,
              maskSmall,
            )
          : graySmall.clone();

      return ImageTemplate._(
        gray: gray,
        graySmall: graySmall,
        graySmallFilled: graySmallFilled,
        mask: mask,
        maskSmall: maskSmall,
        scale: scale,
        originalWidth: width,
        originalHeight: height,
      );
    } catch (e) {
      debugPrint('Error creating template: $e');
      return null;
    }
  }

  void dispose() {
    gray.dispose();
    graySmall.dispose();
    graySmallFilled.dispose();
    mask?.dispose();
    maskSmall?.dispose();
  }
}

class ImageMatchingService {
  /// 在源图像中查找模板图像（使用预处理模板）
  /// [sourceBytes] 源图像数据
  /// [template] 预处理后的模板对象
  /// [threshold] 匹配阈值，默认为 0.8
  /// [algorithm] 匹配算法，默认为 pyramidHybrid
  /// 返回匹配结果，如果没有找到匹配项则返回 null
  static MatchResult? matchTemplateWithPreload(
    Uint8List sourceBytes,
    ImageTemplate template, {
    double threshold = 0.8,
    MatchingAlgorithm algorithm = MatchingAlgorithm.pyramidHybrid,
  }) {
    cv.Mat? sourceGray;
    cv.Mat? sourceSmall;
    cv.Mat? resultSmall;
    cv.Mat? result;
    cv.Mat? roi;

    try {
      // 1. 源图像直接解码为灰度图
      sourceGray = cv.imdecode(sourceBytes, cv.IMREAD_GRAYSCALE);
      if (sourceGray.isEmpty) return null;

      // 检查图像尺寸
      if (sourceGray.rows < template.gray.rows ||
          sourceGray.cols < template.gray.cols) {
        return null;
      }

      // 根据算法分发逻辑
      if (algorithm == MatchingAlgorithm.directMasked ||
          algorithm == MatchingAlgorithm.directUnmasked) {
        // --- 单尺度直接匹配 ---
        result = cv.matchTemplate(
          sourceGray,
          template.gray,
          cv.TM_CCOEFF_NORMED,
          mask: algorithm == MatchingAlgorithm.directMasked
              ? template.mask
              : null,
        );

        final minMax = cv.minMaxLoc(result);
        final maxVal = minMax.$2;
        final maxLoc = minMax.$4;

        if (maxVal >= threshold) {
          return MatchResult(
            x: maxLoc.x,
            y: maxLoc.y,
            width: template.originalWidth,
            height: template.originalHeight,
            confidence: maxVal,
          );
        }
        return null;
      } else {
        // --- 金字塔匹配 (Hybrid / Masked) ---

        // 2. 粗匹配：将源图像缩小
        final smallWidth = (sourceGray.cols * template.scale).toInt();
        final smallHeight = (sourceGray.rows * template.scale).toInt();

        sourceSmall = cv.resize(sourceGray, (
          smallWidth,
          smallHeight,
        ), interpolation: cv.INTER_LINEAR);

        // 执行粗匹配
        if (algorithm == MatchingAlgorithm.pyramidHybrid) {
          // Hybrid: 使用 graySmallFilled (智能填充) + 无 Mask (启用 FFT)
          resultSmall = cv.matchTemplate(
            sourceSmall,
            template.graySmallFilled,
            cv.TM_CCOEFF_NORMED,
            // mask: null
          );
        } else {
          // PyramidMasked: 使用 graySmall + Mask
          resultSmall = cv.matchTemplate(
            sourceSmall,
            template.graySmall,
            cv.TM_CCOEFF_NORMED,
            mask: template.maskSmall,
          );
        }

        final minMaxSmall = cv.minMaxLoc(resultSmall!);
        final maxValSmall = minMaxSmall.$2;
        final maxLocSmall = minMaxSmall.$4;

        // 如果粗匹配置信度太低，直接返回失败（放宽一点阈值以防误判）
        if (maxValSmall < threshold * 0.7) {
          // 稍微放宽一点
          return null;
        }

        // 3. 精匹配：在原图上确定 ROI 区域
        // 将粗匹配坐标映射回原图
        final centerX = maxLocSmall.x / template.scale;
        final centerY = maxLocSmall.y / template.scale;

        // 定义 ROI 范围（比模板稍大一些，留出容错空间）
        // 搜索范围扩大一些
        final searchRange = (20 / template.scale).toInt();

        final roiX = (centerX - searchRange).toInt().clamp(
          0,
          sourceGray.cols - template.originalWidth,
        );
        final roiY = (centerY - searchRange).toInt().clamp(
          0,
          sourceGray.rows - template.originalHeight,
        );

        // 计算实际 ROI 宽高
        final roiW = (template.originalWidth + 2 * searchRange).clamp(
          0,
          sourceGray.cols - roiX,
        );
        final roiH = (template.originalHeight + 2 * searchRange).clamp(
          0,
          sourceGray.rows - roiY,
        );

        // 截取 ROI
        roi = sourceGray.region(cv.Rect(roiX, roiY, roiW, roiH));

        // 在 ROI 上进行精匹配 (始终带 Mask，保证最终精度)
        result = cv.matchTemplate(
          roi,
          template.gray,
          cv.TM_CCOEFF_NORMED,
          mask: template.mask,
        );

        final minMax = cv.minMaxLoc(result);
        final maxVal = minMax.$2;
        final maxLoc = minMax.$4;

        if (maxVal >= threshold) {
          // 最终坐标 = ROI 起始坐标 + ROI 内匹配坐标
          return MatchResult(
            x: roiX + maxLoc.x,
            y: roiY + maxLoc.y,
            width: template.originalWidth,
            height: template.originalHeight,
            confidence: maxVal,
          );
        }

        return null;
      }
    } catch (e) {
      debugPrint('Error matching template: $e');
      return null;
    } finally {
      // 释放中间变量
      sourceGray?.dispose();
      sourceSmall?.dispose();
      resultSmall?.dispose();
      result?.dispose();
      roi?.dispose();
    }
  }
}
