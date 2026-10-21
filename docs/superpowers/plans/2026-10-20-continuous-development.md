# LYGlyphText Continuous Development Implementation Plan

> **For agentic workers:** 使用 executing-plans 按任务推进；用户已授权连续执行和每项任务的自动提交、集成及普通推送，不需要再次询问是否继续。

**Goal:** 按总计划完成剩余首版能力，先交付可独立验收的 UIView 附件，再完成文本交互、宿主、环境与发布准备。

**Architecture:** 保留 Core Text 单一内核、MainActor 文档与 UI、UIImage 独立描述。UIView 仅由 Label 的可见附件宿主管理，测量与几何不创建视图；SwiftUI 复用同一宿主。

**Tech Stack:** iOS 16+、Swift tools 6.0／Swift 6 language mode、UIKit、SwiftUI、Core Text、XCTest，零第三方运行依赖。

## 已批准的连续流程

- [ ] 从 [总计划第 5.0 节](2026-10-20-lyglyphtext-implementation.md) 自上而下选择第一个未完成且依赖已满足的任务，将其标为进行中。
- [ ] 先固定本任务接口、默认值、所有权、失败／取消语义与验收边界；实现任务先编写能复现缺口的行为测试，确认失败原因。纯文档任务执行 docs 与规范审查，不增加无意义测试。
- [ ] 最小实现并运行针对性检查；公开接口、生命周期和跨端变化覆盖直接消费者，保留已有回归，不通过减少验收范围绕过失败。
- [ ] 更新阶段勾选、队列状态与独立验证记录，列出命令、环境、真实结果、截图和未验证项。
- [ ] 按 [CONTRIBUTING](../../../CONTRIBUTING.md) 中文 Conventional Commit、独占集成锁、候选验证、普通合入 main 与 `git push origin main` 完成当前任务；只提交本任务文件。
- [ ] 自动开始下一项，不停在“要不要继续”。最终功能与证据满足前保持推进；PR、Tag、Release 和远端删除不在本次授权内。

只有必须由用户决定的真实阻塞、改动冲突或反复验证失败才暂停相关任务，保留现场并说明需要的决定。不可用的 iOS 16、Swift 6.0 编译器、真机或人工 VoiceOver 环境标为“未验证”，继续独立工作；发布门槛不会因此视为通过。普通 push 失败保留提交和本地集成、记录原因，不强推／自动 pull／rebase；不依赖远端交付的任务继续。

执行队列为 D0 → V1 → M1a → M1b → I1 → H1 → A1 → P1；状态、依赖、验收与证据由总计划唯一维护。D0—I1 已交付，[H1 宿主矩阵](2026-10-21-host-matrix.md)已完成 319／319 正式回归（298 宿主＋21 UI）与 12 张截图检查，见 [H1 记录](../../verification/2026-10-21-host-matrix.md)；最终证据复审及提交／集成／普通推送仍待执行。当前下一项为 A1，H1 交付后自动实施，不等待用户再次规划。本文件细化 V1，[M1 分段／动作／样式契约](2026-10-20-document-actions-styles.md)与[I1 契约](2026-10-20-text-interaction.md)保留各自历史设计和证据；[早期 UIView 提案](2026-10-20-uiview-attachments-next.md)仅作为设计背景。

## V1：接口契约

**状态：** V1 已以 `70e8340` 提交、合入并普通推送，远端 SHA 已核对一致；临时分支已安全删除。D0 规则提交为 `160c3c4`。以下接口已实现；[专项记录](../../verification/2026-10-20-view-attachments.md) 保存 102／102 完整回归、八张截图和失败修复证据。M1a `b74a0cb` 完成 127／127 回归，M1b `6dbeaee` 完成 215／215 回归，I1 `003558c` 完成 294／294 正式回归，均已合入／推送并核对远端 SHA；H1 已完成正式功能验收，交付后自动进入 A1。

