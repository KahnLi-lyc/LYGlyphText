# LYGlyphText Implementation Plan：Auto Layout 与尺寸适配

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. 如执行环境不提供该技能，按本文阶段顺序和验收清单执行；阶段失败时先修正，不跳过验收。

**Goal:** 实现支持局部文本交互、行内图片与自定义 UIView 附件的独立只读富文本 Swift Package，同时服务 UIKit 与 SwiftUI。

**Architecture:** 使用 Core Text 生成统一布局结果，供测量、绘制、截断、附件定位与命中检测共同使用；首版不使用 TextKit 2。UIKit 自定义 UIView 通过固有尺寸和标准测量流程对接 Auto Layout，SwiftUI 通过 UIViewRepresentable 复用内核。首版在 MainActor 同步排版，按明确失效条件复用有界缓存。

**Tech Stack:** iOS 16+、Swift 6 language mode、UIKit、SwiftUI、Core Text、Core Graphics、XCTest、Swift Package Manager。

**状态与日期：** 2026-10-21；已完成基础显示、行数限制／尾部省略、行内 UIImage／UIView、分段／动作描述与样式／完整已声明段落值、word／character、统一垂直展示及文字动作交互。I1 已交付基线 `003558c` 已合入并推送；I1 正式 docs／format／build／test 为 276 项宿主＋18 项 UI = 294／294，通过规格与质量审查，证据见 [I1 记录](../../verification/2026-10-20-interaction.md)。H1 功能验收完成，正式回归 298 项宿主＋21 项 UI＝319／319，已检查 12 张截图；最终规格及质量批准，以 `32ac04a` 合入推送并核远端 SHA 一致，见 [H1 宿主矩阵](2026-10-21-host-matrix.md)与[验证记录](../../verification/2026-10-21-host-matrix.md)；A1 已完成动态字体／颜色／RTL 与自动可见语义、动作激活，正式 359／359（336 宿主＋23 UI）；已以 `b615c3e` 合入推送并核远端 SHA；人工 VoiceOver 仍未验证，P1独立可执行准备已验收：正式368／368、86 Swift冻结、Release九组和真实列表证据归档；发布补证仍保留。证据另见 [基础显示记录](../../verification/2026-10-20-basic-display.md)、[行数限制记录](../../verification/2026-10-20-line-limits.md)、[图片附件记录](../../verification/2026-10-20-image-attachments.md)、[UIView 附件记录](../../verification/2026-10-20-view-attachments.md) 与 [样式记录](../../verification/2026-10-20-m1b-styles.md)。

---

## 1. 范围与完成定义

### 1.1 首版能力

- 富文本字体、前景／背景色、字距、基线偏移、段落样式、下划线与删除线。
- 多行排版、字符／单词换行、内边距、行数限制与尾部省略；从左至右及从右至左的水平文本。
- 分段文本与基于 NSAttributedString 的输入，动作使用稳定 ID，点击／长按统一向宿主回调。
- UIImage 图片附件，以及通过工厂创建的 UIImageView、UIButton、自定义 UIView 附件。
- 按下高亮、取消清理、滚动容器协作、附件交互优先级和列表复用。
- UIKit Auto Layout、固有尺寸、多行宽度驱动高度、布局优先级、横向／纵向 UIStackView、列表自适应，以及 SwiftUI 宽度提议测量。
- 深色模式、Dynamic Type、RTL 与基础 VoiceOver；SwiftUI 与 UIKit 共用内核。

### 1.2 首版不包含

编辑器、输入法、文本选择复制、竖排、任意排版路径与绕排、HTML／Markdown 解析、文本阴影／描边等扩展特效、动画排版、后台排版与异步渲染、内嵌任意 SwiftUI View、网络图片下载器。网络图片由宿主加载到附件视图；改变排版尺寸必须显式更新文档。

### 1.3 发布完成定义

阶段 0 的规范／工具与阶段 1—7 的组件实现分别验收；后七阶段均须有对应代码、自动检查和验收记录。最低系统真实运行结果与最新可用系统结果分别记录。所有未实际运行的环境标记为“未验证”，不能由新 SDK 编译、静态阅读或模拟回调推导通过。

## 2. 项目与代码边界

仓库为 `KahnLi-lyc/LYGlyphText`，公开、默认分支 main；产品与模块统一命名 LYGlyphText。工作区总目录不初始化 Git，第三方参考库不属于本仓库。

基础目录已建立；未来能力在对应职责目录增量实现：

```text
Package.swift
Sources/LYGlyphText/
  Document/       文档、分段、动作、附件与输入转换
  Layout/         Core Text 排版、截断、矩形查询及缓存键（internal）
  UIKit/          Label、附件宿主、触摸状态、无障碍
  SwiftUI/        UIViewRepresentable 包装
Tests/LYGlyphTextTests/
Examples/LYGlyphTextDemo/
  project.yml             固定 XcodeGen 2.46.0；生成 .xcodeproj 不提交
  LYGlyphTextDemo/       UIKit 与 SwiftUI 示例
  LYGlyphTextDemoTests/  带宿主测试
  LYGlyphTextDemoUITests/ 交互测试
```

- Swift tools 版本设为 6.0，Swift language mode 设为 v6，最低部署版本 iOS 16.0；首版仅支持 iOS／UIKit。
- 单一 library product 与单一业务 target，零第三方运行依赖；Apple 系统框架不属于第三方源码。
- 示例工程包含名为 LYGlyphTextDemo 的 shared scheme，通过本地 package 引用组件；示例不进入 library target。
- Core Text 与 UIKit/Core Foundation 类型可在 Swift 中调用；纯 Swift 不意味着不能调用 Apple 的 C／Objective-C 系统 API。
- 开发使用 `codex/` 前缀分支，验证后自动提交、安全合入本地 main 并普通推送至 origin/main；用户明确要求不推送时跳过，推送失败不强推或自动变基。PR／Tag／Release 需明确授权。流程见 [参与开发](../../../CONTRIBUTING.md)。
- 中文 DocC、命名、最小公开接口、MainActor、幂等清理及格式配置遵守 [编码规范](../../../CODING_STYLE.md)；不照搬业务 App 的固定字号、TCA 或 SnapKit 依赖。

## 3. 接口契约

