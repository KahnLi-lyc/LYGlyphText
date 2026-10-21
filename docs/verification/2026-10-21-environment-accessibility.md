# A1 显示环境与无障碍验证记录

日期：2026-10-21。基线 `32ac04a11ee39b2ba5c863b5abedfef0c247cd4e`，分支 `codex/environment-accessibility`。A1a 环境定向测试及最终规格／质量复审已批准；A1b 已完成实现、81 项定向回归及规格／质量审查；A1c 最终定向 5／5 及规格／质量双审通过；A1d 正式完整回归 359／359 已通过，最终规格／质量审查均批准，已以 `b615c3e036a9816fda9191f52c46915482bd5d1b` 完成提交、锁内快进 main、普通推送并核远端 SHA 一致。实施契约见 [A1 计划](../superpowers/plans/2026-10-21-environment-accessibility.md)。

## 环境

Xcode 27.1／Apple Swift 6.4／Swift 6 language mode，iPhone 17 Pro iOS 27 Simulator，UDID `5260ADE6-ADC2-44AA-9EEB-CDEC90196D08`；XcodeGen 2.46.0、SwiftFormat 0.59.1。仅使用该设备串行运行，不以新工具链成功推导最低环境通过。

## A1a：显示环境

仅新增 `EnvironmentTests.swift`，未修改组件 Sources 或公开 API。默认 body 在 large／extraExtraExtraLarge／accessibilityExtraExtraExtraLarge 间随环境重排并可往返；显式 UIFont、preferredFont 与 UIFontMetrics 已产生的快照保持固定。图片／UIView 三种对齐跟随当前字体但声明尺寸不变；语义前景、背景、下划线、删除线、按下前景及背景色有浅深像素断言。RTL 宿主覆盖逻辑 grapheme 映射、显式段落方向及图片方向；不额外镜像图片。

真实 SwiftUI 宿主的三字号×明暗×LTR／RTL 共 12 组环境继承通过，同一输入 180pt 宽下两端自然高度分别为 98／159／760pt，实际 scale=3，高度一致。三字号×明暗的测量入口包含 intrinsic、sizeThatFits、两种 fitting 和 SwiftUI proposal；工厂调用为零，frame、全部原有约束及其对象身份／属性／优先级／激活状态保持不变。

| 运行 | 真实结果 | 本地忽略证据 |
|---|---|---|
| 草稿编译 | 测试代码编译错误，不算行为红 | `.build/verification/a1a-red/` 编译日志 |
| 首轮环境运行 | 7 项，1 测试失败、4 断言；测量夹具未完成 trait 传播，未改产品源码 | `a1a-red/Environment.xcresult`、旧测试快照 |
| 第二轮定向 | 91 项，1 测试失败、4 断言；同一夹具缺少布局传播周期，其余 84 项通过 | `a1a-red/SecondRuntime.xcresult`、`second-runtime.log` |
| 夹具修正后 | 91／91：7 新环境＋84 既有附件／按压绘制／SwiftUI 回归；0 failed／skipped／expected failures，runtimeWarnings=[] | `.build/verification/a1a-green/Tests.xcresult`、`summary.json` |
| 规格补测 | 7／7：补完整约束快照及无优先级 fitting，零失败／跳过／预期失败，runtimeWarnings=[] | `.build/verification/a1a-review-green/Tests.xcresult`、`summary.json` |
| 质量补测 | 7／7：固定 50ms 等待改为有超时的状态条件等待，零失败／跳过／预期失败，runtimeWarnings=[] | `.build/verification/a1a-quality-green/Tests.xcresult`、`summary.json` |

规格审查补齐每环境完整约束快照与无优先级 fitting；质量审查将 SwiftUI 固定 50ms 等待改为目标 trait／方向／180pt 宽／预期高度就绪条件，未就绪才推进 RunLoop，2 秒单调时钟超时输出真实状态。修复后先规格再质量复审均批准，无遗留阻塞。

上述红结果均为测试夹具或草稿问题，不描述为组件环境缺陷。先让空宿主完成真实 trait 布局传播，再绑定文档／provider，只执行测量，避免将宿主准备与测量副作用混淆。第二轮测试已结束后自动诊断收集拖延，仅对其 `simctl diagnose` 子进程发送 SIGINT；xcodebuild 保持运行至正常返回失败，失败结果完整保留，不将诊断中止写成测试通过。

