# I1 文字交互验证记录

日期：2026-10-20 起，2026-10-21 恢复执行。当前在 `codex/text-interactions`，C1—C4 已完成并通过规格与质量审查，C5 正式检查已通过，**尚未提交、集成或推送 I1**。沿用同一未提交工作区；Git 交付完成后按路线图进入 H1。正式契约见 [I1 计划](../superpowers/plans/2026-10-20-text-interaction.md)。

## 已确认起点

前置 M1b 提交 `6dbeaeeade114c63dac8574e11b0860488882b15` 已快进合入本地 main、普通推送成功，远端 SHA 核对一致；原临时分支已删除。回归基线为 215／215（206 宿主＋9 UI），证据见 [M1b 记录](2026-10-20-m1b-styles.md)。此基线包含样式和可见几何，不证明文字手势已提供。

## 当前实施范围

C1 先建立不可变最终源几何、glyph 归属、动作索引与输出事件值，将装饰准备移出 draw；随后 C2 迁移按下颜色绘制，C3 接入识别器／取消／最新回调，C4 完成真实两端手势与父列表协作，C5 正式回归和交付。每块串行进行规格及质量审查。

## C1 失败证据与实施中结果

行为红测试保存在 `.build/verification/c1-red-behavior/Tests.xcresult`：`ActionGeometryTests/testRealLigatureKeepsSeparateSameIDActionsAndHalfOpenBoundary()` 实际使用 Baskerville 的 fi 连字，先确认 glyph 数小于字符数，再断言两个同 ID 动作独立且共享半开边界。旧动作索引返回 0 项／缺少矩形，1 项测试出现 2 个断言失败；根代理独立读取结果确认 1 失败、0 通过／跳过。此前 `.build/verification/c1-red/` 是隔离编译错误，仅保留诊断，不作为行为失败证据。

扩展测试捕获了行末 U+200B 的真实缺口：缺少独立 glyph 的忽略字符可能与前一个字形共享 source coverage，caret offset 并不能证明它占有可点击宽度；双向边界的 primary／secondary 也可能不同。定向失败证据为 `.build/verification/c1-zero-probe/Tests.xcresult`，1 测试／2 断言失败。修正联合实际 glyph 起点归属与忽略字符的零 advance 判断，不改变正常 fi 分区。

最终针对性绿结果为 `.build/verification/c1-zero-target-green/Tests.xcresult`：63／63（14 动作几何＋17 原几何＋32 装饰），0 failed／skipped／runtime warnings；根代理独立读取确认。覆盖 leading／internal／trailing、RTL 的 6 种零宽字符夹具及真实 fi／emoji 回归。

C1 完整宿主结果为 `.build/verification/c1-host-accepted/Tests.xcresult`：220／220，0 failed／skipped／runtime warnings，根代理独立读取确认；原 206 项宿主测试全部保留，另加 14 项动作几何。原 9 项 UI 源码未改，本块未运行，最终 I1 另执行全套。固定 SwiftFormat 0.59.1 检查本块 6 个 Swift 文件，0 个需改；冻结哈希、测试摘要和环境保存在同目录。独立规格及质量审查均已批准，C1 验收时源码哈希与冻结记录一致。C1 快照的普通 solid underline 走 CTLineDraw，源归属／原始批次为 C2 缓存；C2 将迁移为统一手绘下划线，尚未提供业务手势，不代表 I1 交付完成。

中间 `c1-red/`、`c1-host/` 为编译失败；`c1-host-final/`、`c1-host-green/` 为新夹具失败，保留诊断但不计为通过。

## C2 迁移前字形基线

在修改 renderer 前运行 `.build/verification/c2-pre-migration/Tests.xcresult`：1／1 通过、0 failed／skipped，根代理独立读取确认。真实 Baskerville fi 先证明 glyph 少于 2，五类夹具保存 glyph／run／原文映射／度量签名于同目录 `actual-signatures.json`，另以 test-only Swift 夹具持久保存，独立重跑不依赖忽略目录。这仅证明迁移前基线已采集；迁移后对比、按压像素及恢复仍待 C2 验收。

C2 行为红证据 `.build/verification/c2-red-behavior/Tests.xcresult`：3 项中基线 1 项通过，前景与背景 2 项像素测试失败，0 skipped。`testPressedForegroundAndRestorationUseSameLayout()` 未取得按压前景像素，`testPressedBackgroundReplacesHalfAlphaOnce()` 仍绘制旧背景通道；根代理独立读取确认，属于真实绘制缺口，非类型缺失或编译错误。

## 用户暂停与恢复入口