下面定义完整首版的目标 API。**当前实际 API** 包含 `LYGlyphTextDocument.init(attributedText:attachments:viewAttachments:actions:) throws`（两个字典和 actions 默认空）、`init(segments:)`、MainActor 的 `LYGlyphTextSegment`／`LYGlyphTextAction`／`LYGlyphTextPressedStyle`／`LYGlyphTextActionEvent`、`LYGlyphTextDocumentError`、两类 MainActor 附件描述与 `LYGlyphTextAttachmentViewProvider`，以及共享 `LYGlyphTextAttachmentAlignment`。configuration 已有内边距／行数／word、character wrapping／top、center、bottom verticalAlignment；Label 已有 document／configuration／preferredMaxLayoutWidth／viewProvider／reloadAttachments／onAction 和标准尺寸接口；SwiftUI 已有 `LYGlyphTextView(document:configuration:viewProvider:displayHeight:onAction:)`，默认 displayHeight=nil 保持自然高度，onAction 默认 nil。图片描述包含只读 id、image、size、alignment 和 alternativeText；视图描述包含 id、viewID、size、alignment、alternativeText 与 isInteractive。附件对齐默认 bottom，替代文本默认 nil，交互默认 false。Document 保存独立文本与已声明字符／段落样式值，不持有 UIView、工厂或可变段落对象。两类附件共用 UTF-16 独立 U+FFFC、唯一 ID 和尺寸校验，拒绝同位置冲突、标准 attachment 和未描述的 U+FFFC。分段累计 UTF-16 位置，动作保留输入顺序并校验 ID、数值范围、完整字符及重叠；Label／SwiftUI 以最终可见几何发送 tap／longPress，并在取消时恢复按下绘制。

| 类型／入口 | 契约 |
|---|---|
| `LYGlyphTextDocument` | 不可变文档快照。已有默认空的 viewAttachments／actions 和 segments 输入；动作只保存范围与按下样式，业务回调仍由宿主 Label／SwiftUI 持有。图片与视图附件分开描述，共用 UTF-16 位置、独立 U+FFFC、唯一 ID 和尺寸校验；同位置冲突明确报错。文档不包含 UIView 或业务闭包。 |
| `LYGlyphTextSegment` | 文本段使用 attributed text 与可选 actionID；附件段使用 attachment 描述与可选 actionID。分段构建器自动累计 UTF-16 范围，使业务无需手写 NSRange。 |
| `LYGlyphTextAction` | 包含非空 actionID、非空 NSRange 和按下样式。一个范围对应一个动作；不同范围可使用同一 actionID，回调保留具体范围。动作范围不得相互重叠。 |
| `LYGlyphTextAttachment` | 已实现的 UIImage 描述：只读 id、image、size、alignment 与 alternativeText，保持现有初始化兼容；不改成 image／view 联合类型，不增加 UIView 或闭包。 |
| `LYGlyphTextViewAttachment` | 已实现：MainActor 不可变描述，包含只读 id、viewID、size、alignment（默认 bottom）、alternativeText（默认 nil）、isInteractive（默认 false）；不持有 UIView 或闭包。 |
| `LYGlyphTextAttachmentViewProvider` | 已实现：MainActor 引用类型，持有不可变 makeView 与可选 onUnmount；以 provider 对象身份判断失效。完整所有权、可见性、重入与释放契约见 [连续开发计划](2026-10-20-continuous-development.md)。 |
| `LYGlyphTextConfiguration` | 包含 textContainerInset、numberOfLines、word／character wrapping 与 top／center／bottom 垂直对齐。默认 0 内边距、0 行限制、word wrapping、top 对齐；有行数限制时尾部省略。 |
| `LYGlyphTextLabel: UIView` | `document`、`configuration`、`onAction`、`viewProvider`、`reloadAttachments()`、`intrinsicContentSize` 与 `sizeThatFits(_:)`，支持标准 `systemLayoutSizeFitting`。`document == nil` 清空文本、附件、交互及无障碍元素。`preferredMaxLayoutWidth` 默认 0，正值为包含内边距的固有尺寸测量宽度；实际绘制按 bounds。沿用标准 Hugging／Compression Resistance API。 |
| `LYGlyphTextView: UIViewRepresentable` | 已有 document、configuration、viewProvider、displayHeight 与 onAction；onAction 位于 displayHeight 后且默认 nil，每次 update 使用最新闭包。实现 makeUIView、updateUIView、sizeThatFits、dismantleUIView；默认自然高度，显式 displayHeight 指定展示外框。 |
| `LYGlyphTextActionEvent` | 输出 actionID、原文 UTF-16 range、可见片段矩形数组，以及 tap／longPress 类型。矩形坐标属于展示视图本地坐标，不向业务暴露 CTLine／CTRun。 |
| `LYGlyphTextLayout` | internal；保存容器约束、排版行、基线、可见原文区间、附件矩形、动作片段矩形与截断映射，不能成为公开 ABI。 |

### 3.1 线程与所有权

- 文档构造及 UIKit 相关公开接口采用 `@MainActor` 隔离。不可变不等于 Sendable：文档包含 UIKit 属性对象，首版不声明它可跨 actor 传递。
- `viewProvider` 的调用、UIView 创建／挂载／卸载、onAction 和 SwiftUI 更新均在 MainActor。
- 工厂按 view 标识返回宿主独占的新 UIView。相同文档在两个 Label 展示时必须得到不同实例；检测到返回已有其他 superview 的实例时拒绝挂载并报告诊断，不抢走其他宿主的视图。
- 工厂仅在 window 非 nil 的展示布局、可见附件首次出现或 provider 明确失效后调用；所有测量和纯几何查询不创建 UIView。Label 提供 `reloadAttachments()` 显式更新工厂结果；连续可见同 ID 复用，完全不可见即卸载，重现时重新创建。
- 文档与 Layout 不保留业务回调；替换文档清理旧布局、旧附件与交互，不擅自清空宿主配置的回调或工厂。View 销毁或 SwiftUI dismantle 时释放回调与工厂持有关系。
- 不通过大范围 `@unchecked Sendable`、`nonisolated(unsafe)` 或降低并发检查强度来换取编译通过。

### 3.2 范围与输入失败

