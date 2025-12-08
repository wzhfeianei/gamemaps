/// 窗口信息模型
class WindowInfo {
  /// 窗口标题
  final String title;
  
  /// 窗口句柄（仅 Windows）
  final int? handle;
  
  /// 窗口可见性
  final bool isVisible;
  
  /// 窗口是否为顶层窗口
  final bool isTopLevel;

  WindowInfo({
    required this.title,
    this.handle,
    this.isVisible = true,
    this.isTopLevel = true,
  });

  factory WindowInfo.fromJson(Map<String, dynamic> json) {
    return WindowInfo(
      title: json['title'] as String,
      handle: json['handle'] as int?,
      isVisible: json['isVisible'] as bool? ?? true,
      isTopLevel: json['isTopLevel'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'handle': handle,
      'isVisible': isVisible,
      'isTopLevel': isTopLevel,
    };
  }

  @override
  String toString() {
    return 'WindowInfo(title: \$title, handle: \$handle, isVisible: \$isVisible, isTopLevel: \$isTopLevel)';
  }
}