最终定向前后 Sources／Tests／Examples 共 73 个 Swift 哈希一致；Package.swift 另核与基线一致（合计 74 个 Swift）。当前环境测试 SHA-256 为 `a0b45875de42a1f02f57e6b2df71659c7bddde7fc91fd1d9027a2e7adc20e3e5`。固定 formatter lint 和 diff 检查通过。最终冻结清单及工具环境保存在 `.build/verification/a1a-quality-green/`；该定向证据不代替 A1d 完整回归。

## A1b：最终可见语义与自动激活

新增内部 TextAccessibility 和 Label 容器快照，不增加公开 API。展示布局与附件 reconciliation 稳定后发布；查询只读、不排版、不创建附件。按最终可见 grapheme 的 UTF-16 逻辑顺序构造语义，排除隐藏源与生成 token；只对全换行 gap 规范空格，不补读隐藏正文。图片／非交互附件使用非空替代文本，交互原生附件独立成子树；不覆盖宿主或工厂原生 AX 属性。

元素弱持有宿主并校验 revision，清空、几何／环境变化、provider、reload、window 移除及 dismantle 均使旧元素失效。卸载业务回调前释放语义快照；自动激活先清按压，再读取最新 callback，同步重入最多发送一次。frame／path 查询实时转换到屏幕坐标，祖先滚动不需要重排。

| 运行 | 真实结果 | 本地忽略证据 |
|---|---|---|
| 初始行为红 | 19 测试、36 失败断言，其中 2 unexpected；缺少自动 AX 入口 | `.build/verification/a1b-red/` |
| 快照释放反证红 | 临时禁用快照清理后 1 测试、5 断言失败；排空 autorelease pool 且宿主仍存活 | `a1b-self-review-red2/` |
| 清按压取消反证红 | 取消回调隐藏宿主后 1 测试、2 断言失败；实现增加发送前可见性复核 | `a1b-cancellation-red/` |
| 最终定向绿 | 81／81：28 AX＋22 ActionInteraction＋7 Environment＋24 ViewAttachment；0 failed／skipped／expectedFailures，runtimeWarnings=[] | `a1b-green-complete/Tests.xcresult`、`handoff.txt` |

固定 SwiftFormat 0.59.1 lint 76 文件零问题；Package＋Sources＋Tests 的 49 文件冻结前后及当前哈希一致。根代理独立读取结果包并校验冻结；规格审查后质量审查均批准，无遗留阻塞问题。该定向结果不代替 A1d 全回归。

无 scene 测试窗口中，通用 AX／screen.coordinateSpace 转换不随祖先滚动；最终采用 UIWindow 专用 `convert(to: nil as UIWindow?)`，40pt 祖先滚动后 frame／path 同步变化且 layout 计数不增。末轮失败有两处测试 oracle 遗留旧转换，修正 oracle 后上述 81 项通过，不描述成额外产品缺陷。部分失败运行在测试结束后自动收集诊断拖延，仅 SIGINT 诊断子进程，xcodebuild 自身正常返回失败，未冒领成功。

原生附件部分裁切保留声明 frame 和单个有序原生子树；无 scene 的 UIButton AX frame 为零，任意原生后代 AX frame 部分裁切及人工 VoiceOver 尚未验证。A1c 继续真实 scene 的 UI 查询与截图。

## A1c：真实宿主环境与 UI

两端共用默认 body 文档、语义颜色、中文／emoji／阿拉伯文、非对称本地方向图和原生按钮，提供三字号、明暗、LTR／RTL、160／320pt、1／不限行和 callback A／B。新增宿主矩阵按 48 个组合比较真实 trait 和一个物理像素内高度；UI 测试直接查询自动动作元素和原生按钮，并操作控件。最终定向及规格／质量审查通过。

首次构建因新增测试闭包缺少显式 self 失败，0 测试，不算行为红。第二轮执行 4 项：样本宿主测试与两端 UI 共 3 项通过，环境矩阵 1 项失败；测试先取到 SwiftUI 拆卸中的旧 Label，过滤为当前文档／window／配置后仍失败。后续只读诊断确认父导航有尺寸但 hosting.view.bounds 为零：测试替换 rootView 后只布局 child，未请求父导航重新布局，新语义树尚未创建。父导航补布局后 hosting bounds 恢复，但强制 `.id` 更换整个示例 root 的测试路径仍只留下已清空旧实例；该路径未宣称修复或验收。矩阵改为每组独立真实导航宿主，保留原 48 组合、trait、文档身份及高度精度断言；同一宿主的真实控件更新继续由两端 UI 和既有环境回归覆盖。不以这个夹具现象推断组件拆卸缺陷。