- NSString、NSAttributedString、Core Text 内部索引统一以 UTF-16 为单位，Swift String.Index 必须通过官方转换与原字符串关联。
- 入口拒绝越界、整数溢出、空动作范围、切开组合字符的范围、重叠动作范围、重复附件 ID，以及非有限或非正的附件尺寸，返回可识别的 `LYGlyphTextDocumentError`。
- 对 NSAttributedString 输入，附件描述必须指向一个单独的 U+FFFC；不满足时拒绝。标准 NSTextAttachment 不自动变成 UIView，首版应通过本组件附件描述输入。
- 对分段输入，内部插入 U+FFFC 并自动形成附件范围；相邻动作不靠颜色、内容相同或字典相等性合并。
- 富文本支持字体、颜色、段落、kern、baselineOffset、underline、strikethrough、ligature 等声明能力；未知属性忽略，不保留原始属性字典，也不能由此宣称支持其特殊渲染。不得依赖 YYText 自定义属性。
- 纯文本缺少字体／颜色时补充 body 字体和 label 颜色；已有显式样式优先。普通高亮只改变颜色、背景或装饰，不改变字体与排版尺寸。

## 4. 统一布局与显示策略

### 4.1 排版、测量与缓存

- 将文档与配置规范化为独立 NSAttributedString，解析段落方向，使用 CTFramesetter／CTFrame 获取行及 baseline；不要用另一个 TextKit 引擎反算 Core Text 的点击位置。
- 将 Core Text 坐标转换为统一的 UIKit 左上原点坐标；内边距和垂直偏移只应用一次，绘制、附件、命中、无障碍共享该变换。
- 缓存存于单个 Label，最多保留最近两个宽度对应的布局，不使用无界全局缓存。键包含文档身份／修订、精确可用宽高约束、配置、显示缩放、字体内容大小与显示环境。
- 文档、有效尺寸、字体大小类别、界面样式或配置变化会失效布局；纯回调变化不会失效几何。颜色变化至少失效绘制。
- UIKit sizeThatFits、intrinsicContentSize 和实际展示使用同一个布局入口；SwiftUI 在相同宽度下复用该入口。无宽度约束时不强制软换行，保留原文显式换行；详细固有尺寸契约见第 4.2 节。
- 宽度为 0 时返回可用的零宽测量结果，不创建超大缓存；空文档内容尺寸为 0，加上明确配置的内边距。输出尺寸按 display scale 向上对齐像素。

### 4.2 Auto Layout 与尺寸适配

#### 4.2.1 UIKit 接口与优先级

- Label 继承 UIView，实现 intrinsicContentSize 与 sizeThatFits(_:)，支持 systemLayoutSizeFitting 的离屏测量流程。使用标准布局优先级，不新增自定义优先级体系。
- 默认两个方向 Hugging 为 .defaultLow，Compression Resistance 为 .defaultHigh；只在初始化设置。文档更新、configure、附件刷新和复用不能覆盖宿主修改的值。
- 固有宽度为不强制软换行时的内容理想宽度，保留显式换行；固有高度按有效宽度重新排版，并遵守 numberOfLines。图片与 View 附件的声明尺寸共同参与测量。
- 多行固有高度的宽度来源依次为：正值 preferredMaxLayoutWidth、正值 bounds.width、内容理想宽度。preferredMaxLayoutWidth 默认 0 表示自动模式。
- preferredMaxLayoutWidth 是包含 textContainerInset 的视图测量宽度，仅用于固有尺寸估算；实际展示始终按 bounds。宿主已有精确宽度时，可显式指定该值用于首次离屏估算；宽度变化时宿主同步更新显式值。
- sizeThatFits(_:) 使用传入的宽高约束，不读取旧 frame 代替测量宽度，不修改自身 frame／约束，不创建或安装附件视图。宽度约束为无限时使用内容理想宽度；0 宽度安全返回零宽结果。
- systemLayoutSizeFitting 在横向 fitting priority 为 required、宽度明确时，必须按该宽度得到正确高度，不能仅用旧 bounds 的固有高度返回结果；实现以测试验证此契约。
- 固有高度测量不受旧 bounds.height 限制。实际可见布局仍按最终 bounds 和行数限制处理；相同输入和相同约束共享同一个布局入口，不要求不同约束复用同一对象。
- 内边距只计入一次，尺寸按 display scale 向上对齐像素。空内容尺寸仅保留明确内边距；不返回 NaN 或无限尺寸。
- Required 外部宽高约束决定最终外框；压窄后按配置换行／尾部省略，高度不足时裁切，不自动缩小字体或附件，也不暗中增加行数限制。
- 绘制、高亮、附件和命中均受内容可见区域裁切；完全不可见附件不挂载，部分可见附件只在可见部分绘制／响应，裁切外不触发业务动作。

```swift
// 标准 UIView 优先级 API；实际约束场景见 AutoLayoutTests。
label.setContentHuggingPriority(.defaultLow, for: .horizontal)
label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
```

#### 4.2.2 失效与布局收敛

- 文档、附件尺寸、字体、行数、内边距、测量宽度变化时使布局缓存失效，并通知 invalidateIntrinsicContentSize／setNeedsLayout／setNeedsDisplay；仅颜色变化不必重算几何。
- 自动模式在 layoutSubviews 检测有效宽度变化后更新固有高度；相同输入、宽度和配置不重复失效。初始 0 宽度转正后必须恢复正常测量。
- 不在测量方法中调用 layoutIfNeeded，不在布局回调中反复添加／修改自身宽高约束；不以旧高度反向限制新固有高度。
- 普通测量不安装附件，不发送业务动作。布局替换清理旧高亮与命中映射；缓存仍限定每 Label 最多两个布局结果。

#### 4.2.3 宿主布局

- 支持原生 Auto Layout；宿主用 SnapKit 为组件设约束也可接入，组件本身不依赖 SnapKit。
- 支持左右约束／固定宽度驱动内容自动撑高，以及宽度上限；高度不固定时由固有尺寸决定，优先级仍服从宿主约束关系。
- 支持横向／纵向 UIStackView，通过 Hugging 和 Compression Resistance 决定拉伸／压缩。验收使用轴向合法的 fill、top、center、bottom，以及纵向对应的 leading／trailing 对齐。
- 首版不承诺 viewForFirstBaselineLayout／viewForLastBaselineLayout 与 UILabel 文字基线完全等价；暂不将 firstBaseline／lastBaseline 列为验收能力。
- 支持 UITableView 自动行高与 UICollectionView 自适应尺寸；宿主提供明确测量宽度、完整约束链及正常的列表尺寸失效通知，不由组件接管列表 delegate 或布局对象。
- 旋转、分屏和窗口缩放均根据容器宽度重排，不读取固定屏幕宽度；正文、附件、高亮及点击区域同步更新。

