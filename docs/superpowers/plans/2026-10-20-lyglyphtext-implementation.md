# LYGlyphText Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. 如执行环境不提供该技能，按本文阶段顺序和验收清单执行；阶段失败时先修正，不跳过验收。

**Goal:** 实现支持局部文本交互、行内图片与自定义 UIView 附件的独立只读富文本 Swift Package，同时服务 UIKit 与 SwiftUI。

**Architecture:** 使用 Core Text 生成统一布局结果，供测量、绘制、截断、附件定位与命中检测共同使用。UIKit 自定义 UIView 为展示内核，SwiftUI 通过 UIViewRepresentable 包装。首版在 MainActor 同步排版，按明确失效条件复用有界缓存。

**Tech Stack:** iOS 16+、Swift 6 language mode、UIKit、SwiftUI、Core Text、Core Graphics、XCTest、Swift Package Manager。

**状态与日期：** 2026-10-20；本文是待实施规范。当前仓库仅包含文档、许可证与忽略规则；以下组件、示例、测试和发布阶段均未完成。

---

## 1. 范围与完成定义

### 1.1 首版能力

- 富文本字体、前景／背景色、字距、基线偏移、段落样式、下划线与删除线。
- 多行排版、字符／单词换行、内边距、行数限制与尾部省略；从左至右及从右至左的水平文本。
- 分段文本与基于 NSAttributedString 的输入，动作使用稳定 ID，点击／长按统一向宿主回调。
- UIImage 图片附件，以及通过工厂创建的 UIImageView、UIButton、自定义 UIView 附件。
- 按下高亮、取消清理、滚动容器协作、附件交互优先级和列表复用。
- UIKit 尺寸适配、SwiftUI 宽度驱动测量、深色模式、Dynamic Type 与基础 VoiceOver。

### 1.2 首版不包含

编辑器、输入法、文本选择复制、竖排、任意排版路径与绕排、HTML／Markdown 解析、文本阴影／描边等扩展特效、动画排版、后台排版与异步渲染、内嵌任意 SwiftUI View、网络图片下载器。网络图片由宿主加载到附件视图；改变排版尺寸必须显式更新文档。

### 1.3 发布完成定义

七个实施阶段均有对应代码、自动检查和验收记录；最低系统真实运行结果与最新可用系统结果分别记录。所有未实际运行的环境标记为“未验证”，不能由新 SDK 编译、静态阅读或模拟回调推导通过。

## 2. 项目与代码边界

仓库为 `KahnLi-lyc/LYGlyphText`，公开、默认分支 main；产品与模块统一命名 LYGlyphText。工作区总目录不初始化 Git，第三方参考库不属于本仓库。

后续编码阶段创建如下结构，本次文档阶段不创建这些文件：

```text
Package.swift
Sources/LYGlyphText/
  Document/       文档、分段、动作、附件与输入转换
  Layout/         Core Text 排版、截断、矩形查询及缓存键（internal）
  UIKit/          Label、附件宿主、触摸状态、无障碍
  SwiftUI/        UIViewRepresentable 包装
Tests/LYGlyphTextTests/
Examples/LYGlyphTextDemo/
  LYGlyphTextDemo.xcodeproj
  LYGlyphTextDemo/       UIKit 与 SwiftUI 示例
  LYGlyphTextDemoTests/  带宿主测试
  LYGlyphTextDemoUITests/ 交互测试
```

- Swift tools 版本设为 6.0，Swift language mode 设为 v6，最低部署版本 iOS 16.0；首版仅支持 iOS／UIKit。
- 单一 library product 与单一业务 target，零第三方运行依赖；Apple 系统框架不属于第三方源码。
- 示例工程包含名为 LYGlyphTextDemo 的 shared scheme，通过本地 package 引用组件；示例不进入 library target。
- Core Text 与 UIKit/Core Foundation 类型可在 Swift 中调用；纯 Swift 不意味着不能调用 Apple 的 C／Objective-C 系统 API。
- 未来功能改动使用 `codex/` 前缀分支；初始化文档按已授权计划提交到 main。

## 3. 接口契约

下面定义首版 API 的责任与最低必要字段；实现必须遵守这些输入输出与语义，不引入业务路由、全局单例或网络服务。

