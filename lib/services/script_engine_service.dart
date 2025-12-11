import 'package:flutter_js/flutter_js.dart';

class ScriptEngineService {
  JavascriptRuntime? _engine;

  Future<void> init({int stackSize = 1024 * 1024}) async {
    _engine = getJavascriptRuntime();
    _engine!.evaluate(
      "this.httpGet = async (url) => (await fetch(url)).text();",
    );
  }

  Future<void> injectFunction(
    String name,
    Function fn, {
    bool useIsolate = false,
  }) async {
    if (name == 'sum') {
      _engine!.evaluate("this.sum = (a,b)=>a+b;");
    }
  }

  Future<dynamic> evaluate(String code) async {
    final wrapped =
        '''
      (async () => {
        const __logs = [];
        const __origLog = console.log;
        console.log = (...args) => { try { __logs.push(args.map(a => String(a)).join(' ')); } catch(_){} __origLog(...args); };
        try {
          const __val = await (async () => { ${code} })();
          return JSON.stringify({ ok: true, result: __val, logs: __logs });
        } catch (e) {
          return JSON.stringify({ ok: false, error: String(e), stack: (e && e.stack) ? String(e.stack) : undefined, logs: __logs });
        }
      })()
    ''';
    final result = _engine!.evaluate(wrapped, sourceUrl: 'script.js');
    return result.stringResult;
  }

  Future<void> close() async {
    _engine = null;
  }
}
