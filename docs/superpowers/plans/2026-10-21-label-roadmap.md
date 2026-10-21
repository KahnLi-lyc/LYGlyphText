# LYGlyphText 2.x Label 能力路线图

> **For agentic workers:** 按[连续开发契约](2026-10-20-continuous-development.md)与 [CONTRIBUTING](../../../CONTRIBUTING.md) 执行；每阶段先写接口／行为契约和失败测试，再实现、验证、规格审查、质量审查、提交、锁内集成和普通推送。PR、Tag、Release 不在授权内。

**Goal:** 以 YYLabel 能力为对标，扩展只读图文混排 `LYGlyphTextLabel`：网络图片、可自定义可点击截断、文字特效、预排版／异步显示、选择复制与文本解析，同时保留现有 Swift 6、Dynamic Type、深色模式、RTL、AX 与 SwiftUI 质量。

**Architecture:** Core Text 仍是唯一排版内核；Document 描述输入，内部 Layout 统一测量、绘制、截断、命中与选区几何，Label 管理 UIKit，`LYGlyphTextView` 包装 SwiftUI。只增加公开 API，不破坏 1.0 接口。

**Tech Stack:** iOS 16+、Swift tools 6.0／Swift 6 language mode、UIKit、SwiftUI、Core Text、ImageIO、URLSession、XCTest，零第三方运行依赖。

## 起点与范围决定

起点为 main `43dc0c9`：P1 正式 368／368（344 宿主＋24 UI），R1 记录 Swift 6.0 编译器与 iOS 16 运行均缺环境、仍未验证。代码审查对照工作区外的 YYText 1.0.7、BSText 1.1.3（均 MIT）完成；第三方源码只作研究，没有移植登记。

用户于 2026-10-21 确认：

- **只做自定义 Label。** 可编辑 TextView、输入法、撤销重做不在本路线图；不引入 TextKit 2，Core Text 单一内核规则不变。
- **网络图片使用“公开加载协议＋内置轻量加载器”。** 默认实现仅用 URLSession、NSCache 和 ImageIO；组件 Package 不依赖 Kingfisher 等第三方库（SPM 为同一 Package 的全部 product 解析依赖，可选 product 也会破坏零依赖）。README 提供可复制的 Kingfisher 桥接示例，供宿主复用自身缓存。
- **版本节奏（推荐，待发布时确认）：** 1.0 只读版按[发布门槛](../../RELEASE_READINESS.md)独立补证；本路线图能力进入 2.x，只增加 API。

## 能力对照

| 能力 | YYLabel／BSLabel | LYGlyphText 当前 | 路线图处理 |
|---|---|---|---|
| Core Text 多行、内边距、垂直对齐 | 有 | 有 | 保持 |
| 截断 | none／start／middle／end，任意富文本 `truncationToken` | 仅尾部 `…`，写死 | G2：自定义可动作 token、head／middle／tail |
| 部分高亮与点击 | 点击／长按，按下颜色／背景／边框，整段点击 | 点击／长按，按下颜色／背景；取消、滚动、RTL、截断命中完整 | G2：圆角背景／边框按下样式、整段点击 |
| 附件 | UIImage、UIView、CALayer | UIImage、工厂 UIView（所有权更严格） | CALayer 暂不做 |
| 网络图片 | 依赖 YYWebImage／YYAnimatedImageView | 无，宿主自建 | G3 |
| 文字特效 | 阴影、内阴影、描边、边框、背景边框、字形变换、Ruby | 下划线、删除线、背景、kern、baseline、连字；其他属性静默忽略 | G2：阴影、描边、圆角背景边框、可选 `.link` 转动作 |
| 排版扩展 | exclusionPaths、竖排、行位置修饰、调试叠加 | 无 | G2：固定行高；其余低优先级、不承诺 |
| 性能 | 异步绘制、后台预排版 | 主线程同步；P1 首次测量 p50：1000 UTF-16 约 11.4ms，5000 约 59ms | G4 |
| 选择复制 | YYLabel 不支持（需 YYTextView） | 无 | G5 |
| 解析器 | 表情、Markdown 示例 | 无 | G6：URL／@／#／表情短码 |
| Swift 6、动态环境、AX、SwiftUI 测量 | 无或不完整 | 完整并验证 | 保持并扩展到新能力 |

不照搬：依赖 keyWindow 的自建效果窗口（多 scene／Extension 不安全）、零尺寸 `UIGraphicsBeginImageContext`、属性内静态 CGColor、无取消的全局异步队列、WeakProxy 定时器。参考 MIT 代码时只借鉴设计；如改写源码，按 [REFERENCES](../../REFERENCES.md) 登记来源并保留许可。

## 现有代码问题