| 类型／入口 | 契约 |
|---|---|
| `LYGlyphTextDocument` | 不可变文档快照。公开初始化入口 `init(segments:) throws` 与 `init(attributedText:actions:attachments:) throws`；对 NSAttributedString 及其可变样式对象作隔离复制。包含文本、样式、动作与附件描述，不包含 UIView 或业务闭包。 |
| `LYGlyphTextSegment` | 文本段使用 attributed text 与可选 actionID；附件段使用 attachment 描述与可选 actionID。分段构建器自动累计 UTF-16 范围，使业务无需手写 NSRange。 |
| `LYGlyphTextAction` | 包含非空 actionID、非空 NSRange 和按下样式。一个范围对应一个动作；不同范围可使用同一 actionID，回调保留具体范围。动作范围不得相互重叠。 |
| `LYGlyphTextAttachment` | 包含文档内唯一 attachmentID、内容类型（UIImage 或 view 标识）、明确 size、相对字体的 top／center／bottom 对齐、contentInsets、替代朗读文本、是否由附件自身交互。UIView 只由宿主提供。 |
| `LYGlyphTextConfiguration` | 包含 textContainerInset、numberOfLines、word／character wrapping 与 top／center／bottom 垂直对齐。默认 0 内边距、0 行限制、word wrapping、top 对齐；有行数限制时尾部省略。 |
| `LYGlyphTextLabel: UIView` | `document`、`configuration`、`onAction`、`viewProvider` 和 UIKit 尺寸接口。`document == nil` 清空文本、附件、交互及无障碍元素。`preferredMaxLayoutWidth` 为 UIKit 多行固有尺寸提供显式宽度。 |
| `LYGlyphTextView: UIViewRepresentable` | 初始化输入与 Label 一致：document、configuration、onAction、viewProvider；实现 makeUIView、updateUIView、sizeThatFits、dismantleUIView。 |
| `LYGlyphTextActionEvent` | 输出 actionID、原文 UTF-16 range、可见片段矩形数组，以及 tap／longPress 类型。矩形坐标属于展示视图本地坐标，不向业务暴露 CTLine／CTRun。 |
| `LYGlyphTextLayout` | internal；保存容器约束、排版行、基线、可见原文区间、附件矩形、动作片段矩形与截断映射，不能成为公开 ABI。 |

### 3.1 线程与所有权

- 文档构造及 UIKit 相关公开接口采用 `@MainActor` 隔离。不可变不等于 Sendable：文档包含 UIKit 属性对象，首版不声明它可跨 actor 传递。
- `viewProvider` 的调用、UIView 创建／挂载／卸载、onAction 和 SwiftUI 更新均在 MainActor。
- 工厂按 view 标识返回宿主独占的新 UIView。相同文档在两个 Label 展示时必须得到不同实例；检测到返回已有其他 superview 的实例时拒绝挂载并报告诊断，不抢走其他宿主的视图。
- 工厂只在可见附件首次出现或 provider 明确失效后调用；普通测量不创建 UIView。Label 提供 `reloadAttachments()` 显式更新工厂结果。
- 文档与 Layout 不保留业务回调；View 销毁、替换文档或 SwiftUI dismantle 时释放回调与工厂持有关系。
- 不通过大范围 `@unchecked Sendable`、`nonisolated(unsafe)` 或降低并发检查强度来换取编译通过。

### 3.2 范围与输入失败

- NSString、NSAttributedString、Core Text 内部索引统一以 UTF-16 为单位，Swift String.Index 必须通过官方转换与原字符串关联。
- 入口拒绝越界、整数溢出、空动作范围、切开组合字符的范围、重叠动作范围、重复附件 ID，以及非有限或非正的附件尺寸，返回可识别的 `LYGlyphTextDocumentError`。
- 对 NSAttributedString 输入，附件描述必须指向一个单独的 U+FFFC；不满足时拒绝。标准 NSTextAttachment 不自动变成 UIView，首版应通过本组件附件描述输入。
- 对分段输入，内部插入 U+FFFC 并自动形成附件范围；相邻动作不靠颜色、内容相同或字典相等性合并。
- 富文本支持字体、颜色、段落、kern、baselineOffset、underline、strikethrough、ligature 等声明能力；未知属性可保留，但不能由此宣称支持其特殊渲染。不得依赖 YYText 自定义属性。
- 纯文本缺少字体／颜色时补充 body 字体和 label 颜色；已有显式样式优先。普通高亮只改变颜色、背景或装饰，不改变字体与排版尺寸。

