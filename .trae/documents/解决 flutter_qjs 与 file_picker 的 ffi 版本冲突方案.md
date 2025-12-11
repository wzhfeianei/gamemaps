## 目标
- 替换 JS 引擎为 `flutter_js`，解决与 `file_picker 10.x (ffi 2.x)` 的版本冲突，同时保持现有“脚本测试页面”与 Monaco 编辑器功能不变。

## 变更范围
- 依赖：移除 `flutter_qjs`，新增 `flutter_js`。
- 服务层：重写 `ScriptEngineService`，以 `JavascriptRuntime` 提供 `init/injectFunction/evaluate/close` 同步接口。
- 页面层：`ScriptTestPage` 保持调用不变，仅替换底层服务实现；编辑器组件无需改动。

## 实施步骤
1. 依赖调整：
   - 从 `pubspec.yaml` 删除 `flutter_qjs`，添加 `flutter_js`。
   - 保持 `file_picker: ^10.x` 与 `flutter_monaco: ^1.x` 不变。
2. 引擎封装：
   - 在 `lib/services/script_engine_service.dart` 中将实现改为：
     - `init()`：`flutterJs = getJavascriptRuntime();`
     - `injectFunction(name, fn)`：通过 `onMessage`/桥接方法暴露 Dart 函数到 JS（或 `setGlobal` 形式，参考文档示例）；
     - `evaluate(code)`：`flutterJs.evaluate(code, sourceUrl: 'script.js')`，支持 Promise；
     - `close()`：销毁 runtime（如需）。
3. 兼容性验证：
   - 在“脚本测试页面”保留默认示例 `sum(2,3)`，验证注入与运行；
   - 验证连续运行与错误消息显示；
   - Windows 环境测试与 `file_picker` 打开/保存流程仍正常。

## 风险与缓解
- `flutter_js` 的函数注入方式与 `flutter_qjs` 不完全一致：通过统一服务接口屏蔽差异；如需更强注入（异步/返回值），补充桥接代码并在编辑器侧保留 d.ts 类型声明。
- 桥接 API 选择：优先使用官方 `onMessage` 与 `xhr/fetch`能力；如需更贴近原始函数注入，采用官方示例中将 Dart 函数设为全局对象的方式。

## 验收点
- 依赖冲突消除；
- “脚本测试页面”可运行示例，注入方法补全/高亮正常；
- 文件选择与保存功能在 Windows 下工作正常。

确认后我将按上述步骤替换实现并完成验证。