第二轮 UI 的 8 张截图揭示断言缺口：最大字号下只检查聚合文本元素 isHittable 不能证明尾标记露出；SwiftUI 页选中 Dark 后仍浅色；UIKit 深色页导航标题不可见。根代理与实施者独立查看截图确认。导航内单项真实红进一步确认 selection=Dark，但 nav／host／当前 Label 均 light，UIColor.label 仍为黑色；`.preferredColorScheme` 单独在该 UIKit 导航嵌入层未传达期望。证据在 `.build/verification/a1c-navigation-red/`，1 项 1 失败。单变量追加 SwiftUI 子树 `.environment(\.colorScheme, ...)` 后，`a1c-navigation-environment` 1／1 通过，当前 Label 实际为 dark 且语义前景为白色；nav／host 仍由 UIKit 管理。保留 `.preferredColorScheme` 呈现偏好，不修改组件 trait 或绘制路径。该快速夹具退出有 appearance 警告，最终还需等待真实 appearance 完成后重验，不能以此单项代替完整无警告验收。

诊断运行 `a1c-root-diagnostic` 为 1 项 1 失败，保留所有候选树与父子 bounds 输出；另有导航传播红结果。测试均结束后，只对对应 `simctl diagnose --timeout=600` 子进程发送 SIGINT（37655、39498、40026），xcodebuild 自身未被中止，正常保留失败结果包。

最终 `.build/verification/a1c-review/Tests.xcresult`：**5／5 Passed＝3 宿主＋2 UI**，0 failed／skipped／expectedFailures，runtimeWarnings=[]。真实导航中每配置独立宿主的 48 组合全部高度差为 **0pt**，scale=3；AX5 不限行在 160／320pt 宽下为 1904／770pt，单行为 79pt。两端 UI 实际操作全部控件，直接点击自动动作与原生按钮，验证最新 B 回调、按钮优先及截断隐藏／恢复；AX5 尾标记的底部必须真正进入滚动可见区。

81 个 Swift 文件冻结前后及根复核当前哈希完全一致；固定 formatter lint 81 文件通过。`attachments/screenshots.json` 记录 8 张 keepAlways 截图及 SHA-256，根独立核对并逐张查看：两端浅色默认、深色 XXXL、RTL 与 AX5 滚动至尾部，文字可读、图片向右且白点在左上，尾标记完整露出。正式 A1d 完整回归后重新导出截图到跟踪目录。A1c 先规格、后独立质量审查均批准，无待修问题；不将本定向结果替代完整回归。

## A1d：完整回归与既有诊断夹具适配

首次正式 docs（23 Markdown／2 Shell）、固定 format（81 Swift）及 Package／Demo Swift 6 模式 build 均通过。证据在 `.build/verification/a1-final/`，实际 build 目录 `20261021T045431Z-41965-build/`。测试目录 `20261021T045441Z-42067-test/`：**351／359：336 宿主全过，23 UI 中 15 过、8 失败**，0 skipped／expectedFailures，runtimeWarnings=[]。UI 阶段暴露既有 UIKit DEBUG 诊断 overlay 被自动 AX 容器排除的回归，不能当作通过。81 个 Swift 冻结前后匹配，完整失败结果与日志保留。

根因是 ActionSelectionCell、UIKitActionDemoController 及 HostMatrix Table／Collection 将诊断 overlay 嵌为 Label 子视图，而自动 `accessibilityElements` 有意只列最终文字语义／原生附件。旧 UI 通过 overlay 标识和真实屏幕坐标操作手势；SwiftUI probe 已为外置结构。修复将四处 UIKit overlay 移为 Label 的同级普通视图，仍对齐其四边且不响应触摸，不改变组件 AX 契约、诊断点、测试数量或真实手势 oracle。保留首次失败结果。修复后定向 `a1d-overlay-green` **3／3 UI Passed**（选择区分、真实 tap／longPress／drag／按钮优先、Table／Collection 宽度／滚动／返回／复用），0 failed／skipped／expectedFailures，runtimeWarnings=[]；81 文件冻结前后及根复核当前一致，相对失败轮仅四个授权 Demo 文件各改一行，固定格式检查通过。完整回归在 `.build/verification/a1-accepted/` 重新执行。

