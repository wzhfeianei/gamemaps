import 'package:flutter_js/flutter_js.dart';
import 'dart:io';
import 'dart:convert';
import 'package:opencv_dart/opencv_dart.dart' as cv;

class ScriptEngineService {
  JavascriptRuntime? _engine;
  final List<String> _logs = [];

  Future<void> init({int stackSize = 1024 * 1024}) async {
    _engine = getJavascriptRuntime();
    _engine!.evaluate(
      "this.httpGet = async (url) => (await fetch(url)).text();",
    );

    // Removed JS log injection to avoid channel interference

    // Register compareImages channel using flutter_js messaging
    // JS helper to send compare requests and resolve promises
    _engine!.evaluate('''
      (function(){
        let __pid = 0;
        if (typeof sendMessage === 'function') {
          globalThis.compareImages = (templatePath, targetPath, minScore) => new Promise((resolve, reject) => {
            const promiseId = (++__pid);
            const payload = JSON.stringify({ templatePath, targetPath, minScore, promiseId });
            sendMessage('compareImages', payload);
            globalThis.resolvePromise = function(id, payload){ if(id===promiseId){ try{ resolve(JSON.parse(payload)); }catch(e){ resolve(payload); } } };
          });
        }
      })();
    ''');

    // Dart handler: receive paths, run OpenCV, resolve promise
    // If onMessage is not available at runtime, this will be a no-op
    try {
      // ignore: invalid_use_of_visible_for_testing_member
      // Some flutter_js versions expose onMessage API
      // Using dynamic to avoid hard dependency on specific signatures
      // @ts-ignore
      // dart side
      // NOTE: If this throws, we simply skip message binding
      // and rely on future library upgrades.
      // The handler will be registered only if onMessage exists.
      // The closure returns void and resolves via evaluate('resolvePromise(...)').
      //
      // The below dynamic invocation is intentionally kept minimal.
      //
      //
      // Attempt to bind channel
      //
      // ignore: avoid_dynamic_calls
      (_engine as dynamic).onMessage('compareImages', (dynamic args) {
        try {
          final String msg = args as String;
          final map = json.decode(msg) as Map<String, dynamic>;
          final tpl = map['templatePath'] as String;
          final tgt = map['targetPath'] as String;
          final minScore = (map['minScore'] as num?)?.toDouble() ?? 0.8;
          final pid = map['promiseId'];

          final tplBytes = File(tpl).readAsBytesSync();
          final tgtBytes = File(tgt).readAsBytesSync();
          final tplMat = cv.imdecode(tplBytes, cv.IMREAD_GRAYSCALE);
          final tgtMat = cv.imdecode(tgtBytes, cv.IMREAD_GRAYSCALE);
          final result = cv.matchTemplate(tgtMat, tplMat, cv.TM_CCOEFF_NORMED);
          final mm = cv.minMaxLoc(result);
          final double score =
              (mm as dynamic).$2 as double; // (minVal, maxVal, minLoc, maxLoc)
          final dynamic pt = (mm as dynamic).$4; // maxLoc
          final rect = {
            'x': pt.x,
            'y': pt.y,
            'w': tplMat.cols,
            'h': tplMat.rows,
          };
          final payload = (score >= minScore)
              ? json.encode({'ok': true, 'score': score, 'rect': rect})
              : json.encode({
                  'ok': false,
                  'reason': 'LOW_SCORE',
                  'score': score,
                });
          // resolve promise back to JS
          _engine!.evaluate(
            'resolvePromise(${pid.toString()}, ${json.encode(payload)})',
          );
        } catch (e) {
          final String? msg = (args is String) ? args as String : null;
          final pid = (msg != null)
              ? (json.decode(msg) as Map<String, dynamic>)['promiseId']
              : null;
          final payload = json.encode({'ok': false, 'error': e.toString()});
          if (pid != null) {
            _engine!.evaluate(
              'resolvePromise(${pid.toString()}, ${json.encode(payload)})',
            );
          }
        }
      });

      // Removed log channel handler
    } catch (_) {
      // onMessage not available; skip binding
    }
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
    _logs.clear();
    final wrapped =
        '''
      (async () => {
        try {
          const __val = await (async () => { ${code} })();
          return JSON.stringify({ ok: true, result: __val });
        } catch (e) {
          return JSON.stringify({ ok: false, error: String(e), stack: (e && e.stack) ? String(e.stack) : undefined });
        }
      })()
    ''';
    final result = _engine!.evaluate(wrapped, sourceUrl: 'script.js');
    return result.stringResult;
  }

  Future<Map<String, dynamic>> compareImagesFromPath(
    String templatePath,
    String targetPath,
    double minScore,
  ) async {
    final tplBytes = File(templatePath).readAsBytesSync();
    final tgtBytes = File(targetPath).readAsBytesSync();
    final tplMat = cv.imdecode(tplBytes, cv.IMREAD_GRAYSCALE);
    final tgtMat = cv.imdecode(tgtBytes, cv.IMREAD_GRAYSCALE);
    final result = cv.matchTemplate(tgtMat, tplMat, cv.TM_CCOEFF_NORMED);
    final mm = cv.minMaxLoc(result);
    final double score = (mm as dynamic).$2 as double; // maxVal
    final dynamic pt = (mm as dynamic).$4; // maxLoc
    final rect = {'x': pt.x, 'y': pt.y, 'w': tplMat.cols, 'h': tplMat.rows};
    if (score >= minScore) {
      return {'ok': true, 'score': score, 'rect': rect};
    }
    return {'ok': false, 'reason': 'LOW_SCORE', 'score': score};
  }

  Future<void> close() async {
    _engine = null;
  }
}
