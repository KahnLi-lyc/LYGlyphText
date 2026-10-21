# G1 显示内核重构验证记录

日期：2026-10-21。基线 `f7d8cc9`，分支 `codex/g1-display-core`。执行契约见 [2.x Label 路线图](../superpowers/plans/2026-10-21-label-roadmap.md) G1。

## 范围与取舍

- **不改行为**：公开 API、默认值和全部既有测试保持不变。
- `LYGlyphTextLabel` 按职责拆为四个文件：主文件（公开属性、尺寸、绘制与失效）、`+Attachments`（附件对账与卸载）、`+Accessibility`（AX 快照与激活）、`+Interaction`（动作手势状态机）。跨文件协作的存储状态由 private 改为模块 internal，不对宿主公开。
- 新增内部 `LayoutCache`（`Sources/LYGlyphText/Layout/LayoutCache.swift`），承接原 Label 内联的解析输入、两项宽度缓存与构建计数。其语义与原实现逐行对应：命中不计数、新建插入队首、超过 2 项淘汰最旧；`invalidate()` 不重置计数。G4 预排版将复用此类型。
- 路线图原写“抽出 TextSurface”。2.x 已确认不做 TextView，没有第二个展示宿主，单独的 surface 对象没有当前用途；按 CODING_STYLE“不创建没有当前用途的抽象”，改为 LayoutCache＋职责 extension，满足后续 G4／G5 的扩展点。
- `TailTruncation` 增加内部 `tokenString`（默认 `…`，为 G2 自定义 token 准备）、`usesEstimate` 对照开关和 `candidateCount` 诊断。纯 LTR 行先用 `CTLineGetStringIndexForPosition` 估算截断点并向后放宽两个组合字符作为上界：上界不满足时从其下一个边界继续逐个回退；上界已满足（宽度非单调）时回到行尾逐个回退，保持原结果。RTL／混排行不估算。token 范围改为按实际 token 长度计算，默认 `…` 仍为 1。

## 缺口与行为证据

新增 `Tests/LYGlyphTextTests/TruncationSearchTests.swift`（3 项）：

- `testWideTokenOnLongLeftToRightLineUsesFewCandidates`：400 个 `i`、320pt、12 个省略号 token。原逐个回退（`usesEstimate: false`）候选数 ≥30，即本项缺口；估算路径 ≤4，结果文本相同且宽度不超出。
- `testEstimatedSearchMatchesLinearSearch`：8 组输入（Latin、中文标点、ZWJ emoji 与组合符、阿拉伯文、双向混排、窄宽字母、kern、混合字号）×13 种宽度×每条可见行×4 种 token，逐例比较截断文本、是否绘制 token、token 范围、方向偏移和可见原文区间完全一致，比较数 >500，且估算路径总候选数小于原路径。
- `testRightToLeftLineKeepsLinearSearch`：RTL 行候选数与原路径相同。

定向运行 `.build/verification/g1-targeted-01/`：TruncationSearchTests＋TruncationTests＋AutoLayoutTests 共 33 项通过（Xcode 27.1／iOS 27.0 Simulator `5260ADE6-ADC2-44AA-9EEB-CDEC90196D08`）。

## 正式检查

环境：Xcode 27.1（27A9275）、Apple Swift 6.4、Swift 6 language mode、iPhone 17 Pro Simulator iOS 27.0（24A434，`5260ADE6-ADC2-44AA-9EEB-CDEC90196D08`）。

| 检查 | 结果 | 证据 |
|---|---|---|
| `scripts/verify.sh docs` | PASS | `.build/verification/g1-full-run.log` |
| 固定 SwiftFormat 0.59.1 | PASS，91 个 Swift 文件 0 需格式化 | 回归前单独运行 `scripts/verify.sh format` |
| `scripts/verify.sh build` | Package／Demo Swift 6 模式构建通过 | `.build/verification/20261021T100233Z-55783-build/` |
| `scripts/verify.sh test 5260ADE6-…` | **371／371 Passed（347 宿主＋24 UI）**，0 失败／跳过／预期失败，`runtimeWarnings=[]` | `.build/verification/20261021T100245Z-55767-test/` |

P1 的 368 个测试方法逐一保留（名称对比无缺失），新增 3 个即 TruncationSearchTests；91 个 Swift 文件 SHA-256 与测试树对比保存在 `.build/verification/g1-final/summary.json`。

性能：布局缓存算法与 P1 逐行对应，截断只减少候选数；完整回归中的 Debug 性能 sanity 测试通过。没有重跑 P1 Release 九组计时，故不声称 Release 数值变化；G4 将对预排版做 Release 前后对比。

审查：按路线图验收项逐条自查规格（公开 API 无变化、368 项保留、截断等价对照）与代码质量（访问级别仅模块内放宽、无并发逃生标记、无新依赖），未另起独立审查代理。Swift 6.0 编译器与 iOS 16 运行仍未验证。