## 4. 统一布局与显示策略

### 4.1 排版、测量与缓存

- 将文档与配置规范化为独立 NSAttributedString，解析段落方向，使用 CTFramesetter／CTFrame 获取行及 baseline；不要用另一个 TextKit 引擎反算 Core Text 的点击位置。
- 将 Core Text 坐标转换为统一的 UIKit 左上原点坐标；内边距和垂直偏移只应用一次，绘制、附件、命中、无障碍共享该变换。
- 缓存存于单个 Label，最多保留最近两个宽度对应的布局，不使用无界全局缓存。键包含文档身份／修订、精确可用宽高约束、配置、显示缩放、字体内容大小与显示环境。
- 文档、有效尺寸、字体大小类别、界面样式或配置变化会失效布局；纯回调变化不会失效几何。颜色变化至少失效绘制。
- UIKit sizeThatFits、intrinsicContentSize 和实际展示使用同一个布局入口。无明确测量宽度时返回单行理想尺寸；多行 Auto Layout 使用 preferredMaxLayoutWidth 或实际 bounds 宽度，不在 layoutSubviews 中反复更改自身约束。
- 宽度为 0 时返回可用的零宽测量结果，不创建超大缓存；空文档内容尺寸为 0，加上明确配置的内边距。输出尺寸按 display scale 向上对齐像素。

### 4.2 截断与命中映射

- 首版只提供尾部省略，省略号继承可见末行的字体与颜色，不继承业务动作或附件属性。
- 用 CTLineCreateTruncatedLine 等 Core Text 排版结果建立最后一行的可见 run／glyph 片段与原文映射；不能只按整个 visibleRange 判断可点击性。
- 省略号本身及被省略的文字、附件不参与业务点击或无障碍动作。
- 分离排版使用的度量矩形和点击使用的可见片段矩形。先确认触点落入可见动作片段，再做字符定位；不能把“最近字符”当作命中成功。
- 默认不额外扩大点击范围，避免相邻动作串点。跨行动作保存多个矩形，不用一个覆盖行间空白的大外接矩形。
- 命中需处理 emoji、组合字符、ligature 和双向 run；多 glyph 形成的同一组合字符应映射到同一原文动作。

### 4.3 附件与显示

- UIImage 直接绘制；UIView 附件使用 U+FFFC 与 CTRunDelegate 预留空间，基线度量数据不持有 UIView。
- CTRunDelegate 回调上下文采用明确 retain／release 配对的不可变度量对象，不捕获 Label 或工厂。
- 采用 source line 的字体 ascender／descender 计算 top／center／bottom 对齐；附件高于字体时提升该行度量，避免裁切。
- 先计算布局，再根据可见附件 ID 对比增删宿主视图；不可见或被截断附件必须卸载。附件不能参与实际文字测量的反向反馈。
- 工厂返回 nil 时保留声明的占位尺寸与替代朗读文本，不触发无限重试。实际 View 变大不自动改变字行；通过更新文档尺寸重新排版。
- 允许附件内部 Auto Layout，但其外框由文本布局管理。UIImageView 作为真实 View 附件时，图片加载与动画由宿主负责。

### 4.4 触摸与取消

- 使用状态 idle → pressed(action + documentRevision + origin) → ended／cancelled；在按下与抬起时核对同一可见动作范围及文档版本。
- 手指移出动作范围、移动超过 10pt、父滚动手势接管、系统取消、文档／布局替换或视图移出 window 时清理按下状态，不触发 tap。
- 长按阈值 0.5s；成功后只发 longPress，抬起不能再发 tap。无回调时不吞普通区域触摸。
- 高亮只覆盖该动作的可见片段，不改变字号或布局。更新高亮不创建新的业务文档。
- `isInteractive` 的附件由子视图优先接收触摸，父容器不重复发送动作。装饰附件自身不响应；其 U+FFFC 可属于文字动作范围。
- 不使用整个 Label 的手势将任意空白位置转换成最近链接；UI 测试同时检查普通文字、行尾空白和行间空白。

