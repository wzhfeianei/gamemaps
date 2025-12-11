import 'package:flutter/material.dart';
import 'package:flutter_monaco/flutter_monaco.dart';

class ScriptEditor extends StatefulWidget {
  final String initialCode;
  final List<String> injectedMethods;

  const ScriptEditor({
    super.key,
    required this.initialCode,
    required this.injectedMethods,
  });

  @override
  State<ScriptEditor> createState() => ScriptEditorState();
}

class ScriptEditorState extends State<ScriptEditor> {
  MonacoController? _controller;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  Future<void> _initController() async {
    _controller = await MonacoController.create(
      options: const EditorOptions(
        language: MonacoLanguage.javascript,
        theme: MonacoTheme.vsDark,
      ),
    );
    await _controller!.setValue(widget.initialCode);
    setState(() {});
  }

  // TODO: 注册补全与类型声明（使用 flutter_monaco 的类型安全 API）

  Future<String> getText() async {
    final c = _controller;
    if (c == null) return widget.initialCode;
    final v = await c.getValue();
    return v;
  }

  Future<void> setText(String text) async {
    final c = _controller;
    if (c == null) return;
    await c.setValue(text);
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return MonacoEditor(controller: _controller!, showStatusBar: true);
  }
}
