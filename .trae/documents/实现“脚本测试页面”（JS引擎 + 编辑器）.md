## 目标与约束

- 面向后续多页面扩展，统一路由与导航，当前新增“脚本测试页面”。
- 技术栈明确：JS 引擎采用 `flutter_qjs`；编辑器采用 `flutter_monaco`（Windows 使用 WebView2）。

## 路由与导航架构

- 顶层 Shell：`HomeShell`（`Scaffold` + `NavigationRail` 或 `BottomNavigationBar`），集中管理页面切换，支持未来扩展更多页面。
- 路由集中化：
  - `lib/routes/app_routes.dart`：路由常量与注册函数，统一 `routes` 映射与 `onGenerateRoute`（便于懒加载与参数传递）。
  - `MaterialApp` 使用 `initialRoute` 与 `routes`，保留 `onUnknownRoute` 兜底。
- 页面挂载：
  - `routes['/']`：`HomeShell`（默认选中“功能页面”）。
  - `routes['/feature']`：现有功能页（`ScreenCaptureTestPage`）。
  - `routes['/script']`：新建脚本测试页（`ScriptTestPage`）。
- 切换策略：
  - Shell 内通过 `NavigationRailDestination`（或底部导航）切换索引，使用 `IndexedStack` 保持状态；同时提供“前往”命名路由支持深链（`Navigator.pushNamed(context, '/script')`）。

代码挂接参考：

- 应用入口：`lib/main.dart:14–21`（当前通过 `home` 直挂页面），调整为 `initialRoute: '/'` + `routes`。
- 现有主页面 Scaffold：`lib/components/ui/screen_capture_test_page.dart:1325–1329`（纳入 Shell 的 `IndexedStack`）。

## JS 引擎（flutter_qjs）设计

- 服务类：`lib/services/script_engine_service.dart`
  - `init()`：创建 `FlutterQjs`，必要时调用 `dispatch()` 建立事件循环。
  - `injectFunction(String name, Function fn)`：将 Dart 方法注入到 JS 全局（`(key, val) => { this[key] = val; }`），统一维护注入表（名称、签名、描述）。
  - `evaluate(String code)`：执行 JS，返回结果/错误；支持 `await` 解析 Promise。
  - `close()`：释放引擎与引用，避免泄漏。
- 异步执行：如需避免阻塞 UI，使用 `IsolateQjs` 实例在隔离线程评估；注入耗时方法时用 `IsolateFunction` 封装。

参考：`flutter_qjs` 提供函数注入与隔离线程支持，示例将 Dart 函数设置到全局对象供 JS 调用 \(pub.dev 文档) \[https://pub.dev/documentation/flutter_qjs/latest/]

## 编辑器（flutter_monaco）集成

- 组件：`lib/components/ui/widgets/script_editor.dart`
  - 嵌入 Monaco，语言 `javascript`，主题 `vs-dark`。
  - 自定义 Completion Provider：根据注入方法表返回函数名、参数片段与文档，提供智能提示。
  - 类型声明：向编辑器环境注入 `d.ts`（如 `declare function sum(a: number, b: number): number;`）增强类型检查与提示质量。
  - 诊断与高亮：通过 markers 标注常见错误与约束。
- 运行时要求：Windows 需安装 WebView2 Runtime \[https://developer.microsoft.com/en-us/microsoft-edge/webview2/]

参考：`flutter_monaco` 支持 Windows 与多补全提供者、标记/装饰能力 \[https://github.com/omar-hanafy/flutter_monaco]

## 页面实现：`ScriptTestPage`

- 布局：上方 Monaco 编辑器；下方结果区与“运行”按钮。
- 初始化：
  - 构建 `ScriptEngineService`，注入 DEMO 方法：`sum(a, b)`（同步返回数字）、可选 `httpGet(url)`（异步返回字符串）。
  - 编辑器默认模板：`const r = sum(2, 3); console.log(r); r;`（返回值用于展示）。
- 交互：点击“运行”读取编辑器代码，调用 `evaluate`，在底部展示结果或错误信息；支持多次运行与实时刷新。

## 安全与性能

- 沙箱：QuickJS 仅暴露注入的方法，不直接访问宿主环境，降低风险。
- 约束：配置合理 `stackSize`；及时 `free` 引用；为异步方法添加超时与错误封装。
- 错误处理：捕获 `JSError`，结果区显示清晰消息；必要时增加日志采样。

## 实施步骤（可扩展路由版）

1. `pubspec.yaml` 添加依赖：`flutter_qjs` 与 `flutter_monaco`（如以 Git 依赖引入仓库 URL）；确保 Windows 安装 WebView2 Runtime。
2. 新增 `lib/routes/app_routes.dart`，集中定义路由常量与 `routes` 注册；在 `lib/main.dart` 改为 `initialRoute: '/'` 并使用集中路由表。
3. 新建 `lib/components/ui/shell/home_shell.dart`：`NavigationRail`/`BottomNavigationBar` + `IndexedStack`，内含“功能页”与“脚本页”。
4. 新建 `lib/services/script_engine_service.dart`，完成引擎初始化、方法注入、评估与资源管理。
5. 新建 `lib/components/ui/script_test_page.dart` 与 `widgets/script_editor.dart`，完成编辑器与运行按钮、结果展示；注册自定义补全与类型声明。
6. 自测：运行示例模板与错误脚本，验证同步/异步、重复执行与导航切换稳定性。

## 风险与替代方案

- 如 `flutter_monaco` 兼容性受限：可退回 `webview_flutter` + 手工集成 Monaco（需更多前端资源与桥接代码），或临时使用 `flutter_code_editor`（弱提示）。
- 如后续需要更强路由能力与深链：可平滑迁移到 `go_router`，保留页面组件与服务层不变。

## 代码参考锚点

- 入口与首页：`lib/main.dart:14–21`
- 现有主页面 Scaffold：`lib/components/ui/screen_capture_test_page.dart:1325–1329`