2026-10-20 用户要求先收尾暂停，回家再继续。唯一实施者已冻结源码，确认没有运行中的 xcodebuild，并释放 Simulator `5260ADE6-ADC2-44AA-9EEB-CDEC90196D08` 与 `.build/DemoDerivedData`。当前分支仍为 `codex/text-interactions`，未提交、未集成、未推送本阶段工作；既有 main／origin/main 交付基线仍为 `6dbeaeeade114c63dac8574e11b0860488882b15`。

暂停前最后一轮局部结果为 `.build/verification/c2-green-initial2/Tests.xcresult`：3／3 通过，0 failed／skipped／runtime warnings，根代理只读确认。包括五夹具迁移前后完整签名比较、fi 前景／恢复和半透明背景替换。这不是 C2 完整验收，不能代替全部宿主或 UI 回归。

恢复时先检查工作区和设备占用，保留已有未提交修改，从 C2 继续，不重复 C1 的已验收工作：

1. 修复新 `PressedTextDrawing` 背景按 style 分层可能破坏原同色合批、对重叠完整 cluster 重复合成 alpha 的问题。
2. 修复同色 stroke batch 内显式／继承色成员真实重叠时，整个 batch 的 clip 可能错误改变显式源颜色的问题；保持原成员顺序、路径与虚线相位。
3. 补齐 C2 的动态颜色、emoji 像素、源归属／实际重叠、半透明联合裁切、全部下划线及准备计数矩阵，再运行针对性和完整宿主检查、固定格式检查，冻结后依次规格及质量审查。
4. C2 批准后依次 C3（手势／宿主回调）、C4（真实 UI／截图）、C5（正式验收／提交／集成／普通推送），再按总计划 H1 → A1 → P1 连续推进。

C1 冻结记录是历史验收快照；当前 C2 已继续修改 Layout／TextDecorations，恢复时不能把工作区描述为仍与 C1 六文件哈希全部相同。C2 尚未完成最终 format／lint／source-freeze，不以局部三项通过宣称整体可交付。

2026-10-21 用户明确恢复后，已确认仅当前 checkout 使用 `codex/text-interactions`，HEAD、main、origin/main 跟踪记录均为 `6dbeaee`，保留全部未提交改动。总计划状态已同步恢复；C2 从既有局部实现继续。源码核查另发现普通背景为空时按压背景可能缺失，将与上述合成和源归属问题一起建立行为测试，不提前计为修复。

恢复后的行为红证据为 `.build/verification/c2-resume-red2/Tests.xcresult`：7 项中原 3 项通过，新 4 项失败，0 skipped／runtime warnings，根代理独立读取确认。新增测试分别捕获 nil 普通背景遗漏按压背景、跨样式完整 cluster 的半透明重复合成、同普通色 stroke 内显式／继承色双顺序归属、非整数 exclusion 横向边界错误。背景重复合成处实测通道值 31，单次 0.5 alpha 的期望约为 128。`c2-resume-red` 是 CTFont 转换编译失败诊断，不作为行为红测试。受控重叠 stroke 探针不代替真实合法文档重叠的后续验收。

首轮修复 `.build/verification/c2-resume-green/Tests.xcresult` 为 7／7，0 failed／skipped／runtime warnings，根代理独立读取确认。扩展矩阵随后发现 fi 的非整数边界抗锯齿缺口；最小探针 `.build/verification/c2-clip-probe2/tests.log` 对比单次填充参考：path 和 rect 两种互补裁切均有 80 个通道差异，边界像素从 `[255,127,127]` 变为 `[255,142,142]`；关闭抗锯齿变为双覆盖 `[255,63,63]`。局部透明层内 plusLighter 累加的矩形探针差异为 0。根代理独立读日志确认；该探针只证明合成根因，真实字形与装饰线仍须各自完成像素验收。

字形修正采用原 glyph 单次覆盖率绘制及 sourceIn 颜色场，未新建 CTLine，彩色 emoji 绕过该覆盖路径。`.build/verification/c2-glyph-mask-probe/Tests.xcresult` 为 1／1，通过同色及异 RGB 同 alpha 的严格像素探针。装饰边界红证据 `.build/verification/c2-decoration-alpha-red/Tests.xcresult` 为 1 失败；中间 `.build/verification/c2-decoration-alpha-green2/Tests.xcresult` 为 20 通过／1 失败，下划线最大 mask 差 22，不能计为绿。上述结果由根代理独立读取确认。

