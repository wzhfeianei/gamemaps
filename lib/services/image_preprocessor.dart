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
}