| 入口 | 约定 |
|---|---|
| `@MainActor LYGlyphTextViewAttachment` | 不可变描述，公开只读 `id: String`、`viewID: String`、`size: CGSize`、`alignment: LYGlyphTextAttachmentAlignment`、`alternativeText: String?`、`isInteractive: Bool`；不持有 UIView、闭包或宿主。 |
| 描述初始化 | `init(id:viewID:size:alignment:alternativeText:isInteractive:)`；alignment 默认 `.bottom`、alternativeText 默认 `nil`、isInteractive 默认 `false`，复用图片附件的对齐类型。 |
| 文档初始化 | `init(attributedText: NSAttributedString, attachments: [Int: LYGlyphTextAttachment] = [:], viewAttachments: [Int: LYGlyphTextViewAttachment] = [:]) throws`；现有调用保持兼容，不改变 UIImage 描述。 |
| 文档校验 | 两字典统一按原文 UTF-16 校验独立 U+FFFC、跨种类唯一 id、有限且为正的 size；缺描述、非法位置、重复 ID、非法尺寸、标准 attachment 仍报可识别错误。同位置同时提供图片／视图描述返回明确的位置冲突错误，不能静默选一种。 |
| `@MainActor LYGlyphTextAttachmentViewProvider` | final 引用类型；公开不可变 `makeView: @MainActor (LYGlyphTextViewAttachment) -> UIView?` 和 `onUnmount: (@MainActor (LYGlyphTextViewAttachment, UIView) -> Void)?`。`init(makeView:onUnmount:)` 的 onUnmount 默认 nil。不比较闭包，以对象身份表示 provider 版本。 |
| UIKit | Label 增加 `viewProvider: LYGlyphTextAttachmentViewProvider?` 与 `reloadAttachments()`。同 provider 重赋值不重建；替换 provider 或显式 reload 失效当前挂载与失败缓存，等待下一次可见展示布局创建。 |
| SwiftUI | `LYGlyphTextView(document:configuration:viewProvider:)` 的 viewProvider 默认 nil；每次 update 刷新输入，同对象不重建；替换对象使用新闭包，dismantle 显式清空 document 与 provider。V1 不提前加入 onAction。 |

新文档对象替换必须清理旧挂载，即使 ID／内容相同；相同文档身份的普通 SwiftUI 更新不重复清理。更换文档保留宿主配置的 provider；nil 文档清空内容与挂载，不擅自清空宿主配置。附件外框只来自声明尺寸与最终 Core Text 几何，工厂返回的 frame／intrinsicContentSize 不能反向参与文字测量。

## V1：可见性、所有权与清理

- 工厂只允许在 `window != nil` 的展示布局中调用；纯几何计算、sizeThatFits、intrinsicContentSize、systemLayoutSizeFitting 和 SwiftUI proposal 测量调用数始终为 0。未进入 window 的离屏布局同样不创建 UIView；父列表的滚动视口由宿主复用生命周期管理，不扫描祖先裁切区域。
- 用最终完整附件矩形与实际内容可见区的交集决定挂载。连续可见的同 ID 复用同一 UIView，只更新 frame；宽度往返不额外创建。完全离开可见集、被截断或高度完全裁切即卸载并释放，重新可见重新创建，不缓存隐藏视图。
- 部分可见视图保留完整布局外框，由只覆盖内容可见区的容器裁切。容器空白处触摸穿透；裁切外不响应，isInteractive 为 false 时附件不截获触摸；true 时真实 UIControl／自有手势响应自身事件。
- 工厂返回 nil 或被拒绝的实例时保留声明占位尺寸，在同一文档／provider／reload 版本的持续可见期间缓存失败，不在每次 layout 重试；完全不可见后重入、换文档／provider 或 reload 才可重试。
- 拒绝已经有 superview 的返回值、当前宿主其他 ID 使用的同一实例、Label 自身及其祖先；不得抢走、移除或清理不属于本宿主的实例，不形成父子循环。相同文档用于两个 Label 时各自调用工厂，各自拥有不同实例。
- 每次成功挂载恰好对应一次 `onUnmount(description, view)`，使用创建该挂载的 provider 和描述；nil／拒绝结果不触发，重复清理不增加次数。回调前解除内部所有权和父子关系，允许宿主释放资源。
- makeView／onUnmount 均可能同步改 document、provider、reload 或移出 window。回调返回后核对文档／provider／刷新版本及 window；旧轮结果不能挂入新状态，不修改迭代中的集合，不重复卸载。未成功挂载的过期 factory 返回值不触发 onUnmount。
- 替换／清空文档、换 provider、reload、移出 window、SwiftUI dismantle 均有幂等清理路径。移出 window 保留配置，重新进入重新挂载；dismantle 清空文档和 provider 并解除闭包持有。
- 清理不触发尚未初始化的 lazy 子视图；`deinit` 不访问 UI 或 MainActor 对象。生命周期通过显式事件处理，示例闭包避免强持有 Label；用 weak 引用验证旧视图／provider 能释放。