全批次“有重叠／无重叠”开关不足以处理同组同时存在真实重叠与远处相邻边界，因此改为准备阶段的局部源区域计划：仅查询动作覆盖区的相交成员、保留源顺序和原完整 stroke 路径／相位，区域内完成 source-over，区域间合成覆盖率。背景计划限定被接管的原批次范围，避免前后批次重复绘制。`.build/verification/c2-local-regions-green2/Tests.xcresult` 为 23／23、0 failed／skipped／runtime warnings，根代理独立读取确认；包含组合重叠和非整数边界验收。完整宿主回归、最终格式与冻结、规格及质量审查仍待完成，不据此宣称 C2 或 I1 已交付。

最终定向 `.build/verification/c2-local-regions-final/Tests.xcresult` 为 25／25，完整宿主 `.build/verification/c2-host-final/Tests.xcresult` 为 245／245（C1 的 220＋C2 的 25），均 0 failed／skipped／runtime warnings，根代理分别直接读取 xcresult 摘要确认。新增背景 consumed 范围像素和 40／160 个不相交动作的局部准备计数；非整数背景／下划线／删除线最大 mask 差均为 0。原 215 项交付基线测试方法无缺失，C1 14 项保留；UI 仍留待 I1 最终回归。

固定 SwiftFormat 0.59.1 显式格式化本块 9 个 Swift 文件中的 3 个后 lint 为 0／9；本次改写仅排版与等价简写，未重复完整宿主测试。格式前后源码哈希、环境、日志分别保存在 `c2-host-final/source-freeze-pre-format.json`、`source-freeze.json`、`environment.json`、`format-write.log` 和 `format.log`。根代理校验全部冻结哈希匹配，`git diff --check` 通过。源码已冻结，开始独立规格审查，批准后再作质量审查；尚未进入 C3 或提交 I1。

独立规格审查暂不批准 C2：未发现确定的实现缺陷，但现有证据缺少单个动作跨行的前景／背景／行间空白与恢复像素、图片和 UIView 两类附件的真实旧 renderer 迁移签名、生成 token ink 实际进入动作矩形时的普通色，以及相邻不同普通背景在 pressed background 为 nil 时各自保留。四项交还同一实施者补齐；245／245 保留为已有候选结果，不据此进入质量审查或 C3。

四项补测候选：`.build/verification/c2-review-gaps-green/Tests.xcresult` 为 29／29，完整宿主 `.build/verification/c2-review-gaps-host-final/Tests.xcresult` 为 249／249，均 0 failed／skipped／runtime warnings，根代理直接读取结果确认。跨行夹具逐行断言前景／背景、实际行间空白与整图恢复；token 夹具独立绘制 token-only run，证明超过 5 个纯色实墨像素进入另一行动作矩形，按下后仍逐点普通色。相邻蓝／品红普通背景在 pressed background=nil 时整图保持完全一致，普通色采样允许 8-bit 量化 1 级差异；此前 `c2-review-gaps-target` 的 128／127 期望差只作测试量化诊断，不计为产品行为红证据。

两类附件迁移使用真实 `6dbeaee` 的隔离 archive 与独立 DerivedData，在 `.build/verification/c2-attachment-original-complete/` 运行 1 项测试、4 类夹具（top／center／bottom／sourceOffset 截断），保存采集源码、实际签名和环境。当前 `AttachmentMigrationTests` 比较两类 placement、CTLine／CTRun 范围／状态／度量、glyph、字体、矩阵、源区间和 token 映射，均与真实旧结果一致。完整宿主后仅将夹具字体强制解包改为 XCTUnwrap，另运行 `c2-attachment-unwrap-green` 1／1；修改说明和前后哈希均保留。

补测未修改产品 Sources。固定格式检查 11 个 Swift 文件、0 个需改；最终 39 个源码／测试冻结哈希由根代理逐项核对无差异，`git diff --check` 通过，原 215 个测试方法全保留。四项已交回同一规格审查者复审，尚未获得 C2 最终批准；9 项既有 UI 仍在 C5 全回归范围内。

规格复审已批准 C2，确认四项缺口全部关闭，并核查旧采集 checkout 的 18 个 Sources 文件与真实 `6dbeaee` 一致：旧路径使用 CTLineDraw，未引入 fromContext。当前进入独立质量审查；质量批准前不进入 C3，I1 整体仍未交付。

质量审查暂不批准 C2，发现单个长动作的确定性二次方开销：`A ` 重复 N 次、全文单动作、byWord 下划线及不换行布局时，barrier 查询和每个 x slab 都重扫全部成员，绘制每个 region 又重复整组 N 个 interval。窄 Label 的理想尺寸查询也会建立 width=nil 布局，因此不能留到 P1 才处理。返回同一实施者修复，并补单个长动作 40→160 的 barrier 成员访问／活跃矩形判断／实际 stroke interval 绘制计数；已有 N 个短动作的准备计数不能代替。上述 249／249 仍是修复前候选证据，新的源码需重新冻结和串行复审。

