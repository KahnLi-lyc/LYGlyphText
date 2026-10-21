# H1 宿主矩阵验证记录

日期：2026-10-21。基线 `003558cd7c72116fcb889162ccf8ecd232e5ec70`，分支 `codex/host-matrix`。H1 功能验收完成：319／319（298 宿主＋21 UI），0 failed／skipped／expected failures，runtimeWarnings=[]；12 张最终截图已检查。H1a—H1c 已完成规格／质量审查，H1d 最终规格与质量证据复审已批准，已以 `32ac04a11ee39b2ba5c863b5abedfef0c247cd4e` 提交、锁内快进 main 并普通推送，远端 SHA 核对一致，临时分支已清理。本记录不代替 A1 环境／无障碍及 P1 性能验收。

## 行为与接口

H1 不新增公开 API，不改变 Core Text 排版、附件尺寸、文字动作契约或每 Label 最多两份布局缓存。新增 internal 测量诊断只统计实际 cache miss 构建、组件主动固有尺寸失效和当前缓存项数；重置计数不清缓存。SwiftUI 的 internal `measuredSize` 为现有 `UIViewRepresentable.sizeThatFits` 共用纯测量入口，不修改 frame／bounds／约束／文档／provider，不创建附件。

| 宿主 | 验证范围 |
|---|---|
| UIStackView | 横／纵各 20 种合法 alignment×distribution；并排按钮、两轴 CHCR 保留、稳定四轮布局收敛；首／末文字基线不在承诺内 |
| UITableView | automaticDimension、contentView 完整四边约束、明确离屏测量宽度、清理后重绑 |
| UICollectionView | full-width compositional estimated item、layout attributes 宽度 required fitting、像素向上取整；宽度变化由宿主通知 layout |
| SwiftUI | `.frame`／HStack／VStack／List／LazyVStack；稳定 row identity、最新 callback、provider 身份、清空／替换与 dismantle |
| 共用数据与宽度 | 40 个稳定 row；短／长文、20×20→48×64 图片、44×24→96×52 UIView、文字动作；0→320→600→240→320，往返高度一致 |
| 两端高度 | 同一文档、配置、有效宽度与实际 display scale；自然高度差不超过一个物理像素；固定 2x 宿主容差 0.5pt |

SwiftUI nil／正无限宽度使用理想尺寸；有限宽度钳制为非负并作为返回宽度。proposal.height 不限制自然高度，仅有限非负 `displayHeight` 覆盖；负宽／NaN／负无限等安全边界另有断言。纯测量工厂调用数为零。宿主提供宽度、完整约束与正常列表失效，组件不接管 delegate 或 layout；`layoutPriority` 不转换为 UIKit CHCR。

## 红绿与审查证据

以下路径均相对仓库根目录；`.build/verification/` 为本地忽略产物，不作为远端附件提交。测试均使用下节唯一 UDID，串行执行。

| 阶段 | 结果 | 本地证据 |
|---|---|---|
| H1a 行为红 | 6 项：4 通过、2 失败；横向 Stack 夹具约束与诊断计数暴露缺口 | `.build/verification/h1a-red/Tests.xcresult`、`test-summary.json` |
| H1a scale 夹具红 | 1 失败：实际 3x 不等于要求 2x；改为明确 2x trait 宿主，不放宽像素容差 | `.build/verification/h1a-review-red/Tests.xcresult` |
| H1a 定向绿 | 13／13：6 HostLayout＋7 保留 AutoLayout；0 failed／skipped，runtimeWarnings=[]；规格及质量批准 | `.build/verification/h1a-green/Tests.xcresult` |
| H1b 行为红 | 9 项：6 通过、3 失败；collection 宽度 240 时 63≠147pt、列表宿主尺寸策略及宽度变化断言 | `.build/verification/h1b-red/Tests.xcresult` |
| H1b 定向绿 | 55／55：6 HostList＋3 DemoHost＋24 ViewAttachment＋22 ActionInteraction；0 failed／skipped，runtimeWarnings=[]；规格及质量批准 | `.build/verification/h1b-green/Tests.xcresult`、`spec-review.txt`、`quality-review.txt` |
| H1c proposal 行为红 | 1 失败、5 个断言失败：理想／非有限 proposal 在旧路径得到零高度 | `.build/verification/h1c-behavior-red-final/Tests.xcresult`、`summary.json` |
| H1c 最终定向绿 | 10／10 宿主与 3／3 UI；0 failed／skipped，runtimeWarnings=[]；规格及质量批准 | `.build/verification/h1c-remediation-final/HostTests.xcresult`、`UITests.xcresult` |
| 正式回归后预期修正 | 11／11：HostList＋DemoHost；0 failed／skipped／expected failures，runtimeWarnings=[] | `.build/verification/h1-collection-expectation-green/Tests.xcresult`、`summary.json` |

