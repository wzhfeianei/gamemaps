import 'dart:io';
import 'package:flutter/foundation.dart';

/// 平台工具类
class PlatformUtils {
  /// 是否为 Windows 平台
  static bool get isWindows {
    return Platform.isWindows;
  }

  /// 是否为 Android 平台
  static bool get isAndroid {
    return Platform.isAndroid;
  }

  /// 是否为 iOS 平台
  static bool get isIOS {
    return Platform.isIOS;
  }

  /// 是否为 macOS 平台
  static bool get isMacOS {
    return Platform.isMacOS;
  }

  /// 是否为 Linux 平台
  static bool get isLinux {
    return Platform.isLinux;
  }

  /// 是否为 Web 平台
  static bool get isWeb {
    return kIsWeb;
  }

  /// 是否为桌面平台
  static bool get isDesktop {
    return isWindows || isMacOS || isLinux;
  }

  /// 是否为移动平台
  static bool get isMobile {
    return isAndroid || isIOS;
  }

  /// 获取平台名称
  static String get platformName {
    if (isWindows) return 'Windows';
    if (isAndroid) return 'Android';
    if (isIOS) return 'iOS';
    if (isMacOS) return 'macOS';
    if (isLinux) return 'Linux';
    if (isWeb) return 'Web';
    return 'Unknown';
  }

  /// 是否支持窗口截图功能
  static bool get supportsWindowCapture {
    return isWindows;
  }

  /// 是否支持屏幕截图功能
  static bool get supportsScreenCapture {
    return isWindows || isAndroid || isIOS;
  }
}
