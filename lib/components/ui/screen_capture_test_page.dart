import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/image_matching_service.dart';
import '../../services/screen_capture_service.dart';
import '../../utils/platform_utils.dart';

import 'match_painter.dart';
import 'crop_painter.dart';

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
          setState(() {
            _rightImage = bytes;
          });
          _createTemplate(bytes);
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
        setState(() {
          _rightImage = bytes;
          _isCropping = false;
        });
        _createTemplate(bytes);
      }
    } catch (e) {
      debugPrint('Crop error: $e');
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
                                overflow: TextOverflow.ellipsis,
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
                  ),
                ),
              ],
            ),
          ),

          // 3. 图片处理工具栏 (新加)
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
                ElevatedButton.icon(
                  onPressed: _isCropping ? null : _startCropMode,
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
              if (onPickImage != null)
                TextButton.icon(
                  onPressed: onPickImage,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Select Image'),
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

                        // 如果是左侧且正在裁剪，使用 MouseRegion + GestureDetector
                        // 否则只是显示
                        Widget content = SizedBox(
                          width: constraints.maxWidth,
                          height: constraints.maxHeight,
                          child: CustomPaint(
                            painter: _isCropping && isLeft
                                ? null // 裁剪时使用 foregroundPainter 覆盖
                                : null,
                            foregroundPainter: _isCropping && isLeft
                                ? CropPainter(
                                    image: imageObj!,
                                    start: _cropStart,
                                    end: _cropEnd,
                                    currentPos: _currentMousePos,
                                    pixelData: _leftImagePixels,
                                  )
                                : (matchResult != null
                                      ? MatchPainter(
                                          matchResult: matchResult,
                                          imageObj: imageObj,
                                        )
                                      : null),
                            child: Image.memory(image, fit: BoxFit.contain),
                          ),
                        );

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