### 4.5 SwiftUI 与无障碍

- UIViewRepresentable.sizeThatFits 使用 proposal.width 调用同一测量入口；nil 宽度使用理想尺寸，有限非负宽度按提议值测量；测量不得修改 Binding 或 SwiftUI 状态。
- updateUIView 总是刷新回调与 provider，即使文档未改变；文档为 nil 时清空旧内容。dismantleUIView 清理交互及附件。
- UIFontMetrics／文本样式元数据驱动 Dynamic Type；显式固定字号默认保持固定。动态字体发生变化时同时重新测量附件对齐。
- 将动态颜色在绘制时按当前 trait 解析；深色模式切换不修改业务文档。缓存更新不能残留旧颜色。
- VoiceOver 按文档语义顺序提供静态文本、可见动作和附件元素，避免父 Label 与子附件重复朗读。动作元素可激活同一业务 action，附件有替代文本；被截断内容不出现在可激活元素中。
- UIKit／SwiftUI 两个示例必须消费同一组文档，避免分别实现两套行为。

## 5. 分阶段实施与验收

阶段内按“建立测试／复现 → 实现最小行为 → 验证 → 更新记录 → 提交”执行。低影响文档调整不添加镜像实现的测试；布局、Unicode、交互及所有权必须有有意义的验证。各阶段提交须可单独审阅，不以空壳声明代替完成。

### 阶段 1：Package 与演示／测试宿主

**输入：** 本计划和空的文档仓库。**输出：** 可在 iOS Simulator 编译的 package、本地 package 示例、shared scheme、测试宿主。

- [ ] 建立第 2 节的目录与 Swift 6／iOS 16 配置，设置零第三方依赖；建立最小公开文档与视图入口作为后续垂直实现起点。
- [ ] 示例首页提供 UIKit、SwiftUI 两个入口；建立单一测试 fixture 数据文件供两端复用。
- [ ] 配置 package scheme `LYGlyphText`、demo shared scheme `LYGlyphTextDemo`，测试使用 XCTest 并在 MainActor 调用 UIKit 代码。
- [ ] 运行第 6 节的清单／构建／测试命令，记录实际 scheme 与目的地；只记录已运行结果。

**完成标准：** iOS Simulator 构建和最小宿主测试通过；无三方依赖、无 .m／.mm／.c 实现文件；README 明确仍为开发中。

### 阶段 2：文档模型、排版与测量

**输入：** 文档输入和容器约束。**输出：** 规范化快照、布局行与测量尺寸，无附件 View 创建。

- [ ] 完成第 3 节的两类文档入口、安全范围转换、错误类型与复制隔离；测试 caller 修改原 NSMutableAttributedString／NSMutableParagraphStyle 不影响已创建文档。
- [ ] 建立 Core Text 行布局及统一坐标；测试空文本、有限宽度、长单词、中英文、段落方向、行距和不同字号。
- [ ] 实现有界布局缓存与失效；比较测量前后 factory 调用次数，确保测量不安装 View。
- [ ] 测试 NSString 的 UTF-16 长度与 Swift Character 数量不同的字符串，覆盖家庭 emoji、肤色修饰、组合重音、旗帜。

**完成标准：** 有限尺寸、不越界；在相同约束下测量与展示使用同一布局；重复内容不会被错误地认为同一动作实例。

### 阶段 3：文字绘制、行数与截断

**输入：** 文档与布局。**输出：** UIKit 富文本显示、像素对齐尺寸及可见原文映射。

- [ ] 在 UIView 绘制支持的文字属性、背景与装饰；对比 fixture 的预期行数、基线和尺寸。
- [ ] 增加行数限制与尾部省略，构造最后一行的映射；测试刚好容纳、只容纳省略号和混合方向文本。
- [ ] 测试 textContainerInset、垂直对齐、不同 display scale、宽度变化、非零 bounds origin；验证坐标偏移没有重复应用。
- [ ] 在演示中提供可见布局边界开关，用于人工检查，开关只属于示例／调试入口。