#### 4.2.4 SwiftUI 测量

- UIViewRepresentable.sizeThatFits 直接消费 proposal.width，不依赖旧 UIKit bounds；nil／无限宽度使用内容理想宽度，有限宽度据此排版，0 宽度安全返回零宽结果。
- 多行自适应高度按提议宽度测量，实际受限高度由展示层裁切；不将旧 frame 高度带入新固有高度计算。
- 测量期间不修改 Binding、SwiftUI 状态、宿主约束或附件；UIKit 与 SwiftUI 相同宽度、内容和配置下高度差不超过 1 个物理像素。
- layoutPriority 由 SwiftUI 宿主使用，不映射为 UIKit Hugging／Compression Resistance；不承诺两套布局系统具有相同优先级数值语义。
- 示例覆盖 .frame、HStack／VStack、List／LazyVStack 和宽度反复变化；同文档更新回调不失效布局。

### 4.3 截断与命中映射

- 首版只提供尾部省略，省略号继承可见末行的字体与颜色，不继承业务动作或附件属性。
- 用 CTLineCreateTruncatedLine 等 Core Text 排版结果建立最后一行的可见 run／glyph 片段与原文映射；不能只按整个 visibleRange 判断可点击性。
- 省略号本身及被省略的文字、附件不参与业务点击或无障碍动作。
- 分离排版使用的度量矩形和点击使用的可见片段矩形。先确认触点落入可见动作片段，再做字符定位；不能把“最近字符”当作命中成功。
- 默认不额外扩大点击范围，避免相邻动作串点。跨行动作保存多个矩形，不用一个覆盖行间空白的大外接矩形。
- 命中需处理 emoji、组合字符、ligature 和双向 run；多 glyph 形成的同一组合字符应映射到同一原文动作。

### 4.4 附件与显示

- UIImage 直接绘制；UIView 附件使用 U+FFFC 与 CTRunDelegate 预留空间，基线度量数据不持有 UIView。
- CTRunDelegate 回调上下文采用明确 retain／release 配对的不可变度量对象，不捕获 Label 或工厂。
- 采用 source line 的字体 ascender／descender 计算 top／center／bottom 对齐；附件高于字体时提升该行度量，避免裁切。
- 先计算布局，再根据可见附件 ID 对比增删宿主视图；不可见或被截断附件必须卸载。附件不能参与实际文字测量的反向反馈。
- 工厂返回 nil 时保留声明的占位尺寸与替代朗读文本，不触发无限重试。实际 View 变大不自动改变字行；通过更新文档尺寸重新排版。
- 允许附件内部 Auto Layout，但其外框由文本布局管理。UIImageView 作为真实 View 附件时，图片加载与动画由宿主负责。

### 4.5 触摸与取消

- 使用状态 idle → pressed(action + documentRevision + origin) → ended／cancelled；在按下与抬起时核对同一可见动作范围及文档版本。
- 手指移出动作范围、移动超过 10pt、父滚动手势接管、系统取消、文档／布局替换或视图移出 window 时清理按下状态，不触发 tap。
- 长按阈值 0.5s；成功后只发 longPress，抬起不能再发 tap。无回调时不吞普通区域触摸。
- 高亮只覆盖该动作的可见片段，不改变字号或布局。更新高亮不创建新的业务文档。
- `isInteractive` 的附件由子视图优先接收触摸，父容器不重复发送动作。装饰附件自身不响应；其 U+FFFC 可属于文字动作范围。
- 不使用整个 Label 的手势将任意空白位置转换成最近链接；UI 测试同时检查普通文字、行尾空白和行间空白。

### 4.6 SwiftUI 与无障碍

- UIViewRepresentable 的宽度与高度契约遵守第 4.2.4 节，不另建布局引擎或依赖旧 bounds 测量。
- updateUIView 总是刷新回调与 provider，即使文档未改变；文档为 nil 时清空旧内容。dismantleUIView 清理交互及附件。
- UIFontMetrics／文本样式元数据驱动 Dynamic Type；显式固定字号默认保持固定。动态字体发生变化时同时重新测量附件对齐。
- 将动态颜色在绘制时按当前 trait 解析；深色模式切换不修改业务文档。缓存更新不能残留旧颜色。
- VoiceOver 按文档语义顺序提供静态文本、可见动作和附件元素，避免父 Label 与子附件重复朗读。动作元素可激活同一业务 action，附件有替代文本；被截断内容不出现在可激活元素中。
- UIKit／SwiftUI 两个示例必须消费同一组文档，避免分别实现两套行为。

## 5. 分阶段实施与验收

### 5.0 连续执行队列

以下队列是后续执行顺序，阶段清单仍用于追踪细项。选取第一个未完成且依赖已满足的任务；完成契约／失败测试、实现、验证、证据、提交、集成和普通推送后自动进入下一项。仅真实阻塞决策、冲突或反复验证失败暂停相关任务；不可用环境标记未验证并继续独立工作。详情见 [连续开发计划](2026-10-20-continuous-development.md)。

