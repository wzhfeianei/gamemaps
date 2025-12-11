import 'package:flutter/material.dart';
import 'dart:convert';
import '../../services/script_engine_service.dart';
import 'widgets/script_editor.dart';

class ScriptTestPage extends StatefulWidget {
  const ScriptTestPage({super.key});

  @override
  State<ScriptTestPage> createState() => _ScriptTestPageState();
}

class _ScriptTestPageState extends State<ScriptTestPage> {
  final _engine = ScriptEngineService();
  final List<String> _injectedMethods = ['sum', 'httpGet'];
  String _result = '';
  final String _defaultCode =
      '/* 示例1：同步函数 */\n(async () => {\n  const r = sum(2, 3);\n  console.log(r);\n  return r;\n})()';
  final _editorKey = GlobalKey<ScriptEditorState>();

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    await _engine.init();
    await _engine.injectFunction('sum', (int a, int b) => a + b);
    await _engine.injectFunction('httpGet', (String url) => url);
  }

  Future<void> _run() async {
    final code =
        await (_editorKey.currentState?.getText() ??
            Future.value(_defaultCode));
    final res = await _engine.evaluate(code);
    String display;
    try {
      final obj = jsonDecode(res);
      if (obj is Map && obj['ok'] == true) {
        final logs = (obj['logs'] is List)
            ? (obj['logs'] as List).join('\n')
            : '';
        final resultStr = obj['result']?.toString() ?? '';
        display = logs.isNotEmpty ? '$resultStr\n$logs' : resultStr;
      } else if (obj is Map && obj['ok'] == false) {
        final err = obj['error']?.toString() ?? 'Error';
        final stack = obj['stack']?.toString();
        final logs = (obj['logs'] is List)
            ? (obj['logs'] as List).join('\n')
            : '';
        display = [
          err,
          if (stack != null) stack,
          if (logs.isNotEmpty) logs,
        ].join('\n');
      } else {
        display = res.toString();
      }
    } catch (_) {
      display = res.toString();
    }
    setState(() {
      _result = display;
    });
  }

  @override
  void dispose() {
    _engine.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('脚本测试页面')),
      body: Column(
        children: [
          Expanded(
            child: ScriptEditor(
              key: _editorKey,
              initialCode: _defaultCode,
              injectedMethods: _injectedMethods,
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ElevatedButton(onPressed: _run, child: const Text('运行')),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () async {
                        final t =
                            '/* 示例1：同步函数 */\n(async () => {\n  const r = sum(2, 3);\n  console.log(r);\n  return r;\n})()';
                        await _editorKey.currentState?.setText(t);
                      },
                      child: const Text('示例：sum'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        final t =
                            '/* 示例2：httpGet */\n(async () => {\n  const txt = await httpGet(\'https://jsonplaceholder.typicode.com/todos/1\');\n  console.log(txt);\n  return txt;\n})()';
                        await _editorKey.currentState?.setText(t);
                      },
                      child: const Text('示例：httpGet'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(_result, maxLines: 6, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
