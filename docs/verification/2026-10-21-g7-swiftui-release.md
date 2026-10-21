# G7 SwiftUI 参数与 2.x 准备验证记录

日期：2026-10-21。基于 G6，分支 `codex/g7-swiftui-release`。执行契约见 [2.x Label 路线图](../superpowers/plans/2026-10-21-label-roadmap.md) G7。

## 交付内容

- `LYGlyphTextView` 新增 `isSelectable`（默认 false）与 `onSelectionChange`，每次更新使用最新值；`imageLoader`（G3）与截断 token（经 `configuration`，G2）已可在 SwiftUI 使用。SwiftUI 拆卸同时释放选区回调。
- README、CHANGELOG（2.x 节，含 `.remoteImage` 新增 case 的源码影响说明）与发布准备（2.x 独立门槛）更新；路线图与总计划标注各阶段完成情况和未交付项。
- 选区与截断 token 的 AX：可交互 token 已作为最后一个按钮元素（G2）；选区本身不暴露为 AX 状态，人工 VoiceOver 体验未验证。

## 行为证据

`Tests/LYGlyphTextTests/SwiftUIFeatureTests.swift`（1 项）：真实 UIHostingController 中 `isSelectable` 与截断 token 传到 Label，设置选区触发回调；rootView 更新为默认参数后关闭选择并清除选区；拆卸释放 `onSelectionChange`。

## 正式检查

| 检查 | 结果 |
|---|---|
| 固定 SwiftFormat 0.59.1 | 110 个 Swift 文件 0 需格式化 |
| `scripts/verify.sh docs`／`build` | PASS |
| `scripts/verify.sh test` | **419／419 Passed（393 宿主＋26 UI）**，0 失败／跳过／预期失败，`runtimeWarnings=[]` |

G6 的 418 个方法与 P1 的 368 个基线方法全部保留。证据保存在主 checkout 的 `.build/verification/g7/`。

## 2.x 汇总

| 阶段 | 提交 | 完整回归 |
|---|---|---|
| G1 显示内核重构 | `589662f` | 371／371 |
| G2 截断 token／特效／链接 | `8635132` | 386／386 |
| G3 网络图片 | `7eab0d6` | 397／397 |
| G4 后台预排版 | `9d6c58b` | 403／403 |
| G5 选择与拷贝 | `ae33f2e` | 413／413 |
| G6 文本解析器 | `b17cb70` | 418／418 |
| G7 SwiftUI 参数与 2.x 准备 | 本提交 | 419／419 |

全部在 Xcode 27.1／Swift 6.4／Swift 6 模式、iPhone 17 Pro Simulator iOS 27.0 上验证。仍未验证：Swift 6.0 编译器、iOS 16 运行、真机、人工 VoiceOver、真实网络、Kingfisher 桥接编译、Allocations／Leaks 专用分析。未授权也未创建 Tag／Release。