| 顺序／任务 | 状态 | 依赖 | 验收范围 | 证据 |
|---|---|---|---|---|
| D0 规则与计划同步 | 已完成 | 现有基础显示／行数／UIImage | 规则一致、当前 API 准确、V1 契约明确；docs 通过后提交／集成／推送 | 本计划、AGENTS、CONTRIBUTING 与连续开发计划；docs 通过，提交 `160c3c4` 已合入并推送，远端 SHA 已核对 |
| V1 UIView／provider／生命周期／按钮自身交互 | 已完成 | D0 | 测量零工厂调用、可见复用／隐藏卸载、所有权与重入、SwiftUI 清理、真实按钮与列表复用；保留 72 项基线 | [专项记录](../../verification/2026-10-20-view-attachments.md)：102／102 Passed，八张截图已检查；`70e8340` 已合入并推送，远端 SHA 一致 |
| M1a segments／actions／范围校验 | 已完成 | V1 | 分段安全构建、UTF-16／组合字符／动作重叠校验、初始化快照与现有输入兼容 | [M1 契约](2026-10-20-document-actions-styles.md) 与 [专项记录](../../verification/2026-10-20-m1a-document.md)：127／127 Passed，两张共用样例截图；`b74a0cb` 已合入／推送、远端 SHA 一致；不提供文字交互 |
| M1b 样式／换行／统一展示几何 | 已完成 | M1a | 装饰、完整段落值、word／character、垂直对齐、最终可见片段与连字几何 | [M1 契约](2026-10-20-document-actions-styles.md) 与 [专项记录](../../verification/2026-10-20-m1b-styles.md)：215／215 Passed，10 张原图已检查；`6dbeaee` 已合入／推送，远端 SHA 一致 |
| I1 文本点击／长按／高亮／取消 | 已完成 | M1b | 真实手势、空白／截断／RTL 命中、单次回调与取消零事件、附件优先级 | [I1 契约](2026-10-20-text-interaction.md)与[执行记录](../../verification/2026-10-20-interaction.md)：276 宿主＋18 UI = 294／294；`003558c` 已合入并推送，远端 SHA 一致 |
| H1 宿主矩阵 | 已交付 `32ac04a` | I1 | StackView、UITableView／UICollectionView、.frame／HStack／VStack／List／LazyVStack、宽度切换与复用收敛 | [H1 契约](2026-10-21-host-matrix.md)与[执行记录](../../verification/2026-10-21-host-matrix.md)：319／319（298 宿主＋21 UI）、12 张截图；最终规格／质量批准，已集成推送并核远端 SHA |
| A1 显示环境／无障碍 | 已交付 `b615c3e`，人工 VO 待验 | H1 | Dynamic Type、明暗、RTL、可见元素语义与 VoiceOver；缺失环境独立标记 | [A1 计划](2026-10-21-environment-accessibility.md)与[专项记录](../../verification/2026-10-21-environment-accessibility.md)：359／359、8 张截图；人工 VoiceOver 未验证 |
| P1 回归／性能／发布准备 | 独立准备验收完成，发布补证待验 | A1；缺失环境不阻塞独立准备 | 九组Release／缓存与释放／真实列表、CPU与RSS、来源及API／安装审查已归档 | [P1 计划](2026-10-21-performance-readiness.md)；Swift6.0／iOS16／真机／人工VoiceOver与专用分配／泄漏分析未验证；PR／Tag／Release未授权 |

I1 已交付并保留 **294／294 Passed（276 宿主＋18 UI，0 failed／0 skipped／0 expected failures，`runtimeWarnings` 为空）** 的正式证据及 M1b 的 215 个基线测试方法。H1 功能验收完成，保留 **319／319 Passed（298 宿主＋21 UI，0 failed／skipped／expected failures，`runtimeWarnings` 为空）** 及 12 张截图；阶段 6 自动环境／AX 已验收，人工 VoiceOver 仍未勾选。H1 已完成最终审查和交付，[A1 计划](2026-10-21-environment-accessibility.md)以 `b615c3e` 完成交付，P1正式368／368与Release／滚动数据已验收，剩余按发布补证清单处理；A1 正式 359／359 已通过；自动环境与无障碍验收、人工 VoiceOver 分开记录。

阶段内按“建立测试／复现 → 实现最小行为 → 验证 → 更新记录 → 提交”执行。低影响文档调整不添加镜像实现的测试；布局、Unicode、交互及所有权必须有有意义的验证。各阶段提交须可单独审阅，不以空壳声明代替完成。

### 阶段 0：工程规范与工具

**输入：** 已归档资料、用户确定的技术路线、开发约定与布局契约。**输出：** 规范文档、固定格式配置及可运行的文档／格式检查入口；不创建组件空壳。

- [x] 建立 AGENTS、CODING_STYLE、CONTRIBUTING，更新 README 与本计划；当前交付约定为验证后自动提交、合入 main 并普通推送，历史阶段的实际推送情况按各自记录留证。
- [x] 建立 EditorConfig 与 SwiftFormat 0.59.1 配置，保留版权头；工具安装必须显式，普通检查不联网或自动下载。
- [x] 建立 docs／format 检查入口和工具回归测试，覆盖失效链接、检查范围、零 Swift 文件、工具缺失及版本不符。
- [x] 用真实固定版本工具验证临时 Swift 样例的失败→格式化→通过及幂等性，记录结果；阶段 0 时组件编译／运行尚未验证，后续证据另记。

**完成标准：** 文档与检查工具可用，Auto Layout 契约和验收完整；工具测试不冒充组件测试。执行记录保存于 docs/verification。

### 阶段 1：Package 与演示／测试宿主

**输入：** 本计划与阶段 0 的工程规范。**输出：** 可在 iOS Simulator 编译的 package、本地 package 示例、shared scheme、测试宿主。

- [x] 建立第 2 节的目录与 Swift 6／iOS 16 配置，设置零第三方依赖；建立最小公开文档与视图入口作为后续垂直实现起点。
- [x] 示例首页提供 UIKit、SwiftUI 两个入口；建立单一测试 fixture 数据文件供两端复用。
- [x] 提供短文、多行、混合样式、并排按钮和 UIKit／SwiftUI 宽度切换的真实示例；不添加尚未实现的列表或附件入口。
- [x] 提供 UIView 附件和 UITableView 复用示例；工厂、原生按钮、清空／重载与滚动已有真实 UI 场景。
- [ ] 后续提供完整 StackView、UICollectionView 和 SwiftUI 列表矩阵。
- [x] UIKit／SwiftUI 共用静态图片混排文档，可操作三种对齐、内容、宽度及行数；另提供共用 UIView 附件文档。
- [x] 配置 package scheme `LYGlyphText`、demo shared scheme `LYGlyphTextDemo`，测试使用 XCTest 并在 MainActor 调用 UIKit 代码。
- [x] 运行第 6 节的清单／构建／测试命令，记录实际 scheme 与目的地；只记录已运行结果。

**完成标准：** iOS Simulator 构建和最小宿主测试通过；无三方依赖、无 .m／.mm／.c 实现文件；README 明确仍为开发中。