长动作红证据 `.build/verification/c2-long-action-red/Tests.xcresult` 为 1 项失败、9 个断言失败：40→160 个 byWord interval 时，barrier 成员访问从 1,560 增至 25,440，活跃矩形检查从 3,200 增至 51,200，实际 stroke path 绘制从 1,640 增至 25,760。修复为空区间直接跳过 barrier，非空范围以二分定位选中成员；矩形以 x／y 边界事件维护活跃集合；相同有效颜色栈的互斥区域合入一个 CGPath，使原完整 stroke 路径每个颜色栈只绘制一次，未截短 interval 或重启 dash phase。

定向绿结果 `.build/verification/c2-long-action-green/Tests.xcresult` 为 30／30：相同 40→160 夹具的 barrier 访问为 0→0，活跃矩形事件为 200→800，stroke path 绘制为 80→320，均呈线性增长，并保留此前 29 项像素、源顺序、真实重叠、相位和附件迁移测试。首次完整宿主候选 `c2-long-action-host-final` 发现旧准备缓存测试把新增绘制期 stroke 计数误作准备期增长；实现没有重做准备，测试随后将绘制期计数与准备快照分开断言。

修正测试契约后的完整宿主 `.build/verification/c2-long-action-host-green/Tests.xcresult` 为 250／250，0 failed／skipped／runtime warnings，根代理直接读取结果确认。固定 SwiftFormat 0.59.1 全仓 53 个 Swift 文件为 0 个需改，`git diff --check` 通过。当前候选交回规格与质量复审；9 项既有 UI 仍留 C5 完整回归。

C2 最终规格与质量复审均批准，无剩余 P1／P2／P3。复审确认事件 sweep 对同 x／y 边界成组更新，颜色栈按 batch ordinal 保留源顺序，互斥区域可安全合并；完整原 stroke interval 和 phase 不变。单个长动作路径为准备 `O(n log n)`、绘制 `O(n)`。C2 完成后进入 C3 手势、取消、Label／SwiftUI 最新回调；I1 整体仍未提交或交付。

C5 首轮正式回归后的质量复查又发现普通绘制为每个字符建立 paint record 并重复调用 `CTRunDraw`。红证据 `.build/verification/c2-run-batching-red/Tests.xcresult` 为 2 项失败、15 个断言失败；5,000 字符夹具产生 5,000 个 paint record、5,000 次 glyph image bounds 查询及 5,000 次绘制。修复后按 CTRun 批量绘制，且只为动作相交 glyph 建立 paint record；定向 `.build/verification/c2-run-batching-green/Tests.xcresult` 为 32／32：无动作夹具 `records=0`、`bounds=0`、`draw=1`，单动作单 run 普通绘制 `records=1`、`bounds=1`、`draw=1`，按压绘制 `draw=3`，双 run 普通／按压分别 `draw=2`／`draw=4`。完整宿主 `.build/verification/c2-run-batching-host-final/Tests.xcresult` 为 276／276，0 failed／skipped／runtime warnings，保留 215 个 M1b 基线方法；固定 SwiftFormat 0.59.1 检查本次 3 个 Swift 文件为 0 个需改。修复后的 C5 完整正式回归见下节；旧 292／292 结果和旧源码冻结清单不再作为最终证据。

## C3 手势、取消与宿主回调

C3 新增局部 `ActionGestureRecognizer`、Label `onAction` 和 SwiftUI `displayHeight` 后的默认 nil `onAction`。tap、0.5 秒 longPress 和超过 10pt 的移动取消共用文档／几何 revision 与最终可见动作索引；清理状态、高亮、timer 和滚动观察后才调用当时最新回调，回调重入最多发送一次。interactive UIView 子树优先；普通文字及空白不被 Label 截获。

最终定向 `.build/verification/c3-reparent-green/Tests.xcresult` 为 22／22，完整宿主 `.build/verification/c3-reparent-host-final/Tests.xcresult` 为 272／272，均 0 failed／skipped／runtime warnings。覆盖 0.499／0.5 秒、up/timer 顺序、10pt 边界、离开再返回、相邻同 ID 不同输入 ordinal、第二触点、滚动接管、输入和层级变化取消、附件接收者重建、回调 A→B／nil→恢复、同步重入、weak timer／scroll target／宿主释放及 SwiftUI update／dismantle。最终规格与质量复审均批准。