1. `LYGlyphTextLabel.measuredLayout` 与 `draw(_:)` 在主线程同步排版／绘制，长文首帧超过一帧预算。
2. `TailTruncation` 每次回退一个字素并重建 NSAttributedString／CTLine，长末行或宽 token 为 O(k·n)。
3. 截断 token 写死 `…`，无法实现“…展开全文”。
4. 文档属性白名单静默忽略阴影、描边、`.link` 等；迁移来的链接文本不可点击。
5. Label 同时承担布局缓存、绘制、附件对账、AX 和手势状态机，扩展选区与异步绘制前需按职责拆出内部显示内核。
6. 附件尺寸只能由文档声明，网络图片缺少“加载后按策略更新尺寸”的正式通道。
7. 纯文本也必须 `try` 构造 Document，缺少便捷入口。
8. 次要：按下样式仅颜色；不支持 IB；无调试叠加。

保留：UTF-16／组合字符校验、附件所有权与幂等清理、取消语义、测量不创建附件、两项布局缓存、SwiftUI proposal 测量、AX 语义和行为测试体系。

## 执行队列

| 顺序／任务 | 依赖 | 范围 | 关键验收 |
|---|---|---|---|
| G0 规则与路线图 | R1 | 本文件；总计划范围／队列、README、CHANGELOG、REFERENCES 移植登记表 | docs 检查；规范一致；不改源码 |
| G1 显示内核重构（已完成，见[记录](../../verification/2026-10-21-g1-display-core.md)） | G0 | 抽出内部 `TextSurface`（布局缓存、绘制、附件对账、几何／命中、AX 快照），Label 按职责拆分；截断改为定位后局部调整 | 368 项全部保留并通过；公开 API 不变；P1 九组不劣化；新增截断复杂度测试 |
| G2 显示能力（已完成，见[记录](../../verification/2026-10-21-g2-display-features.md)；head／middle 截断、整段点击、纯文本便捷构造与文档级圆角背景未交付） | G1 | 富文本截断 token（可带动作）、head／middle／tail；阴影、描边、圆角背景边框及其按下样式；固定行高；可选 `.link` 转动作；整段点击；纯文本便捷 API | 绘制／几何测试覆盖 RTL、组合字符与截断命中；截图检查 |
| G3 网络图片（已完成，见[记录](../../verification/2026-10-21-g3-remote-images.md)；`.fitWidth` 自动改尺寸未交付） | G1 | 远程图片附件（URL、声明尺寸或 `.fixed`／`.fitWidth` 策略、占位／失败图）；async 可取消加载协议；默认 URLSession＋NSCache 加载器、请求去重、离屏／复用取消、ImageIO GIF；加载后一次显式固有尺寸失效；Kingfisher 桥接示例 | 本地 URLProtocol 桩，不访问外网；测量零请求；取消、复用、去重、失败回退；桥接完整实现协议；列表复用 UI 测试 |
| G4 预排版与异步显示（预排版已完成，见[记录](../../verification/2026-10-21-g4-prepared-layout.md)；异步绘制未交付） | G2、G3 | 先 spike：不使用并发逃生标记能否在后台由不可变快照排版。可行则提供列表预排版与 `displaysAsynchronously`（修订号丢弃过期结果）；不可行记录原因，改为主线程预计算 | Release 前后对比 5000 UTF-16 首帧主线程耗时；取消与复用测试；无 `@unchecked Sendable`／`nonisolated(unsafe)` |
| G5 选择与复制（已完成，见[记录](../../verification/2026-10-21-g5-selection.md)；基于 Core Text 几何与 UIEditMenuInteraction，未采用 UITextInput，无放大镜） | G4 | `isSelectable`；Core Text 选区几何（多行、bidi、附件、截断边界）；非编辑 `UITextInput` 接入 `UITextInteraction(for: .nonEditable)` 与 `UIEditMenuInteraction`；复制纯文本／富文本，附件输出替代文本；与动作手势的优先级 | 选区几何单测（中文、emoji、RTL、截断）；真实长按／拖柄／复制 UI 测试与剪贴板断言；列表滚动不误选 |
| G6 文本解析器 | G2 | `LYGlyphTextParser` 协议：NSDataDetector URL、@、#、表情短码转图片附件，输出 segments 与 actions | UTF-16、组合字符和重叠范围单测 |
| G7 SwiftUI、AX 与 2.0 准备 | G5、G6 | SwiftUI 新参数、选区 AX、README／CHANGELOG、全量回归与性能对比 | 完整宿主＋UI 回归；最低系统与最新系统分开留证 |

G2 与 G3 可在独立 worktree 并行，但不得同时修改同一文件；冲突时串行。每项新增公开 API 必须有中文 DocC、默认值、MainActor／取消语义，并扩展到 UIKit 与 SwiftUI 直接消费者。

## 验证边界

- 每个代码阶段运行 `scripts/verify.sh docs`、`format`、`build` 和专用 UDID 的完整 `test`，保存截图与源码哈希；同一已验证 SHA 不重复整套检查。
- 网络测试只使用本地桩；性能沿用 P1 Release 九组方法，模拟器结果不代表真机。
- iOS 16 运行、Swift 6.0 编译器、真机、人工 VoiceOver 和 Allocations／Leaks 专用分析继续独立留证，不由新阶段推导通过。