### 阶段 2：文档模型、排版与测量

**输入：** 文档输入和容器约束。**输出：** 规范化快照、布局行与测量尺寸，无附件 View 创建。

- [x] 完成 attributedText 最小入口与明确附件错误；不可变文本／样式值隔离，测试调用方修改原 NSMutableAttributedString／NSMutableParagraphStyle 后显示保持不变。
- [x] 建立 Core Text 行布局、基线和 UTF-16 原文范围；验证空文本、中英文、家庭 emoji、组合重音、不同字号和基本方向。
- [x] 测量显式换行（包括纯换行）、空白、内边距、0／有限／无限宽度；高度不受旧展示高度限制。
- [x] 每 Label 最多两份布局缓存，内容／配置／trait 变化后失效；测量不创建 View。
- [x] 完成图片 attachments 字典输入，以 UTF-16 位置关联独立 U+FFFC；校验描述完整性、位置、唯一 ID 和有限正尺寸，继续拒绝标准 NSTextAttachment。
- [x] 完成 segments、actions 输入、UTF-16 数值／完整字符／重叠校验；官方 Swift range 转换与 CRLF 保护有测试，重复 ID 与相邻动作独立保留。
- [x] UIView 的全部测量入口与离屏布局 factory 次数为零；挂载／失败／卸载和重入有计数、weak 释放验证。
- [x] 扩展行距、完整已声明段落度量、字距／基线偏移／连字及背景／装饰样式，保留 typed 快照和极端数值防守。
- [x] 显示／截断范围补充家庭 emoji、肤色、旗帜、组合重音、混合方向及字符内属性分段测试。
- [x] 补齐 Unicode／双向文本的动作范围与真实点击矩阵；覆盖 ligature、emoji、组合字符、RTL／LTR、截断 token 与实际手势。

**完成标准：** 有限尺寸、不越界；在相同约束下测量与展示使用同一布局；重复内容不会被错误地认为同一动作实例。

### 阶段 3：文字绘制、截断与 Auto Layout

**输入：** 文档、布局与外部尺寸约束。**输出：** UIKit 富文本显示、固有尺寸、多行自动撑高及可见原文映射。

- [x] 在 UIView 绘制字体和前景色，像素测试确认实际彩色文字与高度裁切；示例核对换行。
- [x] 实现背景、下划线／删除线及 pattern／byWord 回退，真实像素覆盖透明合成、混合字号和正负基线。
- [x] 增加 `configuration.numberOfLines`（0／负值为无限行）与尾部省略；末行可见 UTF-16 区间不包含隐藏内容／生成省略号，组合字符内 run 片段合并；测试刚好容纳、只容纳／无法容纳省略号、混合方向及隐藏首 strong 的自然 RTL。
- [x] 测试 textContainerInset、垂直对齐、不同 display scale、宽度变化、非零 bounds origin；文字、装饰与两类附件共享变换，偏移不重复应用。
- [x] 图片附件覆盖内边距、宽度往返、非零 bounds 原点、高度压缩与三种垂直对齐；全部 UIImage 方向与声明尺寸有像素／几何测试。完整显示环境仍由 A1 验收。
- [x] 实现 intrinsicContentSize、sizeThatFits、preferredMaxLayoutWidth 和 systemLayoutSizeFitting 宽度驱动测量，覆盖左右／固定／上限约束与明确宽度的离屏测量。
- [x] 初始化标准 Hugging／Compression Resistance 默认值，测试优先级控制拉伸／压缩，更新文档不重置宿主值。
- [x] 实现有效宽度变化的固有尺寸失效，测试 0→正值、窄→宽→窄、旧高度不影响新高度及布局收敛；测量不调用 layoutIfNeeded 或安装附件。
- [x] 显式压缩高度后裁切文字，不自动缩字；sizeThatFits 不修改 frame／约束。
- [x] 验证高度裁切的高亮、动作与附件命中；绘制／几何单测和真实 UIKit／SwiftUI 短高度手势保留证据。
- [ ] 在演示中提供可见布局边界开关，用于人工检查，开关只属于示例／调试入口。

**完成标准：** 相同约束下测量与显示高度差不超过 1 个物理像素；Auto Layout 自动撑高、优先级及离屏测量通过，无新增约束冲突或反复布局；截断映射不包含隐藏内容。几何测试使用稳定系统字体和明确尺寸，视觉记录注明系统版本。

### 阶段 4：图片与真实 UIView 附件

**输入：** 附件描述和 MainActor 工厂。**输出：** 与文字共同换行的图片及真实子视图。

- [x] 实现度量 delegate 与图片绘制，验证三种对齐、超高／超宽附件、连续附件、行首／行尾附件和截断附件；隐藏高附件不撑高，省略号不继承附件属性。
- [x] 相同图片文档在两个 Label 独立显示／清空；声明尺寸更新使固有高度失效，UIKit／SwiftUI 同输入宽度／行数下高度差不超过一个物理像素。测量不创建子视图、不改变宿主优先级。
- [x] 实现按 ID 管理的宿主视图集合及 reloadAttachments；记录 factory 调用与释放次数。
- [x] 同时用两个 Label 展示相同文档，核对 View 实例独立；测试 nil 工厂结果、跨宿主错误返回和切换文档的卸载。
- [x] 示例包含静态 UIImage、UIImageView、按钮与自定义徽章；复用测试滚动／替换内容后不得残留旧附件。
- [x] UIView 附件尺寸变化更新固有高度；受限外框裁切附件及命中区域，测量阶段 factory 调用数始终为 0。

**完成标准：** 真实子视图在主线程安装；隐藏附件不挂载；无跨宿主抢占与明显 retain cycle；附件尺寸与 baseline 不受工厂实际 frame 反向影响。

### 阶段 5：局部交互与取消

**输入：** 可见动作片段及触摸序列。**输出：** 高亮与一次 tap／longPress 事件，或无事件的取消。

- [x] 实现第 4.5 节状态机；状态转换单测覆盖长按后抬起、文档中途更新、移出 window 和系统取消。
- [x] 使用实际几何命中测试覆盖跨行范围、相邻动作、重复 actionID、RTL／ligature、emoji 及部分截断范围。
- [x] 用 UI 测试验证点击、长按、滑动滚动和移出范围，不仅调用内部回调；检查行尾／行间空白不触发业务。
- [x] 验证交互附件只响应自身，装饰附件可交由所属文字动作；普通区域不阻断父列表的选择／滚动。

