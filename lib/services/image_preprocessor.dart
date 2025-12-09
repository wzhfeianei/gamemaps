import 'package:opencv_dart/opencv_dart.dart' as cv;

class ImagePreprocessor {
  /// 智能填充背景
  /// 将图像中的透明区域（Mask == 0）填充为非透明区域的平均灰度值
  /// 返回处理后的灰度图
  static cv.Mat smartFillBackground(cv.Mat src) {
    cv.Mat gray;
    cv.Mat mask;
    bool needDisposeGray = false;
    bool needDisposeMask = false;

    // 1. 准备灰度图和 Mask
    if (src.channels == 4) {
      // BGRA -> 分离通道
      final channels = cv.split(src);
      mask = channels[3]; // Alpha 通道
      // 转换为灰度
      gray = cv.cvtColor(src, cv.COLOR_BGRA2GRAY);

      // 释放不需要的通道
      channels[0].dispose();
      channels[1].dispose();
      channels[2].dispose();
      needDisposeMask = true;
      needDisposeGray = true;
    } else {
      // 如果不是 4 通道，假设没有透明度，直接转灰度返回
      if (src.channels == 3) {
        return cv.cvtColor(src, cv.COLOR_BGR2GRAY);
      }
      return src.clone();
    }

    try {
      return _fill(gray, mask);
    } finally {
      if (needDisposeMask) mask.dispose();
      if (needDisposeGray) gray.dispose();
    }
  }

  /// 使用给定的灰度图和 Mask 进行填充
  /// 返回新的填充后的灰度图
  static cv.Mat smartFillBackgroundFromGrayMask(cv.Mat gray, cv.Mat mask) {
    return _fill(gray, mask);
  }

  static cv.Mat _fill(cv.Mat gray, cv.Mat mask) {
    // 2. 计算前景平均灰度
    // mean 计算 mask 非零区域的平均值
    final scalar = cv.mean(gray, mask: mask);
    final meanVal = scalar.val1;

    // 3. 填充背景
    // 克隆一份灰度图用于修改
    final result = gray.clone();

    // 创建 mask 的反转版本 (背景为 255)
    // 由于 bitwise_not 可能未直接暴露，使用 255 - mask 替代
    final all255 = cv.Mat.zeros(mask.rows, mask.cols, mask.type);
    all255.setTo(cv.Scalar(255, 0, 0, 0));
    final invMask = cv.subtract(all255, mask);
    all255.dispose();

    // 将灰度图中背景区域设置为平均值
    result.setTo(cv.Scalar(meanVal, 0, 0, 0), mask: invMask);

    invMask.dispose();
    return result;
  }

  /// 图像二值化
  /// [src] 输入图像 (BGRA 或 BGR)
  /// [threshold] 阈值 (0-255)，如果 useOtsu 为 true 则忽略此值
  /// [useOtsu] 是否使用 Otsu 自动阈值
  /// [inverse] 是否反转二值化结果 (黑变白，白变黑)
  static cv.Mat binarizeImage(
    cv.Mat src, {
    double threshold = 127,
    bool useOtsu = false,
    bool inverse = false,
  }) {
    cv.Mat gray;
    cv.Mat? alphaMask;

    // 1. 转灰度并提取 Alpha
    if (src.channels == 4) {
      final channels = cv.split(src);
      alphaMask = channels[3];
      gray = cv.cvtColor(src, cv.COLOR_BGRA2GRAY);
      channels[0].dispose();
      channels[1].dispose();
      channels[2].dispose();
    } else {
      if (src.channels == 3) {
        gray = cv.cvtColor(src, cv.COLOR_BGR2GRAY);
      } else {
        gray = src.clone();
      }
    }

    try {
      // 2. 处理 Alpha 通道：将透明区域设为黑色 (0)
      if (alphaMask != null) {
        // 创建反向 Mask (透明区域为 255)
        final all255 = cv.Mat.zeros(
          alphaMask.rows,
          alphaMask.cols,
          alphaMask.type,
        );
        all255.setTo(cv.Scalar(255, 0, 0, 0));
        final invAlpha = cv.subtract(all255, alphaMask);
        all255.dispose();

        // 将透明区域设为黑 (0)
        // 注意：这里假设背景是黑色的。如果希望二值化时忽略背景，这步很关键。
        gray.setTo(cv.Scalar(0, 0, 0, 0), mask: invAlpha);
        invAlpha.dispose();
      }

      // 3. 应用二值化
      int type = inverse ? cv.THRESH_BINARY_INV : cv.THRESH_BINARY;
      if (useOtsu) {
        type |= cv.THRESH_OTSU;
      }

      final result = cv.threshold(gray, threshold, 255, type);

      // result.$1 是计算出的阈值 (如果用了 Otsu)，result.$2 是图像
      // 我们只需要图像
      return result.$2;
    } finally {
      gray.dispose();
      alphaMask?.dispose();
    }
  }
}
