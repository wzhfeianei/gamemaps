import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:opencv_dart/opencv_dart.dart' as cv;
import '../../services/image_matching_service.dart';
import '../../services/screen_capture_service.dart';
import '../../services/image_preprocessor.dart';
import '../../utils/platform_utils.dart';

import 'match_painter.dart';
import 'crop_painter.dart';
import 'draw_painter.dart';
import 'eraser_cursor_painter.dart';
import 'image_editor_painter.dart'; // 引入新的编辑器 Painter
import 'keep_color_preview_painter.dart';

class ScreenCaptureTestPage extends StatefulWidget {
  const ScreenCaptureTestPage({super.key});

  @override
  State<ScreenCaptureTestPage> createState() => _ScreenCaptureTestPageState();
}

class _ScreenCaptureTestPageState extends State<ScreenCaptureTestPage> {
  /// 左侧截图结果
  Uint8List? _leftImage;
  ui.Image? _leftImageObj;
  ByteData? _leftImagePixels; // RGBA 像素数据

  /// 右侧指定图片
  Uint8List? _rightImage;
  ui.Image? _rightImageObj; // 增加右侧图片对象
  ByteData? _rightImagePixels; // 增加右侧图片像素数据

  /// 运行中的窗口列表（仅 Windows）
  List<String> _windows = [];

  /// 选中的窗口名称
  String? _selectedWindow;

  /// 是否正在截图（全屏/窗口）
  bool _isCapturing = false;

  /// 匹配结果
  MatchResult? _matchResult;

  /// 是否正在匹配
  bool _isMatching = false;

  /// 是否正在连续截图
  bool _isContinuousCapturing = false;

  /// 匹配耗时
  Duration? _matchDuration;

  /// 预处理的模板
  ImageTemplate? _template;

  /// 裁剪相关状态
  bool _isCropping = false;
  Offset? _cropStart; // 图片坐标系
  Offset? _cropEnd; // 图片坐标系
  Offset? _currentMousePos; // 图片坐标系

  /// 绘制提取相关状态
  bool _isDrawing = false;
  final List<Offset> _drawPoints = [];
  bool _useMagneticLasso = false;

  /// 橡皮擦相关状态
  bool _isEraserMode = false;
  double _eraserSize = 20.0; // 默认半径
  double _eraserTolerance = 30.0; // 默认容差
  final ValueNotifier<Offset?> _mousePosNotifier = ValueNotifier(
    null,
  ); // 用于高性能光标更新
  final List<Offset> _eraserPathPoints = []; // 橡皮擦移动路径

  /// 保留色模式相关状态
  bool _isKeepColorMode = false;
  final List<Color> _keepColors = [];
  bool _isPreviewingKeep = false;
  ui.Image? _previewMaskImage;

  /// 匹配算法选择
  MatchingAlgorithm _selectedAlgorithm = MatchingAlgorithm.pyramidHybrid;

  /// 历史记录栈
  final List<Uint8List> _undoStack = [];
  final List<Uint8List> _redoStack = [];

  @override
  void initState() {
    super.initState();

    // Windows 平台加载窗口列表
    if (PlatformUtils.isWindows) {
      _loadWindows();
    }
  }

  @override
  void dispose() {
    _isContinuousCapturing = false; // 停止连续截图
    _template?.dispose();
    _mousePosNotifier.dispose();
    super.dispose();
  }

  /// 加载运行中的窗口列表（仅 Windows）
  Future<void> _loadWindows() async {
    final windows = await ScreenCaptureService.getRunningWindows();
    // Remove duplicate window titles
    final uniqueWindows = windows.toSet().toList();
    setState(() {
      _windows = uniqueWindows;
      if (uniqueWindows.isNotEmpty) {
        _selectedWindow = uniqueWindows.first;
      }
    });
  }