类型缺失／编译失败结果只保留诊断，不计行为红。H1a 的夹具约束与 scale 修正也不描述为组件原有排版缺陷。H1b 最终使用 compositional layout，避免旧 FlowLayout attributes 宽度残留；宿主始终持有 dataSource／delegate／layout。

H1c 审查补齐真实 factory=0 的测量纯度、独立 UIKit 高度对照、row 0 确实滚出屏幕再返回、List／LazyVStack footer 对应同一行，以及 HStack／VStack 实际容器几何。真实动作先验证 `callback=B;handled=none`，操作后必须事件递增且 `handled=B`、actionID 对应当前行，不能只检查选择器文本。原生按钮有独立计数；其他复用行保持零事件／按钮／按压状态。

几何探针仅在 DEBUG 中作为透明不可见 accessibility probe，正常 Demo 不显示 CGRect 或内部缓存信息。H1c 冻结覆盖 9 个文件，含共用 `HostMatrixSamples.swift`；`source-freeze.sha256` 全部匹配，`source-mtimes.txt` 中修改时间均早于宿主／UI 测试开始。早期候选结果不代替本次最终冻结。

## 正式验收

| 命令 | 当前结果 | 证据 |
|---|---|---|
| `scripts/verify.sh docs` | 最终稿通过：21 个 Markdown、2 项 Shell 语法、文本规范与双 diff | `.build/verification/h1-final/docs-final.log` |
| 固定 SwiftFormat 0.59.1 的 `scripts/verify.sh format` | 通过：73 个 Swift 文件、0 个需改 | `.build/verification/h1-final/format.log` |
| `scripts/verify.sh build` 修正后重跑 | Package 与 Demo 的 Swift 6 language mode 构建通过 | `.build/verification/20261021T031606Z-13491-build/`；首轮构建保留在 `20261021T025700Z-9207-build/` |
| `scripts/verify.sh test 5260ADE6-ADC2-44AA-9EEB-CDEC90196D08` 首轮 | 298 宿主＋21 UI＝319 项：318 通过、1 失败（同一测试 3 个断言），0 skipped／expected failures，runtimeWarnings=[]；21 UI 全过 | `.build/verification/20261021T025752Z-9448-test/Tests.xcresult`、`tests.log` |
| 最终完整 test | 319／319（298 宿主＋21 UI）；0 failed／skipped／expected failures，runtimeWarnings=[]；73 个冻结文件哈希匹配且 mtime 早于测试 | `.build/verification/20261021T031641Z-13628-test/Tests.xcresult` |
| 最终规格 → 质量审查 | 最终规格及质量审查依次批准；完整结果、73 文件冻结、12 张截图与文档一致，无遗留阻塞问题 | `.build/verification/h1-final/reviews.txt` |

首轮完整 xcresult 已关闭并核对 summary；测试结束后自动 `simctl diagnose` 耗时，仅终止该诊断子进程，不中断已结束的测试，也不将失败结果计为通过。

首轮完整宿主回归的 `testCollectionSelfSizingUsesAttributesWidthAndMatchesOffscreenMeasurement` 在 240／320／600pt 下分别取得 164.333／122.333／101.333pt，预期为 147／105／84pt，均多 17.333pt。核对哈希确认测试与 H1b 绿时一致，但 Demo collection 控制器在 H1b 绿后已改变；当前状态行的固有高度 13.333pt 与 spacing 4pt 未纳入旧测试预期。此为 Demo 宿主变化后的独立预期缺口，不称为组件排版错误，也不推断不存在的旧源码快照。修复仅补全状态行非空／有限正高度断言与总高度独立计算，并按实际 scale 像素取整、容差一个物理像素；新冻结与最终正式回归均已通过。该结果保留为首轮正式失败证据。修正后 11 项目标测试已全绿，新 build 通过；73 个 Swift 文件（含 Package）已重新冻结于 `.build/verification/h1-final/final-source-freeze.json`，完整正式回归使用该候选且 73／73 匹配、修改时间早于测试开始；清单 SHA-256 为 `f302e17f2460a10ecfdcd33a2b65f77aa2d95338a40c052674487894e08808a9`，旧冻结不代替本次结果。

最终正式完整回归已通过，覆盖既有 I1 回归，不删减原有用例。298 项宿主比 I1 的 276 项增加 22 项，21 项 UI 保留既有 18 项并增加 3 项 H1 操作。交付提交 `32ac04a11ee39b2ba5c863b5abedfef0c247cd4e` 已锁内快进 main，普通 push 成功且远端 SHA 一致；已删除本任务临时分支。此次 push 有旧 credential helper 路径失效警告，但推送和远端核对均成功，未修改全局配置。

## 真实 UI 与截图

`HostMatrixUITests` 的 3 项测试实际操作两端宽度、容器、内容、原生按钮与 callback B；UITableView／UICollectionView／List／LazyVStack 分别滚出首行并返回，验证当前 row 和零状态隔离。Frame／HStack／VStack 检查实际 mode 与几何，不以共同 Label 存在代替容器验证。

