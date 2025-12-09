import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/image_matching_service.dart';
import '../../services/screen_capture_service.dart';
import '../../utils/platform_utils.dart';

import 'match_painter.dart';
import 'crop_painter.dart';
import 'draw_painter.dart';

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

  Future<void> _updateRightImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final pixelData = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );

    setState(() {
      _rightImage = bytes;
      _rightImageObj = frame.image;
      _rightImagePixels = pixelData;
      _isDrawing = false;
      _drawPoints.clear();
    });
    _createTemplate(bytes);
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
          await _updateRightImage(bytes);
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Template processed and ready')),
        );
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
    if (_leftImage == null || _template == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please capture screen and select image first'),
        ),
      );
      return;
    }

    setState(() {
      _isMatching = true;
      _matchResult = null;
      _matchDuration = null;
      _isCropping = false; // 退出裁剪模式
    });

    await Future.delayed(Duration.zero);

    final stopwatch = Stopwatch()..start();

    try {
      final result = ImageMatchingService.matchTemplateWithPreload(
        _leftImage!,
        _template!,
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
        await _updateRightImage(bytes); // 使用更新后的方法
        setState(() {
          _isCropping = false;
        });
      }
    } catch (e) {
      debugPrint('Crop error: $e');
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
      _drawPoints.clear();
      _currentMousePos = null;
    });
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

      // 绘制原图
      // canvas.drawImage(_rightImageObj!, Offset.zero, Paint());
      // 不，我们要抠图，所以是先 clip 只有画图

      // 计算 Path 的边界
      final bounds = path.getBounds();

      // 平移 Canvas，使 Path 的左上角对齐到 (0,0) ?
      // 或者保持原位，最后只取 bounds 区域

      canvas.clipPath(path);
      canvas.drawImage(_rightImageObj!, Offset.zero, Paint());

      final picture = recorder.endRecording();
      // 这里生成的大小还是原图大小，但是只有中间有内容。
      // 我们想要的是只保留图标部分（裁剪掉透明空白）。
      // 所以应该创建一个和 bounds 一样大的 canvas，然后平移绘制。

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
        await _updateRightImage(bytes);

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
                      onPressed:
                          (_leftImage != null &&
                              _template != null &&
                              !_isMatching)
                          ? _matchImages
                          : null,
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
                        // 取消/退出按钮 (仅在绘制模式下显示)
                        if (_isDrawing)
                          Tooltip(
                            message: 'Cancel Drawing',
                            child: IconButton(
                              onPressed: _toggleDrawMode,
                              icon: const Icon(Icons.close),
                              color: Colors.red,
                            ),
                          ),
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
            child: Row(
              children: [
                const Text(
                  'Tools: ',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 10),
                // 截图按钮
                ElevatedButton.icon(
                  onPressed: _isDrawing
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
                  const Spacer(),
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
                const Spacer(), // 占位
                if (_isDrawing)
                  const Text(
                    'Draw loop on right image to extract icon.',
                    style: TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),

          // 4. 底部信息栏
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12.0),
            color: Colors.grey[200],
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
                                (_isCropping && isLeft) ||
                                    (_isDrawing && !isLeft)
                                ? null // 交互模式下使用 foregroundPainter
                                : null,
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
                            child: Image.memory(image, fit: BoxFit.contain),
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
