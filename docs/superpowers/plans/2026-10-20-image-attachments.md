# LYGlyphText 行内图片附件实施计划

> 执行方式：使用 executing-plans 逐项实现；旧聊天已中断，本聊天接手现有分支和改动。

**目标：** 在基础显示和行数限制之上完成图片与文字混排，复用 UIKit／SwiftUI 的 Core Text 内核。

**基线：** e8318ac；iOS 16+、Swift tools 6.0、Swift 6 模式、纯 Swift、零第三方运行依赖。

## 接口与边界

- MainActor 的 `LYGlyphTextAttachment` 保存 id、UIImage、明确的 point 尺寸、top／center／bottom 对齐及可选替代文本；默认 bottom。
- `LYGlyphTextDocument.init(attributedText:attachments:) throws` 的附件字典默认空，以原文 UTF-16 位置关联单个 U+FFFC；校验位置、完整占位、唯一 ID、有限正尺寸，继续拒绝标准 NSTextAttachment。
- 图片按声明尺寸填充，处理 UIImage 方向；不可拆分、超宽裁切，不自动缩小。
- UIKit 基线相对图片顶部：top 为 `-a`，center 为 `-(a+d+h)/2`，bottom 为 `-d-h`；a 为字体 ascender，d 为带符号 descender，h 为声明高度。delegate 度量同时覆盖字体区域和图片。
- 本轮不实现分段构建器、View 工厂、点击、长按、附件内边距、网络加载或完整 VoiceOver；替代文本仅保存数据。

## 阶段与验收

- [x] 模型和失败测试：位置／尺寸／ID／占位校验，兼容旧入口及可变输入隔离。
- [x] 排版与几何：CTRunDelegate 不可变度量上下文及明确释放；字体区域对齐；附件影响宽高；最终可见 run 转 UIKit 附件矩形。
- [x] 绘制与截断：图片方向、内容区裁切；截断行 sourceOffset 映射；隐藏附件不绘制、不额外撑高；省略号无附件属性。
- [x] 宿主尺寸：保持两项缓存、测量无副作用、布局优先级、宽度往返与替换清空；UIKit／SwiftUI 同输入高度差不超过一个物理像素。
- [x] 示例：两端图片样例、三种对齐、现有内容／宽度／行数组合；图片由本地绘制生成，不引入外部资产。
- [x] 验证与交付：docs、format、build、宿主及 UI 测试，保存截图与环境证据；更新 README 和总计划，只勾选真实完成的图片任务。

证据见 [图片附件验证记录](../../verification/2026-10-20-image-attachments.md)：72／72 测试通过，12 张最终图片截图逐张检查。Swift 6.0 编译器、iOS 16 实际运行及完整 VoiceOver 仍未验证。

## 验证矩阵

覆盖混合字号、连续／行首／行尾／超高／超宽附件、中文／emoji／基本 RTL；截断保留／移除、省略号相邻／仅 token、隐藏高附件；内边距、零／有限／无限宽度、Auto Layout 和离屏测量、非零 bounds 原点、外部高度裁切及跨宿主共享文档。

Swift 6 模式构建、Swift 6.0 编译器兼容、iOS 16 运行分别记录；没有相应环境时标记未验证。

## 集成

在 `codex/image-attachments` 开发。验证通过后按 CONTRIBUTING 的独占锁流程提交并安全合入本地 main，清理本任务分支；不推送，不创建 Tag 或 Release。下一轮再规划 UIView 附件工厂、挂载复用与生命周期。