**完成标准：** 取消场景回调数为 0；长按成功回调数为 1 且无 tap；跨行高亮不覆盖行间空白；点击事件范围和 actionID 与原文一致。

### 阶段 6：宿主布局、SwiftUI、显示环境与 VoiceOver

**输入：** SwiftUI 宽度提议、环境和回调更新。**输出：** 两端行为一致的自适应组件。

- [x] 完成 make／update／sizeThatFits／dismantle；基础 .frame、理想／零／有限宽度、替换／清空文档及两端高度对比通过。
- [x] HStack／VStack／List／LazyVStack、完整宽度切换矩阵与回调更新：H1 正式回归通过，见宿主矩阵记录。
- [x] 横向／纵向 UIStackView 验证合法对齐方式、并排按钮和不同优先级；不以 UIView 默认基线代替 UILabel 文字基线适配。
- [x] UITableView 自动行高、UICollectionView 自适应及离屏测量覆盖长短文本替换、附件变化、0→正宽、旋转／分屏／窗口缩放；宿主提供确定宽度和完整约束链。
- [x] 在 List／LazyVStack 及 UIKit 列表中复用组件；测试附件和高亮状态不串行，更新过程不形成测量循环。
- [x] 验证 body／大字体／辅助功能字号，动态颜色明暗切换；更新字体后重新测量和对齐附件。A1 48 配置两端高度差 0pt。
- [x] 检查自动无障碍元素顺序、动作激活与附件替代文本；A1 自动化与真实 UI 完整回归通过。
- [ ] 实际启用 VoiceOver 人工验证朗读顺序、无重复朗读、停顿与焦点体验；自动 AX 验证不代替人工。

**完成标准：** UIKit 与 SwiftUI 相同宽度的高度差不超过 1 个物理像素；StackView／列表复用无旧状态和布局循环；SwiftUI 不残留旧回调；VoiceOver、Dynamic Type、深色模式均有独立证据。

### 阶段 7：回归、性能与发布

**输入：** 前六阶段的实现与证据。**本轮输出：** 发布准备、文档与完整验证记录；缺失环境单列发布阻塞，不创建版本或发布。

- [ ] 完成第 6 节矩阵；补齐最低 iOS 16 与最新可用系统的运行结果，最低系统无法获取时明确发布阻塞项，不伪造通过。
- [x] 在固定设备／模拟器和 Release 构建测量 100、1000、5000 个 UTF-16 单元，以及每条含 0／3／10 个附件的集合；P1九组2655原始ns、p50／p95、factory=0、RSS和真实滚动已归档。“冷”只指新Label首次测量，非进程冷启动。
- [x] 缓存最多两份、600轮真实窗口释放5400／5400、weak=0与三轮45秒滚动已验证；Time Profiler 35.61秒／31269样本已导出，RSS初／峰／末独立记录，不先许诺帧率。
- [ ] 补齐Allocations／Leaks专用统计结果解释：模板实际执行且trace已保存，但当前CLI未暴露专用表，Allocations录制器最终退出还存在控制器超时；不能由weak=0或RSS推导无泄漏。
- [x] 复核纯 Swift／零第三方运行依赖、来源与许可证、公开 API、README 本地Package安装和示例说明；见P1静态准备记录。
- [x] 完成CHANGELOG未发布草案和RELEASE_READINESS，列出验证环境、已知限制和发布阻塞项；未创建Tag或Release。
- [ ] 后续另行授权：达到发布门槛后创建首个版本 Tag／Release；此项不属于本轮连续开发执行范围，也不因发布准备完成而勾选。

**完成标准：** 无未说明的功能缺口；本地构建、设备运行、无障碍和性能证据分别列出；发布操作只在届时获得发布授权后执行，本文不代表立即发布组件。

## 6. 验证命令与场景

### 6.1 当前工程工具

```sh
scripts/verify.sh docs
scripts/verify.sh format
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/tests -v
```

docs 检查本地链接文件存在性、文本约定、Shell 语法及 diff，不验证远端网页或锚点。format 零 Swift 文件时必须报告“不适用”；有 Swift 文件但缺少固定工具时失败，不自动安装。具体安装／覆盖变量见 CONTRIBUTING。工具测试只证明检查行为，不是组件测试。

### 6.2 当前组件构建与测试

从仓库根目录运行。build 使用 XcodeGen 2.46.0 生成 Demo 工程，并构建 Package 与应用；test 显式传入独立可用的 Simulator UDID，保存日志和 xcresult。普通检查不下载工具。

```sh
swift package dump-package
scripts/verify.sh build
xcodebuild -list
xcodebuild -list -project Examples/LYGlyphTextDemo/LYGlyphTextDemo.xcodeproj
xcrun simctl list devices available
scripts/verify.sh test <UDID>
git diff --check
```

宿主 scheme 为 LYGlyphTextDemo，包含根 Tests 的 Package 测试源码、Demo 宿主测试和 UI 测试；一轮不再重复运行独立 Package test scheme。有效清单、BUILD SUCCEEDED、TEST SUCCEEDED 与非零测试数分别核查；macOS swift test 不能代替 UIKit 的 iOS Simulator 运行。命令和参数以 CONTRIBUTING 为准。

下表是完整首版验收矩阵；本轮已覆盖的子集单独记录在基础显示验证文档，不将整张矩阵提前标记通过。

