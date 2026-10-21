# LYGlyphText 固定负载与发布准备实施计划

> **For agentic workers:** 使用 subagent-driven-development 串行实施，每块先规格审查再质量审查；保留全部既有回归。用户已授权连续执行、自动提交、锁内集成和普通推送。

**Goal:** 建立可重复固定负载、缓存与释放验证，实际记录 Release 测量和滚动／Instruments 证据，整理首版发布缺口，不创建版本或发布。

**Architecture:** 不新增框架公开 API。复用现有 Label 内部诊断和最终几何；负载／计时／列表仅属于 Demo 和测试。所有测量及 UIKit 操作 MainActor，Core Text 仍是唯一内核。

**Tech Stack:** iOS 16+、Swift 6 mode、UIKit／Core Text、XCTest／XCUITest、Xcode Instruments CLI、固定 SwiftFormat 0.59.1。

## 起点与固定环境

A1 已以 `b615c3e036a9816fda9191f52c46915482bd5d1b` 提交、独占锁内快进 main，普通推送成功并核远端 SHA 一致；临时分支已安全删除。A1 正式359／359（336宿主＋23UI）、81 Swift 冻结与8张截图、最终规格／质量审查均通过。推送有旧 credential helper 路径失效警告，但结果成功；未改全局配置。

P1 分支 `codex/performance-readiness`，同一 checkout；唯一设备 `5260ADE6-ADC2-44AA-9EEB-CDEC90196D08` iPhone17Pro／iOS27 Simulator。Xcode27.1／Swift6.4，工具和系统版本分别留证。xcodebuild、真实 UI 与 Instruments 串行，不接管其他任务设备。Swift6.0编译器、iOS16、真机和人工 VoiceOver 仍未验证，不能由本轮推导发布通过。

## 固定负载和计时契约

- 9组：100／1000／5000 UTF-16 单元×0／3／10附件；U+FFFC计入长度。24×24pt附件、20pt显式字体、320pt宽、scale取真实宿主。0为纯文字，3为2图片＋1UIView，10为5图片＋5UIView；输入含中文、emoji和基本RTL。附件置于前缀可见区；完整Character拼接后ASCII补足精确长度，不切grapheme。
- 描述保存输入文本／附件和metadata，可重复构造新Document。图片本地生成，无网络；ID唯一、位置从累计UTF16取得。动作与按钮出现在3行截断可见区。
- Release每组文档构造30次，首次测量30次（每次新Label，document构造和赋值在计时外），热缓存预热5次＋正式200次，缓存位图绘制30次。Debug只做少量sanity，不报告为Release性能。
- 单调时钟DispatchTime.uptimeNanoseconds；断言、日志、JSON编码、上下文分配及autoreleasepool排空在计时外。输出每次原始ns、计数、字体／宽／scale／配置；p50／p95为nearest-rank `sorted[ceil(p*n)-1]`，根独立重算。
- “冷”仅指新Label首次测量，不代表进程／字体缓存冷启动。绘制阶段上下文预分配、布局已缓存，名称labelDrawCachedBitmap，明确`includesViewSubtree=false`；UIView成本通过真实window滚动另记。
- 不设未经测量的FPS或内存门槛。RSS／footprint只能描述进程观测，不代替weak释放及Instruments，不声称模拟器即真机性能。

## P1a：输入、缓存与释放行为

创建 `Examples/LYGlyphTextDemo/LYGlyphTextDemo/PerformanceSamples.swift` 和 `LYGlyphTextDemoTests/PerformanceBehaviorTests.swift`；不修改组件实现与project.yml。

- [x] 先写样本长度、位置、类型数、ID、尺寸／字体、重构Document快照测试；确认实际缺口，编译失败不算行为红。实现9组固定样本并保留metadata。
- [x] 新离屏Label逐组测sizeThatFits、intrinsic、required-width fitting，精确断言factory=0；测量不修改frame、约束、优先级或创建子视图。
- [x] 独立缓存夹具只用sizeThatFits，宽序列240,320,240,480,320,240,480；build序列1,2,2,3,3,4,4、cache数量1,2,2,2,2,2,2。同Document不失效，不同Document立即清缓存，下一查询只增一次build；不将当前行为描述为LRU。
- [x] 每个含UIView负载100轮真实window挂载、稳定重复布局、清空／reload／移出重挂；成功挂载与onUnmount精确配对、回调时superview=nil、autoreleasepool后weak=nil。按实际可见placement计算预期；双宿主共享document/provider也实例独立，清空一端不影响另一端。
- [x] 指定设备定向回归、format与源码冻结，先规格后质量审查；修复返回同一实施者。