  Future<void> _updateLeftImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final pixelData = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );

    setState(() {
      _leftImage = bytes;
      _leftImageObj = frame.image;
      _leftImagePixels = pixelData;
      _matchResult = null; // 重置匹配结果
      _matchDuration = null; // 重置耗时
      // 如果正在裁剪，重置裁剪状态但保持模式（如果需要）
      // 这里假设重新截图后退出裁剪模式
      _isCropping = false;
      _cropStart = null;
      _cropEnd = null;
    });
  }

  Future<void> _updateRightImage(
    Uint8List bytes, {
    bool pushToUndo = false,
  }) async {
    if (pushToUndo && _rightImage != null) {
      _undoStack.add(_rightImage!);
      _redoStack.clear(); // 清空重做栈
    }

    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final pixelData = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );

    setState(() {
      _rightImage = bytes;
      _rightImageObj = frame.image;
      _rightImagePixels = pixelData;

      // 保持模式状态，不自动退出
      if (!_isEraserMode && !_isKeepColorMode) {
        _isDrawing = false;
        _drawPoints.clear();
      } else if (_isEraserMode) {
        _eraserPathPoints.clear(); // 清除橡皮擦路径
      }

      if (_isPreviewingKeep) {
        // 如果在预览时更新了图片（例如撤销），需要重新生成预览
        _updatePreviewMask();
      }
    });
    _createTemplate(bytes);
  }

  /// 撤销操作
  Future<void> _undo() async {
    if (_undoStack.isEmpty) return;

    // 保存当前状态到重做栈
    if (_rightImage != null) {
      _redoStack.add(_rightImage!);
    }

    final prevImage = _undoStack.removeLast();
    await _updateRightImage(prevImage, pushToUndo: false);
  }

  /// 重做操作
  Future<void> _redo() async {
    if (_redoStack.isEmpty) return;

    // 保存当前状态到撤销栈
    if (_rightImage != null) {
      _undoStack.add(_rightImage!);
    }

    final nextImage = _redoStack.removeLast();
    await _updateRightImage(nextImage, pushToUndo: false);
  }

  /// 截取当前屏幕
  Future<void> _captureScreen() async {
    setState(() {
      _isCapturing = true;
    });

    try {
      final image = await ScreenCaptureService.captureScreen();
      if (image != null) {
        await _updateLeftImage(image);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to capture screen')));
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  /// 截取指定窗口（仅 Windows）
  Future<void> _captureWindow() async {
    if (!PlatformUtils.isWindows || _selectedWindow == null) return;

    setState(() {
      _isCapturing = true;
    });

    try {
      final image = await ScreenCaptureService.captureWindow(_selectedWindow!);
      if (image != null) {
        await _updateLeftImage(image);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to capture window')));
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  /// 连续截图并对比（仅 Windows）
  Future<void> _continuousCaptureAndMatch() async {
    if (!PlatformUtils.isWindows || _selectedWindow == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a window first')),
      );
      return;
    }

    if (_template == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a template image first')),
      );
      return;
    }

    if (_isContinuousCapturing) {
      setState(() {
        _isContinuousCapturing = false;
      });
      return;
    }

    setState(() {
      _isContinuousCapturing = true;
    });

    while (_isContinuousCapturing && mounted) {
      final stopwatch = Stopwatch()..start();

      try {
        final image = await ScreenCaptureService.captureWindow(
          _selectedWindow!,
        );
        if (image != null) {
          final codec = await ui.instantiateImageCodec(image);
          final frame = await codec.getNextFrame();
          // 注意：连续截图中我们可能不需要实时获取 pixelData，除非需要实时放大镜
          // 为了性能暂不获取 pixelData

          if (!mounted || !_isContinuousCapturing) break;

          setState(() {
            _leftImage = image;
            _leftImageObj = frame.image;
          });

          await Future.delayed(Duration.zero);

          final matchStart = Stopwatch()..start();
          final result = ImageMatchingService.matchTemplateWithPreload(
            image,
            _template!,
            algorithm: _selectedAlgorithm,
          );
          matchStart.stop();

          if (!mounted || !_isContinuousCapturing) break;

          setState(() {
            _matchResult = result;
            _matchDuration = matchStart.elapsed;
          });
        }
      } catch (e) {
        debugPrint('Continuous capture error: $e');
        await Future.delayed(const Duration(seconds: 1));
      }

      stopwatch.stop();
      final elapsed = stopwatch.elapsedMilliseconds;
      final waitTime = 30 - elapsed;
      if (waitTime > 0) {
        await Future.delayed(Duration(milliseconds: waitTime.toInt()));
      } else {
        await Future.delayed(const Duration(milliseconds: 1));
      }
    }
  }

  /// 选择并显示左侧图片
  Future<void> _pickLeftImage() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
      );

      if (result != null) {
        if (result.files.single.bytes != null) {
          await _updateLeftImage(result.files.single.bytes!);
        } else if (result.files.single.path != null) {
          final file = File(result.files.single.path!);
          final bytes = await file.readAsBytes();
          await _updateLeftImage(bytes);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to pick image')));
      }
    }
  }

  /// 选择并显示指定图片（右侧）
  Future<void> _pickImage() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
      );

      if (result != null) {
        Uint8List? bytes;
        if (result.files.single.bytes != null) {
          bytes = result.files.single.bytes!;
        } else if (result.files.single.path != null) {
          final file = File(result.files.single.path!);
          bytes = await file.readAsBytes();
        }

        if (bytes != null) {
          await _updateRightImage(bytes, pushToUndo: true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to pick image')));
      }
    }
  }

  void _createTemplate(Uint8List bytes) {
    _template?.dispose();
    _template = null;

    final template = ImageTemplate.create(bytes);
    if (template != null) {
      _template = template;
      if (mounted) {
        // ScaffoldMessenger.of(context).showSnackBar(
        //   const SnackBar(content: Text('Template processed and ready')),
        // );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to create template')),
        );
      }
    }
  }

  /// 执行图像匹配
  Future<void> _matchImages() async {
    // 允许点击，内部具体判断是缺左图还是缺模板
    if (_leftImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please capture screen first')),
      );
      return;
    }

    if (_template == null) {
      // 尝试重新创建模板 (如果是刚刚更新了右图但创建失败)
      if (_rightImage != null) {
        _createTemplate(_rightImage!);
      }

      // 再次检查
      if (_template == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Template not ready. Please select/edit right image again.',
            ),
          ),
        );
        return;
      }
    }

    setState(() {
      _isMatching = true;
      _matchResult = null;
      _matchDuration = null;
      _isCropping = false; // 退出裁剪模式
      _isEraserMode = false;
      _isKeepColorMode = false; // 退出保留色模式
      _isPreviewingKeep = false;
      _isDrawing = false;
    });

    await Future.delayed(Duration.zero);

    final stopwatch = Stopwatch()..start();

    try {
      final result = ImageMatchingService.matchTemplateWithPreload(
        _leftImage!,
        _template!,
        algorithm: _selectedAlgorithm,
      );

      stopwatch.stop();

      setState(() {
        _matchResult = result;
        _matchDuration = stopwatch.elapsed;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error matching images: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isMatching = false;
        });
      }
    }
  }

  /// 启动裁剪模式
  void _startCropMode() {
    if (_leftImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please capture/select an image first')),
      );
      return;
    }
    setState(() {
      _isCropping = true;
      _cropStart = null;
      _cropEnd = null;
      _matchResult = null;
      _isDrawing = false;
      _isEraserMode = false;
      _isKeepColorMode = false;
      _isPreviewingKeep = false;
    });
  }

  /// 确认裁剪
  Future<void> _confirmCrop() async {
    if (_leftImageObj == null || _cropStart == null || _cropEnd == null) return;

    // 计算规范化的矩形
    final rect = Rect.fromPoints(_cropStart!, _cropEnd!);
    if (rect.width < 1 || rect.height < 1) return;

    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // 绘制子图
      canvas.drawImageRect(
        _leftImageObj!,
        rect,
        Rect.fromLTWH(0, 0, rect.width, rect.height),
        Paint(),
      );

      final picture = recorder.endRecording();
      final img = await picture.toImage(
        rect.width.toInt(),
        rect.height.toInt(),
      );
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        final bytes = byteData.buffer.asUint8List();
        await _updateRightImage(bytes, pushToUndo: true); // 使用更新后的方法
        setState(() {
          _isCropping = false;
        });
      }
    } catch (e) {
      debugPrint('Crop error: $e');
    }
  }

  /// 执行智能图像预处理
  Future<void> _performSmartPreprocess() async {
    if (_rightImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an image first')),
      );
      return;
    }

    try {
      // 1. 解码为 Mat
      final mat = cv.imdecode(_rightImage!, cv.IMREAD_UNCHANGED);
      if (mat.isEmpty) return;

      // 2. 调用预处理
      final processedMat = ImagePreprocessor.smartFillBackground(mat);

      // 3. 编码回 PNG
      // 注意：processedMat 是单通道灰度图
      final success = cv.imencode('.png', processedMat);

      // 释放资源
      mat.dispose();
      processedMat.dispose();

      if (success.$1) {
        // success.$2 是 Uint8List
        await _updateRightImage(success.$2, pushToUndo: true);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Smart preprocessing applied (Background Filled)'),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Smart preprocess error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error preprocessing image: $e')),
        );
      }
    }
  }

  /// 启动/停止绘制模式
  void _toggleDrawMode() {
    if (_rightImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an image first')),
      );
      return;
    }

    setState(() {
      _isDrawing = !_isDrawing;
      _isEraserMode = false; // 互斥
      _isKeepColorMode = false;
      _isPreviewingKeep = false;
      _drawPoints.clear();
      _currentMousePos = null;
    });
  }

  /// 启动/停止橡皮擦模式
  void _toggleEraserMode() {
    if (_rightImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an image first')),
      );
      return;
    }

    setState(() {
      _isEraserMode = !_isEraserMode;
      _isDrawing = false; // 互斥
      _isKeepColorMode = false;
      _isPreviewingKeep = false;
      _currentMousePos = null;
      _eraserPathPoints.clear();
    });
  }

  /// 启动/停止保留色模式
  void _toggleKeepColorMode() {
    if (_rightImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an image first')),
      );
      return;
    }

    setState(() {
      _isKeepColorMode = !_isKeepColorMode;
      _isEraserMode = false;
      _isDrawing = false;
      _isPreviewingKeep = false; // 退出模式时关闭预览
      _keepColors.clear();
      _previewMaskImage = null;
    });
  }

  /// 添加保留色
  void _addKeepColor(Offset pos) {
    if (_rightImageObj == null || _keepColors.length >= 5) return;

    final int cx = pos.dx.round();
    final int cy = pos.dy.round();
    if (cx < 0 ||
        cx >= _rightImageObj!.width ||
        cy < 0 ||
        cy >= _rightImageObj!.height)
      return;

    final color = _getPixel(cx, cy);

    // 避免重复添加 (简单判断)
    for (final c in _keepColors) {
      if (_colorDiff(c, color) < 5) return;
    }

    setState(() {
      _keepColors.add(color);
      // 如果正在预览，需要更新 Mask
      if (_isPreviewingKeep) {
        _updatePreviewMask();
      }
    });
  }

  /// 移除保留色
  void _removeKeepColor(Color color) {
    setState(() {
      _keepColors.remove(color);
      if (_isPreviewingKeep) {
        _updatePreviewMask();
      }
    });
  }

  /// 设置预览状态
  void _setPreviewKeep(bool active) {
    if (_keepColors.isEmpty) return;
    if (_isPreviewingKeep == active) return;

    setState(() {
      _isPreviewingKeep = active;
      if (_isPreviewingKeep) {
        _updatePreviewMask();
      } else {
        _previewMaskImage = null;
      }
    });
  }

  /// 切换预览状态
  void _togglePreviewKeep() {
    _setPreviewKeep(!_isPreviewingKeep);
  }

  /// 更新预览图像 (真实效果预览)
  Future<void> _updatePreviewMask() async {
    if (_rightImagePixels == null ||
        _rightImageObj == null ||
        _keepColors.isEmpty)
      return;

    final w = _rightImageObj!.width;
    final h = _rightImageObj!.height;
    final totalPixels = w * h;

    // 创建预览图像像素数据 (RGBA)
    // 复制原图像素，如果被剔除则设为透明
    final previewPixels = Uint8List(totalPixels * 4);

    // 阈值平方
    final double threshold = _eraserTolerance * 2.5;
    final double thresholdSq = threshold * threshold;

    for (int i = 0; i < totalPixels; i++) {
      final offset = i * 4;
      final int pr = _rightImagePixels!.getUint8(offset);
      final int pg = _rightImagePixels!.getUint8(offset + 1);
      final int pb = _rightImagePixels!.getUint8(offset + 2);
      final int pa = _rightImagePixels!.getUint8(offset + 3);

      if (pa == 0) {
        // 原图本来就是透明的
        previewPixels[offset] = 0;
        previewPixels[offset + 1] = 0;
        previewPixels[offset + 2] = 0;
        previewPixels[offset + 3] = 0;
        continue;
      }

      bool keep = false;
      for (final color in _keepColors) {
        final int dr = pr - color.red;
        final int dg = pg - color.green;
        final int db = pb - color.blue;
        final int distSq = dr * dr + dg * dg + db * db;

        if (distSq <= thresholdSq) {
          keep = true;
          break;
        }
      }

      if (keep) {
        // 保留区域：复制原像素
        previewPixels[offset] = pr;
        previewPixels[offset + 1] = pg;
        previewPixels[offset + 2] = pb;
        previewPixels[offset + 3] = pa;
      } else {
        // 剔除区域：设为透明
        previewPixels[offset] = 0;
        previewPixels[offset + 1] = 0;
        previewPixels[offset + 2] = 0;
        previewPixels[offset + 3] = 0;
      }
    }

    // 生成 Image
    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
      previewPixels,
    );
    final ui.ImageDescriptor descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: w,
      height: h,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();

    if (mounted && _isPreviewingKeep) {
      setState(() {
        _previewMaskImage = frame.image;
      });
    }
  }

  /// 执行多色保留操作
  Future<void> _performMultiColorKeep() async {
    if (_rightImagePixels == null ||
        _rightImageObj == null ||
        _keepColors.isEmpty)
      return;

    final w = _rightImageObj!.width;
    final h = _rightImageObj!.height;
    final totalPixels = w * h;

    final Uint8List newPixels = Uint8List.fromList(
      _rightImagePixels!.buffer.asUint8List(),
    );

    final double threshold = _eraserTolerance * 2.5;
    final double thresholdSq = threshold * threshold;
    bool changed = false;

    for (int i = 0; i < totalPixels; i++) {
      final offset = i * 4;
      final int pa = newPixels[offset + 3];
      if (pa == 0) continue;

      final int pr = newPixels[offset];
      final int pg = newPixels[offset + 1];
      final int pb = newPixels[offset + 2];

      bool keep = false;
      for (final color in _keepColors) {
        final int dr = pr - color.red;
        final int dg = pg - color.green;
        final int db = pb - color.blue;
        final int distSq = dr * dr + dg * dg + db * db;

        if (distSq <= thresholdSq) {
          keep = true;
          break;
        }
      }

      if (!keep) {
        newPixels[offset + 3] = 0; // 设为透明
        changed = true;
      }
    }

    if (changed) {
      await _updatePixels(newPixels, w, h);
      // 操作完成后退出模式
      setState(() {
        _isKeepColorMode = false;
        _keepColors.clear();
        _isPreviewingKeep = false;
        _previewMaskImage = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kept selected colors, removed others.'),
          ),
        );
      }
    }
  }

  /// 磁性套索：寻找吸附点
  Offset _findSnapPoint(Offset center, int radius) {
    if (_rightImageObj == null || _rightImagePixels == null) return center;

    int w = _rightImageObj!.width;
    int h = _rightImageObj!.height;
    int centerX = center.dx.round();
    int centerY = center.dy.round();

    // 如果超出范围，直接返回
    if (centerX < 0 || centerX >= w || centerY < 0 || centerY >= h)
      return center;

    double maxGradient = -1.0;
    Offset bestPoint = center;

    // 搜索周围
    for (int y = centerY - radius; y <= centerY + radius; y++) {
      for (int x = centerX - radius; x <= centerX + radius; x++) {
        if (x < 1 || x >= w - 1 || y < 1 || y >= h - 1) continue;

        // 计算梯度 (Sobel 简化版)
        // Gx = I(x+1, y) - I(x-1, y)
        // Gy = I(x, y+1) - I(x, y-1)
        // Gradient = |Gx| + |Gy|

        final cL = _getPixel(x - 1, y);
        final cR = _getPixel(x + 1, y);
        final cT = _getPixel(x, y - 1);
        final cB = _getPixel(x, y + 1);

        double gx = _colorDiff(cL, cR);
        double gy = _colorDiff(cT, cB);
        double gradient = gx + gy;

        // 距离中心的距离权重 (越近权重越高)
        double dist = math.sqrt(
          math.pow(x - centerX, 2) + math.pow(y - centerY, 2),
        );
        if (dist > radius) continue;

        // 稍微倾向于离鼠标近的点
        double score = gradient / (1 + dist * 0.1);

        if (score > maxGradient) {
          maxGradient = score;
          bestPoint = Offset(x.toDouble(), y.toDouble());
        }
      }
    }

    // 如果梯度太小，说明不是边缘，就不吸附
    if (maxGradient < 50) return center;

    return bestPoint;
  }

  Color _getPixel(int x, int y) {
    final offset = (y * _rightImageObj!.width + x) * 4;
    final r = _rightImagePixels!.getUint8(offset);
    final g = _rightImagePixels!.getUint8(offset + 1);
    final b = _rightImagePixels!.getUint8(offset + 2);
    // alpha 忽略
    return Color.fromARGB(255, r, g, b);
  }

  double _colorDiff(Color c1, Color c2) {
    return (c1.red - c2.red).abs() +
        (c1.green - c2.green).abs() +
        (c1.blue - c2.blue).abs().toDouble();
  }

  /// 提取图标
  Future<void> _extractIcon() async {
    if (_drawPoints.length < 3 || _rightImageObj == null) return;

    // 1. 路径平滑与构建
    final path = Path();
    path.moveTo(_drawPoints[0].dx, _drawPoints[0].dy);

    // 使用简单的二次贝塞尔曲线连接
    for (int i = 0; i < _drawPoints.length - 1; i++) {
      final p0 = _drawPoints[i];
      final p1 = _drawPoints[i + 1];
      // 取中点
      final mid = Offset((p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
      path.quadraticBezierTo(p0.dx, p0.dy, mid.dx, mid.dy);
    }
    path.lineTo(_drawPoints.last.dx, _drawPoints.last.dy);
    path.close();

    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // 计算 Path 的边界
      final bounds = path.getBounds();

      canvas.clipPath(path);
      canvas.drawImage(_rightImageObj!, Offset.zero, Paint());

      final picture = recorder.endRecording();

      final recorder2 = ui.PictureRecorder();
      final canvas2 = Canvas(recorder2);

      // 移动 path 到 (0,0)
      final shiftedPath = path.shift(-bounds.topLeft);
      canvas2.clipPath(shiftedPath);

      // 绘制图片，位置偏移 -bounds.topLeft
      canvas2.drawImage(_rightImageObj!, -bounds.topLeft, Paint());

      final picture2 = recorder2.endRecording();

      final img = await picture2.toImage(
        bounds.width.toInt(),
        bounds.height.toInt(),
      );
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        final bytes = byteData.buffer.asUint8List();
        await _updateRightImage(bytes, pushToUndo: true);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Icon extracted successfully')),
          );
        }
      }
    } catch (e) {
      debugPrint('Extract error: $e');
    }
  }

  /// 应用橡皮擦路径到像素数据 (拖拽结束时调用)
  Future<void> _applyEraserPathToPixels() async {
    if (_eraserPathPoints.isEmpty ||
        _rightImagePixels == null ||
        _rightImageObj == null)
      return;

    final int w = _rightImageObj!.width;
    final int h = _rightImageObj!.height;
    final int r = _eraserSize.round();
    final int rSq = r * r;

    // 复制像素数据
    final Uint8List newPixels = Uint8List.fromList(
      _rightImagePixels!.buffer.asUint8List(),
    );
    bool changed = false;

    // 遍历路径点，插值处理以防止快速移动产生间隙
    if (_eraserPathPoints.length == 1) {
      _eraseSquare(newPixels, _eraserPathPoints[0], w, h, r);
      changed = true;
    } else {
      for (int i = 0; i < _eraserPathPoints.length - 1; i++) {
        final p1 = _eraserPathPoints[i];
        final p2 = _eraserPathPoints[i + 1];

        // 计算两点距离
        final double dist = (p1 - p2).distance;
        // 步长取半径的 1/4 或 1 像素，取大者以平衡性能
        final double step = math.max(1.0, r / 4.0);

        double currentDist = 0.0;
        while (currentDist <= dist) {
          // 线性插值
          final double t = dist == 0 ? 0 : currentDist / dist;
          final Offset p = Offset.lerp(p1, p2, t)!;

          if (_eraseSquare(newPixels, p, w, h, r)) {
            changed = true;
          }
          currentDist += step;
        }
      }
      // 确保最后一个点被处理
      if (_eraseSquare(newPixels, _eraserPathPoints.last, w, h, r)) {
        changed = true;
      }
    }

    if (changed) {
      await _updatePixels(newPixels, w, h);
      setState(() {
        _eraserPathPoints.clear();
      });
    }
  }

  /// 辅助函数：擦除单个正方形区域
  bool _eraseSquare(Uint8List pixels, Offset center, int w, int h, int r) {
    bool changed = false;
    final int cx = center.dx.round();
    final int cy = center.dy.round();

    // 遍历正方形区域 [cx-r, cx+r]
    for (int y = cy - r; y <= cy + r; y++) {
      if (y < 0 || y >= h) continue;
      for (int x = cx - r; x <= cx + r; x++) {
        if (x < 0 || x >= w) continue;
        // 正方形不需要额外的距离判断

        final int offset = (y * w + x) * 4;
        if (pixels[offset + 3] != 0) {
          pixels[offset + 3] = 0; // Alpha = 0
          changed = true;
        }
      }
    }
    return changed;
  }

  /// 执行魔术擦除 (点击时调用：覆盖区域擦除 + 全局颜色替换)
  Future<void> _performMagicErase(Offset targetPos) async {
    if (_rightImagePixels == null || _rightImageObj == null) return;

    final int cx = targetPos.dx.round();
    final int cy = targetPos.dy.round();
    final int w = _rightImageObj!.width;
    final int h = _rightImageObj!.height;

    // 检查边界
    if (cx < 0 || cx >= w || cy < 0 || cy >= h) return;

    // 1. 获取基准色 (在擦除前获取)
    final baseColor = _getPixel(cx, cy);

    // 复制当前像素数据以便修改
    final Uint8List newPixels = Uint8List.fromList(
      _rightImagePixels!.buffer.asUint8List(),
    );

    bool changed = false;
    final int totalPixels = w * h;

    // 预计算基准色分量
    final int rBase = baseColor.red;
    final int gBase = baseColor.green;
    final int bBase = baseColor.blue;

    // 阈值平方
    final double threshold = _eraserTolerance * 2.5;
    final double thresholdSq = threshold * threshold;

    // 2. 擦除覆盖区域 (Square) - 优先执行
    final int r = _eraserSize.round();
    // final int rSq = r * r; // 不再需要平方
    for (int y = cy - r; y <= cy + r; y++) {
      if (y < 0 || y >= h) continue;
      for (int x = cx - r; x <= cx + r; x++) {
        if (x < 0 || x >= w) continue;
        // if ((x - cx) * (x - cx) + (y - cy) * (y - cy) > rSq) continue; // 移除圆判断

        final int offset = (y * w + x) * 4;
        if (newPixels[offset + 3] != 0) {
          newPixels[offset + 3] = 0;
          changed = true;
        }
      }
    }

    // 3. 全局颜色替换
    for (int i = 0; i < totalPixels; i++) {
      final int offset = i * 4;
      final int pa = newPixels[offset + 3];

      if (pa == 0) continue; // 已经是透明的

      final int pr = newPixels[offset];
      final int pg = newPixels[offset + 1];
      final int pb = newPixels[offset + 2];

      // 计算色差平方
      final int dr = pr - rBase;
      final int dg = pg - gBase;
      final int db = pb - bBase;
      final int distSq = dr * dr + dg * dg + db * db;

      if (distSq <= thresholdSq) {
        newPixels[offset + 3] = 0; // Alpha = 0
        changed = true;
      }
    }

    if (changed) {
      await _updatePixels(newPixels, w, h);
    }
  }

  Future<void> _updatePixels(Uint8List newPixels, int w, int h) async {
    // 从像素数据重新生成 Image
    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
      newPixels,
    );
    final ui.ImageDescriptor descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: w,
      height: h,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    final img = frame.image;

    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    if (byteData != null) {
      final bytes = byteData.buffer.asUint8List();
      await _updateRightImage(bytes, pushToUndo: true);
    }
  }

  /// 保存图片到本地
  Future<void> _saveImage(Uint8List imageBytes, String title) async {
    try {
      // 移除标题中的空格，用作默认文件名的一部分
      final safeTitle = title.replaceAll(' ', '_');
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save $title',
        fileName: '${safeTitle}_${DateTime.now().millisecondsSinceEpoch}.png',
        type: FileType.image,
        allowedExtensions: ['png', 'jpg', 'jpeg'],
      );

      if (outputFile != null) {
        // 确保扩展名
        if (!outputFile.toLowerCase().endsWith('.png') &&
            !outputFile.toLowerCase().endsWith('.jpg') &&
            !outputFile.toLowerCase().endsWith('.jpeg')) {
          outputFile += '.png';
        }

        final file = File(outputFile);
        await file.writeAsBytes(imageBytes);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Image saved to $outputFile')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save image: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Screen Capture Test')),
      body: Column(
        children: [
          // 1. 控制面板
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Control Panel',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: _captureScreen,
                      child: _isCapturing
                          ? const CircularProgressIndicator()
                          : const Text('Capture Current Screen'),
                    ),
                    const SizedBox(width: 12),
                    if (PlatformUtils.isWindows) ...[
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true, // 确保文本过长时自动截断而不是溢出
                          initialValue: _selectedWindow,
                          decoration: const InputDecoration(
                            labelText: 'Select Window',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 0,
                            ),
                          ),
                          items: _windows.map((window) {
                            return DropdownMenuItem(
                              value: window,
                              child: Text(
                                window,
                                overflow: TextOverflow.ellipsis, // 溢出显示省略号
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedWindow = value;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: _selectedWindow != null
                            ? _captureWindow
                            : null,
                        child: _isCapturing
                            ? const CircularProgressIndicator()
                            : const Text('Capture Window'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed:
                            (_selectedWindow != null && _template != null)
                            ? _continuousCaptureAndMatch
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isContinuousCapturing
                              ? Colors.red
                              : null,
                          foregroundColor: _isContinuousCapturing
                              ? Colors.white
                              : null,
                        ),
                        child: Text(
                          _isContinuousCapturing ? 'Stop Auto' : 'Auto Capture',
                        ),
                      ),
                    ],
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: !_isMatching ? _matchImages : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                      child: _isMatching
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Find Match'),
                    ),
                    const SizedBox(width: 12),
                    // 算法选择
                    SizedBox(
                      width: 180,
                      child: DropdownButtonFormField<MatchingAlgorithm>(
                        value: _selectedAlgorithm,
                        decoration: const InputDecoration(
                          labelText: 'Algorithm',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 0,
                          ),
                        ),
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(
                            value: MatchingAlgorithm.pyramidHybrid,
                            child: Text(
                              'Pyramid Hybrid (Fast+Mask)',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          DropdownMenuItem(
                            value: MatchingAlgorithm.pyramidMasked,
                            child: Text(
                              'Pyramid Masked (Robust)',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          DropdownMenuItem(
                            value: MatchingAlgorithm.directMasked,
                            child: Text(
                              'Direct Masked (Slow)',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          DropdownMenuItem(
                            value: MatchingAlgorithm.directUnmasked,
                            child: Text(
                              'Direct Unmasked (Fastest)',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _selectedAlgorithm = value;
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 2. 图片显示区域
          Expanded(
            child: Row(
              crossAxisAlignment:
                  CrossAxisAlignment.stretch, // Ensure full height for toolbar
              children: [
                // 左侧：截取的屏幕图像
                Expanded(
                  child: _buildImageDisplay(
                    title: 'Captured Screen',
                    image: _leftImage,
                    placeholder: 'No screen captured yet',
                    matchResult: _matchResult,
                    imageObj: _leftImageObj,
                    onPickImage: _pickLeftImage,
                    isLeft: true,
                  ),
                ),

                const VerticalDivider(width: 1, color: Colors.grey),

                // 右侧：指定图片
                Expanded(
                  child: _buildImageDisplay(
                    title: 'Specified Image',
                    image: _rightImage,
                    placeholder: 'No specified image',
                    onPickImage: _pickImage,
                    imageObj: _rightImageObj,
                  ),
                ),

                // 右侧工具栏（新增）
                Container(
                  width: 48, // 工具栏宽度
                  color: Colors.grey[200],
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(height: 16),
                        // 绘制/提取按钮
                        Tooltip(
                          message: 'Draw & Extract',
                          child: IconButton(
                            onPressed: _isCropping ? null : _toggleDrawMode,
                            icon: const Icon(Icons.draw),
                            color: _isDrawing ? Colors.orange : Colors.black54,
                            style: IconButton.styleFrom(
                              backgroundColor: _isDrawing
                                  ? Colors.orange.withOpacity(0.1)
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // 磁性套索开关 (仅在绘制模式下显示)
                        if (_isDrawing) ...[
                          Tooltip(
                            message: 'Magnetic Lasso',
                            child: IconButton(
                              onPressed: () {
                                setState(() {
                                  _useMagneticLasso = !_useMagneticLasso;
                                });
                              },
                              icon: Icon(
                                _useMagneticLasso
                                    ? Icons
                                          .leak_add // 使用 leak_add 作为磁性套索的近似图标
                                    : Icons.leak_remove,
                                color: _useMagneticLasso
                                    ? Colors.blue
                                    : Colors.black54,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // 智能预处理按钮
                        Tooltip(
                          message: 'Smart Preprocess (Fill Background)',
                          child: IconButton(
                            onPressed: _performSmartPreprocess,
                            icon: const Icon(Icons.auto_fix_high),
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(height: 16),

                        const Divider(indent: 8, endIndent: 8),

                        // 橡皮擦按钮菜单
                        PopupMenuButton<void>(
                          tooltip: 'Eraser Size',
                          icon: Icon(
                            Icons.cleaning_services,
                            color: _isEraserMode
                                ? Colors.purple
                                : Colors.black54,
                          ),
                          style: IconButton.styleFrom(
                            backgroundColor: _isEraserMode
                                ? Colors.purple.withOpacity(0.1)
                                : null,
                          ),
                          itemBuilder: (context) => [
                            PopupMenuItem<void>(
                              enabled: false,
                              child: StatefulBuilder(
                                builder: (context, setState) {
                                  return SizedBox(
                                    width: 200,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text('Size: ${_eraserSize.round()}'),
                                        Slider(
                                          value: _eraserSize,
                                          min: 1.0,
                                          max: 100.0,
                                          onChanged: (value) {
                                            setState(() {
                                              _eraserSize = value;
                                            });
                                            this.setState(() {
                                              _eraserSize = value;
                                              if (!_isEraserMode) {
                                                _toggleEraserMode();
                                              }
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                          onOpened: () {
                            if (!_isEraserMode) {
                              _toggleEraserMode();
                            }
                          },
                        ),

                        const SizedBox(height: 16),

                        // 保留色工具按钮
                        Tooltip(
                          message: 'Keep Colors (Filter)',
                          child: IconButton(
                            onPressed: _toggleKeepColorMode,
                            icon: const Icon(Icons.invert_colors),
                            color: _isKeepColorMode
                                ? Colors.green
                                : Colors.black54,
                            style: IconButton.styleFrom(
                              backgroundColor: _isKeepColorMode
                                  ? Colors.green.withOpacity(0.1)
                                  : null,
                            ),
                          ),
                        ),

                        // 保留色模式下的额外控件
                        if (_isKeepColorMode) ...[
                          const SizedBox(height: 8),
                          // 1. 已选颜色列表
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: _keepColors
                                .map(
                                  (c) => GestureDetector(
                                    onTap: () => _removeKeepColor(c),
                                    child: Container(
                                      width: 20,
                                      height: 20,
                                      decoration: BoxDecoration(
                                        color: c,
                                        border: Border.all(color: Colors.grey),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        size: 12,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                          const SizedBox(height: 8),

                          // 2. 预览按钮
                          Tooltip(
                            message: 'Preview (Hold to view)',
                            child: GestureDetector(
                              onTapDown: _keepColors.isNotEmpty
                                  ? (_) => _setPreviewKeep(true)
                                  : null,
                              onTapUp: _keepColors.isNotEmpty
                                  ? (_) => _setPreviewKeep(false)
                                  : null,
                              onTapCancel: _keepColors.isNotEmpty
                                  ? () => _setPreviewKeep(false)
                                  : null,
                              child: Container(
                                padding: const EdgeInsets.all(8.0),
                                decoration: BoxDecoration(
                                  color: _isPreviewingKeep
                                      ? Colors.blue.withOpacity(0.1)
                                      : Colors.transparent,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _isPreviewingKeep
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                  color: _keepColors.isNotEmpty
                                      ? (_isPreviewingKeep
                                            ? Colors.blue
                                            : Colors.black54)
                                      : Colors.grey,
                                ),
                              ),
                            ),
                          ),

                          // 3. 应用按钮
                          Tooltip(
                            message: 'Apply Filter',
                            child: IconButton(
                              onPressed: _keepColors.isNotEmpty
                                  ? _performMultiColorKeep
                                  : null,
                              icon: const Icon(Icons.check_circle),
                              color: _keepColors.isNotEmpty
                                  ? Colors.green
                                  : Colors.grey,
                            ),
                          ),
                        ],

                        if (_isEraserMode || _isKeepColorMode) ...[
                          const SizedBox(height: 8),
                          // 容差调整 (共享)
                          Tooltip(
                            message: 'Tolerance: ${_eraserTolerance.round()}',
                            child: IconButton(
                              icon: const Icon(Icons.tune, size: 20),
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Tolerance'),
                                    content: StatefulBuilder(
                                      builder: (ctx, setDialogState) {
                                        return Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text('${_eraserTolerance.round()}'),
                                            Slider(
                                              value: _eraserTolerance,
                                              min: 0,
                                              max: 100,
                                              onChanged: (v) {
                                                setDialogState(() {
                                                  _eraserTolerance = v;
                                                });
                                                setState(() {
                                                  _eraserTolerance = v;
                                                  // 如果正在预览保留色，实时更新
                                                  if (_isKeepColorMode &&
                                                      _isPreviewingKeep) {
                                                    _updatePreviewMask();
                                                  }
                                                });
                                              },
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx),
                                        child: const Text('Done'),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],

                        const SizedBox(height: 16),
                        // 撤销/重做
                        Tooltip(
                          message: 'Undo',
                          child: IconButton(
                            onPressed: _undoStack.isNotEmpty ? _undo : null,
                            icon: const Icon(Icons.undo),
                            color: _undoStack.isNotEmpty
                                ? Colors.black87
                                : Colors.grey,
                          ),
                        ),
                        Tooltip(
                          message: 'Redo',
                          child: IconButton(
                            onPressed: _redoStack.isNotEmpty ? _redo : null,
                            icon: const Icon(Icons.redo),
                            color: _redoStack.isNotEmpty
                                ? Colors.black87
                                : Colors.grey,
                          ),
                        ),

                        // 取消/退出按钮 (仅在绘制或橡皮擦模式下显示)
                        if (_isDrawing || _isEraserMode) ...[
                          const SizedBox(height: 16),
                          Tooltip(
                            message: 'Exit Mode',
                            child: IconButton(
                              onPressed: () {
                                setState(() {
                                  _isDrawing = false;
                                  _isEraserMode = false;
                                  _drawPoints.clear();
                                });
                              },
                              icon: const Icon(Icons.close),
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 3. 图片处理工具栏 (旧的底部工具栏)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.grey[100],
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Text(
                    'Tools: ',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 10),
                  // 截图按钮
                  ElevatedButton.icon(
                    onPressed: _isDrawing || _isEraserMode
                        ? null
                        : (_isCropping ? null : _startCropMode),
                    icon: const Icon(Icons.crop),
                    label: const Text('Screenshot / Crop'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isCropping ? Colors.green : null,
                      foregroundColor: _isCropping ? Colors.white : null,
                    ),
                  ),
                  if (_isCropping) ...[
                    const SizedBox(width: 10),
                    const Text(
                      'Drag on left image to crop. Release to confirm.',
                      style: TextStyle(color: Colors.green),
                    ),
                    const SizedBox(
                      width: 10,
                    ), // Add explicit spacing instead of Spacer
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _isCropping = false;
                          _cropStart = null;
                          _cropEnd = null;
                        });
                      },
                      child: const Text('Cancel'),
                    ),
                  ],
                  // 移除原来的 Draw 按钮，因为已经移动到右侧
                  // const Spacer(), // Spacer cannot be used inside ScrollView
                  const SizedBox(width: 20),
                  if (_isDrawing)
                    const Text(
                      'Draw loop on right image to extract icon.',
                      style: TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  if (_isEraserMode)
                    const Text(
                      'Click to magic erase similar colors.',
                      style: TextStyle(
                        color: Colors.purple,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),

          // 4. 底部信息栏
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12.0),
            color: Colors.grey[200],
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 20, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text(
                    _matchDuration != null
                        ? 'Time: ${_matchDuration!.inMilliseconds}ms'
                        : 'Time: --',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 20),
                  if (_matchResult != null) ...[
                    Text(
                      'Position: (${_matchResult!.x}, ${_matchResult!.y})',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 20),
                    Text(
                      'Size: ${_matchResult!.width}x${_matchResult!.height}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 20),
                    Text(
                      'Confidence: ${(_matchResult!.confidence * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ] else if (_matchDuration != null) ...[
                    const Text(
                      'Result: No match found',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                  ] else ...[
                    const Text(
                      'Ready to match',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建图像显示区域
  Widget _buildImageDisplay({
    required String title,
    required Uint8List? image,
    required String placeholder,
    VoidCallback? onPickImage,
    MatchResult? matchResult,
    ui.Image? imageObj,
    bool isLeft = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      color: Colors.grey[100],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (image != null)
                    IconButton(
                      icon: const Icon(Icons.save),
                      tooltip: 'Save Image',
                      onPressed: () => _saveImage(image, title),
                    ),
                  if (onPickImage != null)
                    TextButton.icon(
                      onPressed: onPickImage,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Select Image'),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
                color: Colors.white,
              ),
              clipBehavior: Clip.hardEdge,
              child: image != null
                  ? LayoutBuilder(
                      builder: (context, constraints) {
                        // 如果没有 imageObj，直接显示图片，不支持高级绘制功能
                        if (imageObj == null) {
                          return Image.memory(image, fit: BoxFit.contain);
                        }

                        final imgW = imageObj.width.toDouble();
                        final imgH = imageObj.height.toDouble();

                        // 计算 BoxFit.contain 的布局
                        final scaleX = constraints.maxWidth / imgW;
                        final scaleY = constraints.maxHeight / imgH;
                        final scale = scaleX < scaleY ? scaleX : scaleY;

                        final displayW = imgW * scale;
                        final displayH = imgH * scale;

                        // 偏移量
                        final dx = (constraints.maxWidth - displayW) / 2;
                        final dy = (constraints.maxHeight - displayH) / 2;

                        Offset toImage(Offset p) {
                          return Offset(
                            (p.dx - dx) / scale,
                            (p.dy - dy) / scale,
                          );
                        }

                        // 内容组件
                        Widget content = SizedBox(
                          width: constraints.maxWidth,
                          height: constraints.maxHeight,
                          child: CustomPaint(
                            painter:
                                (_isEraserMode && !isLeft && imageObj != null)
                                ? ImageEditorPainter(
                                    image: imageObj,
                                    eraserPath: List.of(_eraserPathPoints),
                                    eraserSize: _eraserSize,
                                    positionNotifier: _mousePosNotifier,
                                  )
                                : (_isKeepColorMode &&
                                          !isLeft &&
                                          imageObj != null
                                      ? KeepColorPreviewPainter(
                                          image: imageObj,
                                          maskImage: _previewMaskImage,
                                        )
                                      : null),
                            foregroundPainter: _isCropping && isLeft
                                ? CropPainter(
                                    image: imageObj,
                                    start: _cropStart,
                                    end: _cropEnd,
                                    currentPos: _currentMousePos,
                                    pixelData: _leftImagePixels,
                                  )
                                : (_isDrawing && !isLeft
                                      ? DrawPainter(
                                          image: imageObj,
                                          points: List.of(
                                            _drawPoints,
                                          ), // Pass a copy to ensure repaint
                                          currentPos: _currentMousePos,
                                          pixelData: _rightImagePixels,
                                        )
                                      : (matchResult != null
                                            ? MatchPainter(
                                                matchResult: matchResult,
                                                imageObj: imageObj,
                                              )
                                            : null)),
                            child: (_isEraserMode && !isLeft)
                                ? const SizedBox.expand()
                                : (_isPreviewingKeep && !isLeft)
                                ? const SizedBox.expand()
                                : Image.memory(image, fit: BoxFit.contain),
                          ),
                        );

                        // 交互逻辑
                        if (isLeft && _isCropping) {
                          return MouseRegion(
                            cursor: SystemMouseCursors.precise,
                            onHover: (event) {
                              setState(() {
                                _currentMousePos = toImage(event.localPosition);
                              });
                            },
                            child: GestureDetector(
                              onPanStart: (details) {
                                final p = toImage(details.localPosition);
                                setState(() {
                                  _cropStart = p;
                                  _cropEnd = p;
                                  _currentMousePos = p;
                                });
                              },
                              onPanUpdate: (details) {
                                final p = toImage(details.localPosition);
                                setState(() {
                                  _cropEnd = p;
                                  _currentMousePos = p;
                                });
                              },
                              onPanEnd: (details) {
                                _confirmCrop();
                              },
                              child: content,
                            ),
                          );
                        } else if (!isLeft && _isDrawing) {
                          // 右侧绘制逻辑
                          return MouseRegion(
                            cursor: SystemMouseCursors.precise,
                            onHover: (event) {
                              setState(() {
                                _currentMousePos = toImage(event.localPosition);
                              });
                            },
                            child: GestureDetector(
                              onPanStart: (details) {
                                final p = toImage(details.localPosition);
                                setState(() {
                                  _drawPoints.clear();
                                  _drawPoints.add(p);
                                  _currentMousePos = p;
                                });
                              },
                              onPanUpdate: (details) {
                                final p = toImage(details.localPosition);
                                Offset finalP = p;
                                if (_useMagneticLasso) {
                                  finalP = _findSnapPoint(p, 10); // 搜索半径 10
                                }

                                setState(() {
                                  _drawPoints.add(finalP);
                                  _currentMousePos = finalP; // 放大镜跟随实际点
                                });
                              },
                              onPanEnd: (details) {
                                _extractIcon();
                              },
                              child: content,
                            ),
                          );
                        } else if (!isLeft && _isKeepColorMode) {
                          // 保留色模式逻辑
                          return MouseRegion(
                            cursor: SystemMouseCursors.click, // 或者吸管图标
                            child: GestureDetector(
                              onTapUp: (details) {
                                final p = toImage(details.localPosition);
                                _addKeepColor(p);
                              },
                              onLongPressStart: (_) => _setPreviewKeep(true),
                              onLongPressEnd: (_) => _setPreviewKeep(false),
                              child: content,
                            ),
                          );
                        } else if (!isLeft && _isEraserMode) {
                          // 右侧橡皮擦逻辑
                          return MouseRegion(
                            cursor: SystemMouseCursors.none, // 隐藏系统光标，使用自定义光标
                            onHover: (event) {
                              // 使用 ValueNotifier 更新光标位置，避免 setState 导致的重绘卡顿
                              _mousePosNotifier.value = toImage(
                                event.localPosition,
                              );
                            },
                            child: GestureDetector(
                              onPanStart: (details) {
                                final p = toImage(details.localPosition);
                                setState(() {
                                  _eraserPathPoints.add(p);
                                });
                                _mousePosNotifier.value = p;
                              },
                              onPanUpdate: (details) {
                                final p = toImage(details.localPosition);
                                setState(() {
                                  _eraserPathPoints.add(p);
                                });
                                _mousePosNotifier.value = p;
                              },
                              onPanEnd: (details) {
                                _applyEraserPathToPixels();
                              },
                              onTapUp: (details) {
                                final p = toImage(details.localPosition);
                                _mousePosNotifier.value = p;
                                _performMagicErase(p);
                              },
                              child: content,
                            ),
                          );
                        } else {
                          return content;
                        }
                      },
                    )
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.image_not_supported,
                            size: 64,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            placeholder,
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
