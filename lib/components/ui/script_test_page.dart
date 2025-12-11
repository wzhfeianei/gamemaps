import 'dart:math';

import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
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
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        final t =
                            '/* 示例3：compareImages(路径+阈值) */\n(async () => {\n  const r = await compareImages(\'D:\\\\1.png\', \'D:\\\\2.png\', 0.85);\n  console.log(JSON.stringify(r));\n  return r.ok ? r.score : r.reason;\n})()';
                        await _editorKey.currentState?.setText(t);
                      },
                      child: const Text('示例：compareImages'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        final resTpl = await FilePicker.platform.pickFiles(
                          type: FileType.image,
                        );
                        final resTgt = await FilePicker.platform.pickFiles(
                          type: FileType.image,
                        );
                        final tpl = resTpl?.files.single.path;
                        final tgt = resTgt?.files.single.path;
                        print(tpl);
                        if (tpl != null && tgt != null) {
                          final r = await _engine.compareImagesFromPath(
                            tpl,
                            tgt,
                            0.85,
                          );
                          setState(() {
                            _result = jsonEncode(r);
                          });
                        }
                      },
                      child: const Text('本地对比'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        final prelude = [
                          '/* 类型声明（用于提示与高亮） */',
                          '/** @type {(a:number,b:number)=>number} */',
                          'function sum(a,b) { return 0; }',
                          '/** @type {(url:string)=>Promise<string>} */',
                          'async function httpGet(url) { return \"\"; }',
                          '/** @type {(templatePath:string,targetPath:string,minScore?:number)=>Promise<{ok:boolean,score:number,rect?:{x:number,y:number,w:number,h:number},reason?:string}>} */',
                          'async function compareImages(templatePath,targetPath,minScore) { return {ok:false,score:0}; }',
                          '',
                        ].join('\n');
                        final existing =
                            await _editorKey.currentState?.getText() ??
                            _defaultCode;
                        await _editorKey.currentState?.setText(
                          prelude + existing,
                        );
                      },
                      child: const Text('注入类型提示'),
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
