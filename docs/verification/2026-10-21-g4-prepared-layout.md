# G4 预排版验证记录

日期：2026-10-21。基于 G3，分支 `codex/g4-prepared-layout`。执行契约见 [2.x Label 路线图](../superpowers/plans/2026-10-21-label-roadmap.md) G4。

## Spike 结论

路线图要求先确认后台排版能否不使用 `@unchecked Sendable`／`nonisolated(unsafe)`。结论为**可行**：

- 用 Swift 6 类型检查探针确认：MainActor 的 `LYGlyphTextDocument` 与公开描述类型在模块内可被非隔离代码读取其 Sendable 的 `let` 属性；UIFont、UIColor、CGColor、UIImage、UITraitCollection 在当前 SDK 为 Sendable；NSAttributedString 不是 Sendable，但只在排版函数内部局部创建。
- 内部 Layout 层（ResolvedText、LYGlyphTextLayout、TextFrame、TailTruncation、TextDecorations、PressedTextDrawing、SourceGeometry 等）去掉 `@MainActor`，成为非隔离、非 Sendable 的值；Label 仍在 MainActor 同步调用。`LayoutCache` 保持 MainActor。
- 后台在 `DispatchQueue.global` 中构造结果，经 `CheckedContinuation.resume(returning:)`（`sending`）一次性转移回 MainActor；没有使用任何并发逃生标记。
- 为跨线程传递配置，`LYGlyphTextConfiguration`（含 `Wrapping`、`VerticalAlignment`）、`LYGlyphTextTruncationToken`、`LYGlyphTextAttachmentAlignment` 新增 `Sendable` 一致性（只增加）。

## 交付的公开接口

| 接口 | 行为 |
|---|---|
| `LYGlyphTextPreparedLayout.prepare(document:configuration:width:traitCollection:) async` | 在后台线程排版，返回包含 `size`（含内边距、按 scale 像素向上取整）的结果；不创建视图、不调用工厂或图片加载器。宽度非有限按理想宽度，负值按 0。 |
| `LYGlyphTextLabel.apply(_:)` | 设置结果中的文档与配置，并在之后首次测量相同宽度、且显示环境（字号类别、明暗、显示比例、对比度、字重、层级、方向）与创建时一致时采用该布局，主线程不再排版。采用推迟到测量时，是因为列表 cell 常在加入 window 之前调用、环境此时尚未确定。文档或配置被替换时放弃；环境不一致时按普通路径排版。回调、工厂、加载器不变。 |

## 范围调整

`displaysAsynchronously`（后台绘制位图）本阶段不交付：P1 Release 数据中缓存位图绘制 p95 最多约 2.8ms，而 5000 UTF-16 首次测量约 59ms；主要成本在排版，已由预排版移出主线程。异步绘制还会引入内容闪烁、按下状态与选区同步重绘等新风险，收益不足以抵消。

## 行为与性能证据

新增 `Tests/LYGlyphTextTests/PreparedLayoutTests.swift`（5 项）：后台结果 `wasBuiltOnMainThread == false` 且尺寸、行数、可见原文区间、基线、两类附件矩形、动作矩形、截断 token 与同步排版逐项一致；`apply` 后同宽度测量构建次数为 0、工厂 0 次，其他宽度复用解析输入正常构建；未进入 window 时 apply、加入后再测量仍采用（构建 0），替换配置后放弃；环境不一致时构建 1 次；6 个文档并发预排版互不干扰，nil 文档只含内边距。

`Examples/LYGlyphTextDemo/LYGlyphTextDemoTests/PreparedLayoutMeasurementTests.swift` 记录主线程耗时，不设阈值。Release（`-O -whole-module-optimization`，`ENABLE_TESTABILITY=YES`）在专用模拟器 `21E5A075-…`（iPhone 17 Pro／iOS 27.0）运行，每组 30 次，nearest-rank p50，单位 µs；原始数据见 [JSON](data/prepared-layout-release-2026-10-21.json)：

| UTF-16／附件数 | 新 Label 首次同步 sizeThatFits | apply 后首次 sizeThatFits | 后台 prepare 往返墙钟 |
|---|---:|---:|---:|
| 100／0 | 1860.6 | 15.3 | 2127.2 |
| 100／3 | 1996.2 | 15.7 | 2209.3 |
| 100／10 | 2224.0 | 19.2 | 2433.1 |
| 1000／0 | 9958.6 | 19.7 | 10277.7 |
| 1000／3 | 9299.0 | 12.3 | 9439.0 |
| 1000／10 | 9520.7 | 13.7 | 9958.4 |
| 5000／0 | 45696.3 | 21.2 | 47361.4 |
| 5000／3 | 46910.0 | 21.3 | 48595.3 |
| 5000／10 | 47468.3 | 21.6 | 47763.8 |

5000 UTF-16 的主线程首次测量 p50 由约 46ms 降到约 21µs；排版耗时转移到后台线程（墙钟列，包含调度）。该次计时与另一台模拟器上的完整回归同时运行，数值只作对比参考，不代表真机或进程冷启动。

## 正式检查

| 检查 | 结果 |
|---|---|
| 固定 SwiftFormat 0.59.1 | 102 个 Swift 文件 0 需格式化 |
| `scripts/verify.sh docs`／`build` | PASS；Swift 6 模式下 Layout 层非隔离且无并发逃生标记，编译无新增错误 |
| `scripts/verify.sh test` | **403／403 Passed（379 宿主＋24 UI）**，0 失败／跳过／预期失败，`runtimeWarnings=[]` |

G3 的 397 个测试方法全部保留，新增 6 项。证据保存在主 checkout 的 `.build/verification/g4/`（含 Release 计时 `g4-release-01/`）。按路线图自查规格与质量；异步绘制未交付，原因见上文。Swift 6.0 编译器（尤其是 6.0 对 `sending` 与非隔离访问的检查）与 iOS 16 上后台解析字体／动态颜色均未验证。
