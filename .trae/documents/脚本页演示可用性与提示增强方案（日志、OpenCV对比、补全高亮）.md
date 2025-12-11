## 更新要求
- compareImages 参数改为：compareImages(templatePath: string, targetPath: string, minScore?: number)
- 从本地路径读取图片（Dart 侧），OpenCV 进行模板匹配，返回分数与矩形，若分数低于 minScore 则返回 { ok:false, reason:'LOW_SCORE' }
- 其它方案保持不变（日志机制、示例按钮、编辑器提示与高亮）

## 具体实现
1) 图像对比（路径版）
- Dart 注入方法：compareImages(String templatePath, String targetPath, [double? minScore])
  - 读取文件：File(templatePath).readAsBytes() / File(targetPath).readAsBytes()
  - 解码：cv.imdecode(bytes, cv.IMREAD_GRAYSCALE)
  - 模板匹配：cv.matchTemplate(target, template, cv.TM_CCOEFF_NORMED)
  - 最佳点与分数：cv.minMaxLoc，score ∈ [0,1]
  - 矩形：{x, y, w: template.cols, h: template.rows}
  - 阈值判断：score < (minScore ?? 0.8) → { ok:false, reason:'LOW_SCORE', score }
  - 成功返回：{ ok:true, score, rect }

- JS 演示脚本：
(async () => {
  const r = await compareImages('D:/images/tpl.png', 'D:/images/screen.png', 0.85);
  log(JSON.stringify(r));
  return r.ok ? r.score : r.reason;
})()

2) 日志与结果展示
- 继续使用 log() 采集，UI 分栏展示 Result / Logs；错误时显示 error/stack/logs
- “示例：compareImages”按钮：弹出两个文件路径选择框（或直接写入示例路径），并生成脚本

3) 编辑器提示与高亮
- d.ts 更新：
  - declare function compareImages(templatePath: string, targetPath: string, minScore?: number): Promise<{ ok: boolean, score: number, rect?: { x:number, y:number, w:number, h:number }, reason?: string }>;
- 注册 Completion Provider：
  - label: 'compareImages'，documentation：路径版说明与返回结构，insertText 片段：compareImages(${1:tplPath}, ${2:targetPath}, ${3:0.85})

## 验证
- sum/httpGet 示例正常；compareImages 路径版在 Windows 本地图片上运行，Result 显示 score 或 reason，Logs 显示 JSON
- flutter analyze 通过；构建 Windows 成功

## 交付
- compareImages 支持路径读取与相似度阈值；日志面板与结果面板；编辑器补全与类型声明同步更新