## P1b：Release计时与真实列表

创建 `LYGlyphTextDemoTests/PerformanceMeasurementTests.swift`、`LYGlyphTextDemo/PerformanceListController.swift` 和 `LYGlyphTextDemoUITests/PerformanceUITests.swift`；修改DemoAppDelegate／DemoSceneDelegate仅接入口及本地分析启动参数。

- [x] 分阶段记录原始数据，测试附件keepAlways保存JSON；Release命令显式`-configuration Release ENABLE_TESTABILITY=YES SWIFT_VERSION=6 CODE_SIGNING_ALLOWED=NO`，独立DerivedData与xcresult，核实际编译优化标记。断言首次build=1、热阶段不增build、factory=0。
- [x] 180行=9组×20，320pt、3行省略，使用原生自适应UITableView。prepareForReuse和didEndDisplaying幂等清理；willDisplay重绑定；退出停止自动滚动。provider计数使用weak视图记录，不保活附件；状态含factory／unmount／live／动作／按钮。
- [x] UI使用真实AX元素操作文字动作和原生按钮，滚动离开／返回验证状态，保存检查截图；Release不能依赖DEBUG透明probe。自动往返独立用于Instruments，实际手势仍由UI测试验证。
- [x] Instruments串行尝试Allocations／Leaks及Time Profiler或Animation Hitches，保存命令、退出码、trace、导出TOC／表和持续时间。记录滚动轮数、offset、挂载／释放、进程内存采样来源；工具或权限失败留证且标未验证，不以模板存在当成功。
- [x] 根已独立重算原始数据分位数并保存匿名JSON到`docs/verification/data/`，更新专项记录。先规格审查再质量审查。

定向命令（每轮新结果目录，禁止复用覆盖）：

```sh
xcodegen generate --spec Examples/LYGlyphTextDemo/project.yml
xcodebuild test -project Examples/LYGlyphTextDemo/LYGlyphTextDemo.xcodeproj -scheme LYGlyphTextDemo -destination 'platform=iOS Simulator,id=5260ADE6-ADC2-44AA-9EEB-CDEC90196D08' -parallel-testing-enabled NO -only-testing:LYGlyphTextDemoTests/PerformanceBehaviorTests -derivedDataPath .build/DemoDerivedData -resultBundlePath .build/verification/p1a-green/Tests.xcresult SWIFT_VERSION=6 CODE_SIGNING_ALLOWED=NO
xcodebuild test -project Examples/LYGlyphTextDemo/LYGlyphTextDemo.xcodeproj -scheme LYGlyphTextDemo -configuration Release -destination 'platform=iOS Simulator,id=5260ADE6-ADC2-44AA-9EEB-CDEC90196D08' -parallel-testing-enabled NO -only-testing:LYGlyphTextDemoTests/PerformanceMeasurementTests -only-testing:LYGlyphTextDemoUITests/PerformanceUITests -derivedDataPath .build/PerformanceDerivedData -resultBundlePath .build/verification/p1b-release/Tests.xcresult ENABLE_TESTABILITY=YES SWIFT_VERSION=6 CODE_SIGNING_ALLOWED=NO
```

## P1c：发布准备与最终交付

- [x] 复核Package纯Swift／零第三方运行依赖、来源／MIT／无移植记录、公开API与README安装方式；新增`docs/RELEASE_READINESS.md`和`CHANGELOG.md`未发布草案，不捏造版本号或发布资格。
- [x] 正式docs、固定format、build、完整host＋UI：368／368（344宿主＋24UI）、86个Swift前后冻结一致，保留A1全部359方法；导出检查截图，61条既有appearance警告单列，不把Debug性能填入Release表。
- [x] 更新README、总计划、连续计划和`docs/verification/2026-10-21-performance-readiness.md`，区分自动完成、Instruments观测、人工／最低环境缺口；仅有证据的任务勾选。
- [x] 最终规格审查后独立质量审查均批准，无必须修复项；两位审查者分别核对368测试树、359基线保留、86源码冻结、Release原始数据、截图及环境边界。

交付按CONTRIBUTING执行中文Conventional Commit、独占集成锁候选核验、快进main、普通push一次并核远端SHA，再安全删除本任务临时分支。实际提交及远端结果以Git历史和本机`.build/verification/p1-final/delivery.json`为准，不pull／rebase／强推、不创建PR／Tag／Release。

- [x] 连续队列独立可做工作完成，已保留发布阻塞清单。人工VoiceOver、旧工具链、最低系统和真机需相应环境或人工证据，未验证项不标完成，不再擅自扩充首版范围。