本轮所有测试结束后，诊断收集拖延；根核对 `simctl diagnose` 43936 是本次 xcodebuild 42084 的直接子进程、同一 UDID 和结果目录后仅 SIGINT 该诊断，xcodebuild 自身正常失败退出，未中断测试。

控制台 appearance 警告与 xcresult runtimeWarnings 分开记录：H1 最终日志已有 17 条 `Unbalanced calls`，本轮宿主结束观察到 61 条；部分旧窗口夹具在 RunLoop 推进后延迟输出，A1a 测试也存在未等真实 appearance 完成便关闭的夹具。A1c 独立最终运行未见该日志。未把该现象宣称为生产组件缺陷或已修复。

## A1d 最终完整结果与截图

正式命令 `scripts/verify.sh docs`、`format`、`build`、`test 5260ADE6-ADC2-44AA-9EEB-CDEC90196D08` 全部正常返回成功；摘要在 `.build/verification/a1-accepted/`。实际构建证据 `20261021T051539Z-44927-build/`，测试证据 `20261021T051545Z-44984-test/Tests.xcresult` 与 `test-summary.json`。**359／359 Passed＝336 宿主＋23 UI**，保留 H1 的 319 项并新增 40 项；0 failed／skipped／expectedFailures，runtimeWarnings=[]。本轮完整运行控制台仍有 61 条上述 appearance 夹具警告，与结果包运行警告分别记录，不宣称完全无控制台警告。

测试前后 81 个 Swift 文件逐一 SHA-256 一致，无新增遗漏；冻结清单 `.build/verification/a1-accepted/source-freeze.json` 的 SHA-256 为 `3af0c4ebff4ed2c694f2cf1e96144b8877e88b49031987c087866a6ffc62bd2b`。固定格式检查 0／81 文件待格式化。最终文档变化后仅重验 docs，不重复同源完整运行。

正式完整结果重新导出并逐张检查以下 8 张截图，原附件 manifest 和 SHA-256 对照在 `.build/verification/a1-accepted/attachments/screenshots.json`：浅深文字可读，非对称图片始终向右且白点位于左上；大字号与按钮对齐，AX5 尾标记完整进入可见区；RTL 切换保留逻辑文本及图片方向。Table／Collection 既有滚动返回截图保留在同一结果导出目录，原 H1 跟踪截图不覆盖。

| 环境 | UIKit | SwiftUI |
|---|---|---|
| 默认浅色 | [截图](images/environment-UIKit-light-default.png) | [截图](images/environment-SwiftUI-light-default.png) |
| XXXL 深色 | [截图](images/environment-UIKit-dark-xxxl.png) | [截图](images/environment-SwiftUI-dark-xxxl.png) |
| AX5 滚动至尾部 | [截图](images/environment-UIKit-ax5-scrolled.png) | [截图](images/environment-SwiftUI-ax5-scrolled.png) |
| RTL | [截图](images/environment-UIKit-rtl.png) | [截图](images/environment-SwiftUI-rtl.png) |

最终跨块规格审查批准，随后独立质量审查批准，无遗留阻断。两位审查者分别核对当前源码、冻结、正式测试和证据边界；根逐张复核截图。交付提交 `b615c3e036a9816fda9191f52c46915482bd5d1b` 已在独占集成锁内核当前基线、clean、81 文件冻结与正式成功摘要，快进 main 后普通 push 成功，ls-remote 确认远端相同 SHA；临时分支已安全删除。推送有旧 credential helper 路径失效警告，未修改全局配置。

## 未验证项

- Swift 6.0 编译器兼容、iOS 16 实际运行、真机均未验证。
- 人工 VoiceOver 朗读顺序、重复朗读、停顿与焦点体验未验证；自动 AX 查询／激活不能替代人工验收。
- 任意原生 UIView 后代 AX frame 的部分裁切不因父视图 clipsToBounds 自动得到保证；单列测试及限制，不承诺尚未实测的行为。
