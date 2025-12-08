import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

class ScreenCaptureService {
  static const MethodChannel _channel = MethodChannel('com.gamemaps/screen_capture');

  /// 截取当前屏幕
  static Future<Uint8List?> captureScreen() async {
    try {
      final result = await _channel.invokeMethod<Uint8List>('captureScreen');
      return result;
    } on PlatformException catch (e) {
      print('Failed to capture screen: \$e');
      return null;
    }
  }

  /// Windows 平台：截取指定名称的窗口
  static Future<Uint8List?> captureWindow(String windowName) async {
    try {
      final result = await _channel.invokeMethod<Uint8List>(
        'captureWindow',
        {'windowName': windowName},
      );
      return result;
    } on PlatformException catch (e) {
      print('Failed to capture window: \$e');
      return null;
    }
  }

  /// Windows 平台：获取当前运行的窗口列表
  static Future<List<String>> getRunningWindows() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('getRunningWindows');
      return result?.cast<String>() ?? [];
    } on PlatformException catch (e) {
      print('Failed to get running windows: \$e');
      return [];
    }
  }
}
