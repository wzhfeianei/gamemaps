import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/image_matching_service.dart';
import '../../services/screen_capture_service.dart';
import '../../utils/platform_utils.dart';

import 'match_painter.dart';

class ScreenCaptureTestPage extends StatefulWidget {
  const ScreenCaptureTestPage({super.key});

  @override
  State<ScreenCaptureTestPage> createState() => _ScreenCaptureTestPageState();
}

class _ScreenCaptureTestPageState extends State<ScreenCaptureTestPage> {
  /// 左侧截图结果
  Uint8List? _leftImage;

  /// 右侧指定图片（这里使用一个默认的 Flutter 图标）
  Uint8List? _rightImage;

  /// 运行中的窗口列表（仅 Windows）
  List<String> _windows = [];

  /// 选中的窗口名称
  String? _selectedWindow;

  /// 是否正在截图
  bool _isCapturing = false;

  /// 匹配结果
  MatchResult? _matchResult;

  /// 是否正在匹配
  bool _isMatching = false;

  /// 匹配耗时
  Duration? _matchDuration;

  /// 左侧图片原始尺寸
  ui.Image? _leftImageObj;

  /// 预处理的模板
  ImageTemplate? _template;

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
    setState(() {
      _leftImage = bytes;
      _leftImageObj = frame.image;
      _matchResult = null; // 重置匹配结果
      _matchDuration = null; // 重置耗时
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

  /// 选择并显示指定图片
  Future<void> _pickImage() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
      );

      if (result != null) {
        if (result.files.single.bytes != null) {
          final bytes = result.files.single.bytes!;
          setState(() {
            _rightImage = bytes;
          });
          _createTemplate(bytes);
        } else if (result.files.single.path != null) {
          final file = File(result.files.single.path!);
          final bytes = await file.readAsBytes();
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

  /// 创建匹配模板
  void _createTemplate(Uint8List bytes) {
    // 释放旧模板
    _template?.dispose();
    _template = null;

    // 创建新模板
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
    });

    // 延时一帧以确保 UI 显示 Loading 状态
    await Future.delayed(Duration.zero);

    final stopwatch = Stopwatch()..start();

    try {
      // 在主线程直接执行，利用零拷贝优势
      final result = ImageMatchingService.matchTemplateWithPreload(
        _leftImage!,
        _template!,
      );

      stopwatch.stop();

      setState(() {
        _matchResult = result;
        _matchDuration = stopwatch.elapsed;
      });

      if (result == null && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No match found')));
      }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Screen Capture Test')),
      body: Column(
        children: [
          // 控制按钮区域
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

          // 主要内容区域：左右分栏
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
                    matchDuration: _matchDuration,
                    imageObj: _leftImageObj,
                  ),
                ),

                // 分隔线
                const VerticalDivider(width: 1, color: Colors.grey),

                // 右侧：指定图片
                Expanded(
                  child: _buildImageDisplay(
                    title: 'Specified Image',
                    image: _rightImage,
                    placeholder: 'No specified image',
                    // 这里可以添加加载指定图片的逻辑
                    onPickImage: _pickImage,
                  ),
                ),
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
    Duration? matchDuration,
    ui.Image? imageObj,
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (matchResult != null && matchDuration != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        'Time: ${matchDuration.inMilliseconds}ms\nPos: (${matchResult.x}, ${matchResult.y}) Size: ${matchResult.width}x${matchResult.height}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.blue,
                        ),
                      ),
                    ),
                ],
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
              child: image != null
                  ? LayoutBuilder(
                      builder: (context, constraints) {
                        return CustomPaint(
                          foregroundPainter: matchResult != null
                              ? MatchPainter(
                                  matchResult: matchResult,
                                  imageObj: imageObj,
                                )
                              : null,
                          child: SizedBox(
                            width: constraints.maxWidth,
                            height: constraints.maxHeight,
                            child: Image.memory(image, fit: BoxFit.contain),
                          ),
                        );
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