| 场景组 | 必验场景 | 验证方法 |
|---|---|---|
| Unicode | 家庭 emoji、肤色、组合重音、旗帜、中文、阿拉伯语与英文混排 | 范围与布局单测 + 实际点击 |
| 样式与几何 | 混合字体、kern、baseline、段落／行距、内边距、垂直对齐 | 几何断言 + 固定环境截图 |
| 固有尺寸 | 单行自然尺寸、多行自动撑高、显式换行、内边距、preferredMaxLayoutWidth | 几何单测 + Auto Layout 宿主 |
| 约束与优先级 | 左右／固定／上限宽度，并排按钮，两个方向 Hugging／Compression Resistance，更新不重置 | 约束布局测试 + 示例 |
| 离屏测量 | systemLayoutSizeFitting 横向 required 宽度、旧 bounds 不影响结果 | XCTest 测量断言 |
| StackView | 横／纵向、合法 fill／top／center／bottom／leading／trailing，对比拉伸压缩 | 宿主布局测试 + Simulator |
| 列表自适应 | UITableView／UICollectionView，长短文本替换、附件尺寸变化、复用 | 宿主／UI 测试 |
| 宽度与收敛 | 0→正值、窄→宽→窄、旋转、分屏、窗口缩放，无反复失效 | 失效计数 + 宿主布局验证 |
| 高度裁切 | 显式压缩高度、附件部分可见、隐藏区域无动作、不自动缩字 | 绘制／命中测试 + 实际点击 |
| 截断 | 0／1／多行限制、跨行链接、隐藏附件、省略号附近 | 映射单测 + UI 点击 |
| 空白 | 普通文字、行尾、行间、Label 内边距 | UI 测试，回调数为 0 |
| 取消 | 移出、超过 10pt、滚动接管、系统 cancel、文档替换、移出 window | 状态机测试 + UI 手势 |
| 附件 | 三种对齐、超过字体高度、两个宿主、nil 工厂、重复 ID、复用 | 所有权／生命周期测试 + 人工检查 |
| SwiftUI | nil／0／有限／无限 proposal、.frame、HStack／VStack、List／LazyVStack、替换闭包、清空内容 | 测量／UI 测试，与 UIKit 高度差≤1物理像素 |
| 环境 | 明暗模式、内容大小类别、VoiceOver、display scale | trait 测试 + 实际人工操作 |
| 兼容性 | Swift 6 mode、新工具链、最低 iOS 16、最新可用系统 | 编译与系统运行分开留证 |
| 性能 | 固定负载、冷／热缓存、附件数量、持续滚动、释放 | XCTest 性能数据 + Instruments |

验证记录包含日期、Git commit、Xcode／Swift 版本、系统 runtime、设备／模拟器、构建配置、执行命令、结果与证据位置。失败不能通过缩小原定范围或更改 fixture 逃避。

## 7. 参考材料与设计取舍

- [参考库清单与校验](../../REFERENCES.md) 记录本地参考源码的上游与确切快照。
- 借鉴 YYLabel 的“容器 → 布局 → 绘制 → 主线程附件”分层和高亮属性思路，不逐行移植旧线程模型或历史系统补丁。
- BSText 是 Swift 实现参考，不是 Swift 6 兼容性或最小系统行为的既有验证证据；SwiftyText 包含 Objective-C 渲染实现，且本次快照未发现明确开源许可证，不直接移植。
- ActiveLabel／Atributika 主要参考文本识别与交互；AttributedString 的 UIView 附件能力依赖 UITextView，不能直接代替本设计。
- TextKit 2 的官方附件支持可作为未来编辑／选择需求的重新评估路线；首版不同时维护第二套排版引擎。

Apple 原始资料：

- [Core Text](https://developer.apple.com/documentation/coretext)
- [CTRunDelegate](https://developer.apple.com/documentation/coretext/ctrundelegate)
- [NSTextAttachmentViewProvider](https://developer.apple.com/documentation/uikit/nstextattachmentviewprovider)
- [UIViewRepresentable.sizeThatFits](https://developer.apple.com/documentation/swiftui/uiviewrepresentable/sizethatfits(_:uiview:context:))
- [UIFontMetrics](https://developer.apple.com/documentation/uikit/uifontmetrics)
- [UIView.intrinsicContentSize](https://developer.apple.com/documentation/uikit/uiview/intrinsiccontentsize)
- [UIView.sizeThatFits](https://developer.apple.com/documentation/uikit/uiview/sizethatfits(_:))
- [UIView.systemLayoutSizeFitting](https://developer.apple.com/documentation/uikit/uiview/systemlayoutsizefitting(_:withhorizontalfittingpriority:verticalfittingpriority:))

## 8. 当前证据与后续更新

| 项目 | 2026-10-21 状态 |
|---|---|
| 产品命名、公开可见性、工作区位置 | 已由用户确定 |
| 本地参考库来源与校验 | 见 REFERENCES.md，本阶段归档交付 |
| 文档与仓库初始化 | 已完成；本轮更新工程规范和布局契约 |
| 阶段 0 工程工具 | 见 [工程验收记录](../../verification/2026-10-20-engineering.md)，不代表组件测试 |
| 本机工具链探测 | Xcode 27.1（27A9275），Apple Swift 6.4；仅说明工具链存在 |
| Package、组件源码、Demo | 基础显示、行数限制／尾部省略、UIImage／UIView 附件及文字动作已实现；宿主矩阵已完成红绿、完整回归和截图验收；自动无障碍与显示环境已完成；人工 VoiceOver 和发布准备仍独立验收 |
| Swift 6 组件编译与测试 | Xcode 27.1／Swift 6.4 的 v6 模式构建和 P1 368／368 宿主／UI 测试，见 P1 验证记录；Swift 6.0 编译器仍未验证 |
| Auto Layout／布局优先级／SwiftUI 基础尺寸 | H1 覆盖 StackView／列表／五种 SwiftUI 容器；完整回归及 12 张截图通过，首／末文字基线未承诺 |
| iOS 16／当前系统运行 | iOS 16 未验证；本轮 iOS 27.0 专用 Simulator 运行，见基础显示验证记录 |
| 自动 AX／人工 VoiceOver、性能、真实设备行为 | 自动可见语义／激活与真实 UI 通过；P1 Release／CPU／RSS已归档；人工VoiceOver、真机和专用分配／泄漏分析仍未验证 |

行数限制专项与截图见 [行数限制验证记录](../../verification/2026-10-20-line-limits.md)，图片专项见 [图片附件验证记录](../../verification/2026-10-20-image-attachments.md)，UIView 工厂与生命周期见 [专项验证记录](../../verification/2026-10-20-view-attachments.md)，装饰与动作几何、绘制及真实手势见 [I1 验证记录](../../verification/2026-10-20-interaction.md)。完整 VoiceOver 行内语义未验收。

后续完成一个阶段时，只勾选有证据的任务，并在提交说明中写明行为变化、测试与限制。首版发布前不得把本文的预期行为写成既成事实。