## C4 真实 UI 与示例

UIKit 与 SwiftUI 使用同一动作样例，增加事件状态、callback A→B、native UIButton、截断／短高度裁切和真实手势入口；另增可选择 UITableView 夹具，区分普通区域父 cell 选择、动作区域及按钮优先级，并验证滚动和复用不串状态。Debug 诊断从真实缓存 layout、`ActionGeometry` 和 `DisplayGeometry` 取得目标点，未增加 public／SPI 几何接口。

完整宿主 `.build/verification/c4-host-final/Tests.xcresult` 为 274／274，0 failed／skipped／runtime warnings。真实 UI `.build/verification/c4-ui-matrix-final2/ActionDemoUITests.xcresult` 为 9／9，设备为 `5260ADE6-ADC2-44AA-9EEB-CDEC90196D08`；覆盖 UIKit／SwiftUI tap、0.65 秒 longPress、短按拖动滚动、回调替换、按钮优先、fi／emoji／RTL／token／短高裁切／inset、父列表选择及复用。

仓库保存并检查 8 张最终截图：`docs/verification/images/interactions-*.png`。xcresult 另导出 6 张非空截图及 manifest 至 `.build/verification/c4-ui-matrix-final2/attachments/`；UIKit 跨行真实按下录屏为 `.build/verification/c4-pressed-video/UIKit-cross-pressed-take3.mp4`。C4 最终规格与质量复审均批准。早期使用其他设备或失败探针的结果仅保留诊断，不计入上述最终结论。

## C5 正式验收与交付

C5 在上述绘制批处理修复后，使用唯一设备 `5260ADE6-ADC2-44AA-9EEB-CDEC90196D08` 串行重新完成正式检查：

- `scripts/verify.sh docs`：通过，19 个 Markdown、2 个 Shell 语法检查及文本规范／双 diff；日志 `.build/verification/c5-final/docs.log`。
- 固定 `LYGLYPHTEXT_SWIFTFORMAT=/Users/kahnli/Desktop/club-circle-workspace/club-circle-ios/.build/tools/swiftformat/0.59.1/build/out/Products/Release/swiftformat scripts/verify.sh format`：通过，62 个 Swift 文件、0 个需格式化；日志 `.build/verification/c5-final/format.log`。
- `scripts/verify.sh build`：Swift 6 language mode 的 Package 与 Demo Simulator 构建通过；证据 `.build/verification/20261020T204429Z-46212-build/`。
- `scripts/verify.sh test 5260ADE6-ADC2-44AA-9EEB-CDEC90196D08`：`.build/verification/20261020T204444Z-46368-test/Tests.xcresult` 为 276 项宿主＋18 项 UI = 294／294，0 failed／skipped／expected failures，`runtimeWarnings` 为空。18 项 UI 由 9 项动作矩阵和 9 项保留回归组成，零测试匹配未发生。

xcresult 的 destination 为 iPhone 17 Pro arm64、iOS 27.0（24A434）、`5260ADE6-ADC2-44AA-9EEB-CDEC90196D08`。本次测试日志保留 Xcode／SDK 的 `invalidDigitCount(94232)`、debugger version lookup、XCTest 17.0 链接及 AppIntents metadata 警告；首轮正式日志曾出现的 `Unbalanced calls to begin/end appearance transitions` 控制台文本未在本次日志复现。xcresult 没有将这些记录归类为 test failure、skip 或 runtime warning。提交、集成、普通推送及远端 SHA 核对仍未执行。

最终固定 SwiftFormat 检查和测试覆盖的 62 个 Swift 文件哈希保存在 `.build/verification/c5-final/source-freeze.sha256`，逐文件复核 62／62 匹配；清单 SHA-256 为 `54866c53520d40c0795b130836d66bd63b8e54d370fce98d7459c1e74edd9423`。最终文档更新后 `git diff --check` 通过；工作区仅保留本次 I1 的累计实现、测试、Demo、文档和 8 张截图，未提交证据目录保持 Git 忽略。

## 环境与未验证项

使用 Xcode 27.1（27A9275）、Apple Swift 6.4／Swift 6 language mode、XcodeGen 2.46.0，以及本任务独占的 iPhone 17 Pro arm64、iOS 27.0（24A434）Simulator `5260ADE6-ADC2-44AA-9EEB-CDEC90196D08`。Swift 6.0 编译器兼容、iOS 16 实际运行、真实设备及人工 VoiceOver 独立标记未验证；I1 不代替后续 A1 的无障碍验收。