**完成标准：** 测量与显示高度差不超过 1 个物理像素；截断映射不包含隐藏内容；几何测试使用稳定系统字体和明确尺寸，视觉记录注明系统版本。

### 阶段 4：图片与真实 UIView 附件

**输入：** 附件描述和 MainActor 工厂。**输出：** 与文字共同换行的图片及真实子视图。

- [ ] 实现度量 delegate 与图片绘制，验证三种对齐、超高附件、连续附件、行尾附件和截断附件。
- [ ] 实现按 ID 管理的宿主视图集合及 reloadAttachments；记录 factory 调用与释放次数。
- [ ] 同时用两个 Label 展示相同文档，核对 View 实例独立；测试 nil 工厂结果、跨宿主错误返回和切换文档的卸载。
- [ ] 示例包含静态 UIImage、UIImageView、按钮与自定义徽章；复用测试滚动／替换内容后不得残留旧附件。

**完成标准：** 真实子视图在主线程安装；隐藏附件不挂载；无跨宿主抢占与明显 retain cycle；附件尺寸与 baseline 不受工厂实际 frame 反向影响。

### 阶段 5：局部交互与取消

**输入：** 可见动作片段及触摸序列。**输出：** 高亮与一次 tap／longPress 事件，或无事件的取消。

- [ ] 实现第 4.4 节状态机；状态转换单测覆盖长按后抬起、文档中途更新、移出 window 和系统取消。
- [ ] 使用实际几何命中测试覆盖跨行范围、相邻动作、重复 actionID、RTL／ligature、emoji 及部分截断范围。
- [ ] 用 UI 测试验证点击、长按、滑动滚动和移出范围，不仅调用内部回调；检查行尾／行间空白不触发业务。
- [ ] 验证交互附件只响应自身，装饰附件可交由所属文字动作；普通区域不阻断父列表的选择／滚动。

**完成标准：** 取消场景回调数为 0；长按成功回调数为 1 且无 tap；跨行高亮不覆盖行间空白；点击事件范围和 actionID 与原文一致。

### 阶段 6：SwiftUI、显示环境与 VoiceOver

**输入：** SwiftUI 宽度提议、环境和回调更新。**输出：** 两端行为一致的自适应组件。

- [ ] 完成 make／update／sizeThatFits／dismantle，测试 nil／0／有限宽度、窄宽反复切换，以及同文档下替换回调。
- [ ] 在 List／LazyVStack 及 UIKit 列表中复用组件；测试附件和高亮状态不串行，更新过程不形成测量循环。
- [ ] 验证 body／大字体／辅助功能字号，动态颜色明暗切换；更新字体后重新测量和对齐附件。
- [ ] 检查无障碍元素顺序、动作激活与附件替代文本；实际启用 VoiceOver 人工验证无重复朗读。

**完成标准：** UIKit 与 SwiftUI 相同宽度的测量一致；SwiftUI 不残留旧回调；VoiceOver、Dynamic Type、深色模式均有独立证据。

### 阶段 7：回归、性能与发布

**输入：** 前六阶段的实现与证据。**输出：** 可发布版本、文档与完整验证记录。

- [ ] 完成第 6 节矩阵；补齐最低 iOS 16 与最新可用系统的运行结果，最低系统无法获取时明确发布阻塞项，不伪造通过。
- [ ] 在固定设备／模拟器和 Release 构建测量 100、1000、5000 个 UTF-16 单元，以及每条含 0／3／10 个附件的集合；记录冷排版、热缓存的 p50／p95、factory 次数、内存与滚动表现。
- [ ] 用 Instruments 检查附件释放与持续滚动内存趋势；缓存占用必须符合“每 Label 最多两个布局”的约束，不先许诺未经测量的帧率。
- [ ] 复核纯 Swift／零第三方运行依赖、来源与许可证、公开 API、README 安装和示例说明；只有验证完成后新增真实可用的安装指引。
- [ ] 更新版本记录并创建首个 `0.1.0` tag／release，发布说明列出验证环境和已知限制。