V1 只验收附件自己的按钮／手势，不实现文字 tap、longPress、高亮或动作事件。文字语义、装饰附件所属动作以及取消状态机由 M1／I1 完成；额外附件内边距、网络加载、全局复用池不纳入 V1。

## V1：文件与执行步骤

| 文件／目录 | 职责 |
|---|---|
| `Sources/LYGlyphText/Document/LYGlyphTextViewAttachment.swift` | 独立视图描述与默认值 |
| `Sources/LYGlyphText/Document/LYGlyphTextDocument.swift` | 两类附件统一校验及明确冲突错误 |
| `Sources/LYGlyphText/Layout/` | 统一度量与可见放置，维持图片绘制／截断回归 |
| `Sources/LYGlyphText/UIKit/LYGlyphTextAttachmentViewProvider.swift` | MainActor provider 与不可变闭包 |
| `Sources/LYGlyphText/UIKit/` | Label 接入、裁切穿透容器、挂载集合与幂等清理；按职责拆文件 |
| `Sources/LYGlyphText/SwiftUI/` | provider 输入、身份复用与 dismantle |
| `Tests/LYGlyphTextTests/ViewAttachmentTests.swift` | 输入、测量、可见性、所有权、重入、释放及 SwiftUI 行为 |
| `Examples/LYGlyphTextDemo/` | 两端真实附件／按钮、nil／清空／reload 控制和列表复用；宿主及 UI 测试 |
| `docs/verification/2026-10-20-view-attachments.md` | 完成实现后新增真实命令、环境、计数、截图、限制 |

- [x] 写描述默认值、现有初始化兼容、两字典相同位置／ID、U+FFFC 与所有尺寸分量测试；先运行确认新增接口缺失导致失败，再实现模型与统一几何。
- [x] 写所有测量入口零 factory、离屏布局零 factory 测试；窗口内首挂载、连续可见复用、完全隐藏卸载／恢复重建、部分裁切的 frame 与触摸范围测试；再接入可见宿主。
- [x] 写 nil／拒绝缓存、两个宿主独立、带 superview／同实例／self／ancestor 拒绝、成功挂载精确清理次数测试；再实现所有权检查与失败缓存。
- [x] 写工厂／卸载回调同步替换文档、换 provider、reload、detach 的重入测试；验证旧结果不挂载、旧回调不清理新集合、重复清理安全，再实现版本核对。
- [x] 写 UIKit 文档清空／替换、provider 身份、reload、detach／reattach、SwiftUI 更新／dismantle 与 weak 释放测试；再补生命周期接入，保留既有尺寸和图片测试。
- [x] 两端共用同一输入，示例提供 UIImageView、按钮、自定义徽章、nil 工厂与清空／reload；真实 UI 测试操作按钮和控制项，滚动列表后验证复用无旧附件，导出并检查截图。仅直接调用按钮回调不能替代真实点击。
- [x] 运行 docs、固定版本 format、build、专用独占 Simulator 的完整宿主／UI 测试，更新证据与总计划。
- [x] 按连续流程提交、集成、普通推送，自动进入 M1a；提交 `70e8340`，远端 main SHA 已核对一致。

## V1：验证与证据边界

图片阶段已有 **72／72 Passed（68 宿主＋4 UI）**，见 [图片验证记录](../../verification/2026-10-20-image-attachments.md)。这是历史基线，V1 必须保留既有覆盖并增加上述用例，不把尚未运行的测试记为通过。

```sh
scripts/verify.sh docs
scripts/verify.sh format
scripts/verify.sh build
xcrun simctl list devices available
scripts/verify.sh test <本任务独占的Simulator-UDID>
```

运行前确认设备未被其他任务占用，记录实际 UDID／runtime、Xcode／Swift、日志／xcresult、非零测试数、factory／onUnmount 计数与截图对应关系。docs 任务只运行 docs。公开 API 与 SwiftUI 生命周期变化要求覆盖两端消费者；截图需要人工检查，自动回调测试、模拟点击或新 SDK 编译不代替真实 UI／最低系统／VoiceOver 证据。

Swift 6.0 编译器、iOS 16、真机、VoiceOver、性能和发布资格分别留证。不可用环境继续列为未验证，不阻塞 V1 其余独立验收，也不授权 PR、Tag 或 Release。
