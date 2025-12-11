## 问题分析
- 当前 flutter_js 版本为 0.8.5，QuickJS 通道 `channelDispacher` 在 C/FFI 层期望第二参数为字符串；一旦收到非字符串（Map/对象），会抛出 `type '_Map<dynamic, dynamic>' is not a subtype of type 'String' of 'message'`。
- 你的错误堆栈出现在 `QuickJsRuntime2.evaluate` 内，说明是在 JS→Dart 的消息阶段（如 `sendMessage(...)`）传参类型不符；而你也反馈 `console.log` 正常，这进一步指向我们自定义的消息通道调用（`log` 或 `compareImages`）是触发点。

## 修复与优化方案
### 1) 移除 JS 日志注入
- 删除我们注入的 `globalThis.log(...)` 和对应的 `onMessage('log', ...)` 处理逻辑，避免任何额外消息通道干扰。
- 保留 `console.log(...)` 给宿主控制台使用；页面内只显示返回值，不再收集 JS 日志。

### 2) 稳定 compareImages（路径+阈值）
- 保留 JS 侧的 `compareImages(...)` Promise 版本，但确保 `sendMessage('compareImages', <string>)` 始终传入 JSON 字符串：`JSON.stringify({ templatePath, targetPath, minScore, promiseId })`。
- Dart 侧 `onMessage('compareImages', (String msg) {...})` 严格按字符串解码；任何异常都通过 `resolvePromise(promiseId, payload)` 回传字符串化 JSON，保证类型一致。
- 提供 UI 降级路径：“本地对比”按钮直接调用 Dart/OpenCV，不走消息通道；即使通道不稳定也能演示成功。

### 3) 结果展示与用户体验
- 运行包装仍用 async IIFE + 显式 `return` 防止顶层变量重复声明错误。
- 页面仅显示结果；如走本地对比，结果以 JSON 显示（score/rect 或 LOW_SCORE）。
- 保留示例按钮：sum/httpGet/compareImages；在通道不稳定情况下推荐使用“本地对比”。

## 验证
- 移除日志注入后，`flutter analyze` 无新增错误；运行“示例：sum/httpGet”不再触发消息通道。
- compareImages：
  - 通道版：确认 `sendMessage` 第二参数为字符串，成功返回结果；
  - 本地版：选择两张图片，必定得到分数与矩形 JSON。

## 交付
- 我将删除日志注入与日志通道处理代码；
- 保留并严格字符串化 compareImages 通道；
- 完成本地对比按钮行为；
- 运行与构建验证后交付。