从最终正式 xcresult 导出全部 PNG，完整附件映射见 `.build/verification/h1-final/attachments/manifest.json`，H1 的 12 张图保存于仓库，均为 1206×2622px。原附件名／测试名映射与哈希另保存在 `attachments/host-matrix-manifest.json`、`screenshots.json`；下表逐文件核对 SHA-256 一致。

逐张检查结果：两端 160pt 宽自然高度均为 59pt、320pt 宽均为 38pt；普通界面没有 CGRect 诊断文字，文字／按钮不重叠。Table／Collection 滚出后当前 row≥11、event／button／pressed 为 0，返回 row 0 后 event=1、callback=B、pressed=0。SwiftUI List 滚出到 row≥5、Lazy 到 row≥6，新行均清零；返回 row 0 后 event=1、handled=B，Lazy button=1；footer 自然高度 59／62pt 均非零且对应 row 0。另检查本轮两端 `images-320-bottom-unlimited`：上箭头橙色位于左上、右箭头橙色位于右上，方向一致；该检查不替代 A1 环境验收。

| 截图 | SHA-256 |
|---|---|
| [host-matrix-swiftui-lazy-return.png](images/host-matrix-swiftui-lazy-return.png) | `fdbf16ba3f3d2b1b8d88310cef571df46776418c29f75e99727f4631e28e78a6` |
| [host-matrix-swiftui-lazy-scrolled.png](images/host-matrix-swiftui-lazy-scrolled.png) | `33d976fb6d93625cf2633b255c2e5b3c3838425eee149f8aa870fbd7dabe4dc0` |
| [host-matrix-swiftui-list-return.png](images/host-matrix-swiftui-list-return.png) | `f4537ebdcb73c8a64741056fe8e5366606083048f8b348b7aa5a56f3b10d9f46` |
| [host-matrix-swiftui-list-scrolled.png](images/host-matrix-swiftui-list-scrolled.png) | `f2309d7b2bfc3abb98564bd58875154cb637020799ca73abffdda700a5e24076` |
| [host-matrix-swiftui-narrow-160.png](images/host-matrix-swiftui-narrow-160.png) | `5a143560ad64535f2fd4480e1dcbe524f08476ad57c75b00621762136fe9d8e8` |
| [host-matrix-swiftui-wide-320.png](images/host-matrix-swiftui-wide-320.png) | `b46e65af3f63c8f1f52b63aea7eb1127c5e60e51e0691d0ce00ae4df11e83e60` |
| [host-matrix-uikit-collection-return.png](images/host-matrix-uikit-collection-return.png) | `28037bf77612c1ffea0487f46fbecad8c73e62bc924a0527304da668d880d579` |
| [host-matrix-uikit-collection-scrolled.png](images/host-matrix-uikit-collection-scrolled.png) | `1bf8e7f36507e13b12053bbb4bbe78c26db980fcc143176b8acbd17bc873b6f8` |
| [host-matrix-uikit-narrow-160.png](images/host-matrix-uikit-narrow-160.png) | `cafabcb01506924ada231653090638fa7e8ae34f565d7df14b05bc9b5cd58c28` |
| [host-matrix-uikit-table-return.png](images/host-matrix-uikit-table-return.png) | `03d39f5f05cc3f7a61612ded9ecafe701a63c5f7958dd66dc1723e1a0eea69f4` |
| [host-matrix-uikit-table-scrolled.png](images/host-matrix-uikit-table-scrolled.png) | `387be327f5ea83097b4e68fe794a0e133fb3fcd084297f8d90efbe145498e662` |
| [host-matrix-uikit-wide-320.png](images/host-matrix-uikit-wide-320.png) | `b4f3c23d764022566bcae43a72a577c671923329aa72e3cbd58ca0cb0ec39792` |

## 环境与未验证项

| 项目 | 状态 |
|---|---|
| 当前工具链 | Xcode 27.1（27A9275）、Apple Swift 6.4、Swift 6 language mode、XcodeGen 2.46.0、SwiftFormat 0.59.1 |
| 实际运行 | iPhone 17 Pro arm64，iOS 27.0（24A434）Simulator；唯一 UDID `5260ADE6-ADC2-44AA-9EEB-CDEC90196D08` |
| Swift 6.0 编译器兼容 | 未验证；Swift 6 language mode 不代替旧编译器 |
| iOS 16 实际运行 | 未验证；部署目标不等于最低系统运行证据 |
| 真机／人工 VoiceOver | 未验证；H1 不验收 VoiceOver 元素或朗读 |
| Dynamic Type／深色模式／环境 RTL | 完整矩阵属于 A1；H1 混合方向文本不代替环境 RTL |
| 固定负载／滚动性能／内存／Instruments | 未验证，属于 P1；H1 收敛计数不代替性能测量 |

完成 H1 正式验收、审查和交付后按连续队列进入 A1；不创建 PR、Tag 或 Release。