**完成标准：** 无未说明的功能缺口；本地构建、设备运行、无障碍和性能证据分别列出；发布操作只在届时获得发布授权后执行，本文不代表立即发布组件。

## 6. 验证命令与场景

以下命令仅适用于对应代码与工程已经创建之后，当前文档仓库不能运行组件构建。所有测试命令从仓库根目录执行；使用实际存在的 iOS Simulator UDID，不填入不存在的设备名称。

```sh
swift package dump-package
xcodebuild -list
xcodebuild -list -project Examples/LYGlyphTextDemo/LYGlyphTextDemo.xcodeproj
xcrun simctl list devices available
xcodebuild -scheme LYGlyphText -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/LYGlyphText-Build build SWIFT_VERSION=6 CODE_SIGNING_ALLOWED=NO
xcodebuild -showdestinations -project Examples/LYGlyphTextDemo/LYGlyphTextDemo.xcodeproj -scheme LYGlyphTextDemo
```

测试目的地通过 `LYGLYPHTEXT_SIMULATOR_ID` 指定为上一步列出的可用 UDID，并保存环境记录。该变量不覆盖任何系统环境变量。

```sh
test -n "$LYGLYPHTEXT_SIMULATOR_ID"
xcodebuild -scheme LYGlyphText -destination "platform=iOS Simulator,id=$LYGLYPHTEXT_SIMULATOR_ID" -derivedDataPath /tmp/LYGlyphText-PackageTests test SWIFT_VERSION=6 CODE_SIGNING_ALLOWED=NO
xcodebuild -project Examples/LYGlyphTextDemo/LYGlyphTextDemo.xcodeproj -scheme LYGlyphTextDemo -destination "platform=iOS Simulator,id=$LYGLYPHTEXT_SIMULATOR_ID" -derivedDataPath /tmp/LYGlyphText-DemoTests test SWIFT_VERSION=6 CODE_SIGNING_ALLOWED=NO
git diff --check
```

预期分别为有效 package 清单、明确 scheme／目的地、`BUILD SUCCEEDED`、`TEST SUCCEEDED` 和无空白错误。`swift test` 在 macOS 宿主上不能代替依赖 UIKit 的 iOS Simulator 测试。

| 场景组 | 必验场景 | 验证方法 |
|---|---|---|
| Unicode | 家庭 emoji、肤色、组合重音、旗帜、中文、阿拉伯语与英文混排 | 范围与布局单测 + 实际点击 |
| 样式与几何 | 混合字体、kern、baseline、段落／行距、内边距、垂直对齐 | 几何断言 + 固定环境截图 |
| 截断 | 0／1／多行限制、跨行链接、隐藏附件、省略号附近 | 映射单测 + UI 点击 |
| 空白 | 普通文字、行尾、行间、Label 内边距 | UI 测试，回调数为 0 |
| 取消 | 移出、超过 10pt、滚动接管、系统 cancel、文档替换、移出 window | 状态机测试 + UI 手势 |
| 附件 | 三种对齐、超过字体高度、两个宿主、nil 工厂、重复 ID、复用 | 所有权／生命周期测试 + 人工检查 |
| SwiftUI | nil／0／有限 proposal、宽度变化、List 复用、替换闭包、清空内容 | 测量测试 + 演示 UI 测试 |
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

## 8. 当前证据与后续更新

| 项目 | 2026-10-20 状态 |
|---|---|
| 产品命名、公开可见性、工作区位置 | 已由用户确定 |
| 本地参考库来源与校验 | 见 REFERENCES.md，本阶段归档交付 |
| 文档与仓库初始化 | 本阶段交付范围 |
| 本机工具链探测 | Xcode 27.1（27A9275），Apple Swift 6.4；仅说明工具链存在 |
| Package、组件源码、Demo | 未实现 |
| Swift 6 组件编译与测试 | 未执行：无组件代码 |
| iOS 16／最新系统运行 | 未验证 |
| VoiceOver、性能、真实设备行为 | 未验证 |

后续完成一个阶段时，只勾选有证据的任务，并在提交说明中写明行为变化、测试与限制。首版发布前不得把本文的预期行为写成既成事实。
