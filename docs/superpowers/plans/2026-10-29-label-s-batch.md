# LYGlyphText S 批次：剩余功能、RocketSim 验证与首个版本

> **For agentic workers:** 沿用[连续开发契约](2026-10-20-continuous-development.md)与 [CONTRIBUTING](../../../CONTRIBUTING.md)；模拟器测试串行，所有 RocketSim 命令显式指定本仓设备 `--udid 5260ADE6-ADC2-44AA-9EEB-CDEC90196D08`。

**起点：** main `9219426`，L 批次已交付，完整回归 442／442。范围约束不变：只做 Label、Core Text 唯一内核、零第三方运行依赖、iOS 16+、Swift 6，公开 API 只增加。

| 编号 | 内容 | 接口与行为契约 | 关键验收 |
|---|---|---|---|
| S0 契约 | 本文件与总计划登记 | 只改文档 | docs 检查 |
| S1 拖柄无障碍可调节 | 选区两端拖柄成为可调节无障碍元素：label 取自 `selectionStartAccessibilityName`／`selectionEndAccessibilityName`（默认“选区开始”“选区结束”），value 为选区文字；increment／decrement 按一个组合字符伸缩该端，至少保留一个字符；`accessibilityIdentifier` 为 `LYGlyphText.selectionStart`／`LYGlyphText.selectionEnd`；只在有选区时出现在无障碍树中 | 调节方向、边界、交叉保护、无障碍树顺序；UI 测试按 identifier 拖动拖柄扩大选区并截图 |
| S2 加载器磁盘缓存 | `LYGlyphTextURLSessionImageLoader` 新增 `diskCacheCapacity`（默认 50MB，0 关闭）与 `diskCacheDirectory`；使用专用 `URLCache`，不写宿主的 `URLCache.shared`，遵循 HTTP 缓存头；`removeAllCachedImages()` 清理内存与磁盘 | 新实例命中磁盘不再请求；清理后重新请求；容量 0 不落盘 |
| S3 轻量 Markdown 规则 | `.markdownLinks(attributes:pressedStyle:)`：`[文字](url)` 显示为“文字”并生成 URL 动作；`.markdownEmphasis()`：`**粗体**`、`*斜体*`、`` `代码` ``，按所在字体派生，去掉标记。不支持嵌套、转义、标题、列表、代码块 | 原文映射、动作范围、组合字符、与其他规则共存、不配对标记保留 |
| S4 调试叠加层 | `LYGlyphTextDebugOptions`：`.lineFrames`、`.baselines`、`.attachmentFrames`、`.actionRegions`；Label 与 SwiftUI 的 `debugOptions` 默认空，只在绘制最后描线，不影响测量、命中与无障碍 | 默认空像素不变；各选项像素断言 |
| S5 Demo 与 UI 测试 | 2.x 演示页增加胶囊背景、截断模式切换、Markdown、调试叠加、远程图片尺寸回调示例 | 新 UI 测试；完整回归 |
| S6 RocketSim 验证 | 在专用设备上用 RocketSim 驱动 Demo：选择、拖柄拖动录屏、拷贝、token、整段点击、截断模式、Markdown、调试叠加；各页 `accessibility-audit` | 截图、录屏与 audit 结果存证；发现的问题先留证再修复；补充证据，不计入自动回归数 |
| S7 回归与版本 | CHANGELOG 合并为 `1.0.0-beta.1`；README 加 SPM 版本化接入；完整回归后创建并推送 annotated tag `1.0.0-beta.1` | 远端 Tag 指向回归通过的提交；不创建 GitHub Release |

**版本决定：** 首个版本 `1.0.0-beta.1`。仓库从未发布，1.0／2.x／L／S 只是内部批次名，第一次发布合并为一个版本；iOS 16 运行、Swift 6.0 编译器、真机、人工 VoiceOver 仍未验证，所以先发 beta，门槛补齐后发 `1.0.0`。之后只增加 API 用 1.x.y，破坏性变化用 2.0.0。用户于 2026-10-29 批准计划，授权创建并推送该 Tag。
