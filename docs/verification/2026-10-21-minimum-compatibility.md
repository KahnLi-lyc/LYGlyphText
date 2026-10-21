# R1 最低工具链与最低系统兼容性验证记录

日期：2026-10-21。基线 `1e787fbfb349f60b35a3d68e1f5c68041012b588`，分支 `codex/minimum-compatibility`。实施契约见[总计划 R1](../superpowers/plans/2026-10-20-lyglyphtext-implementation.md)。**独立检查完成；Swift 6.0 编译器与 iOS 16 运行均未验证，发布门槛保持未满足。** 本轮没有兼容性失败复现，不据静态猜测修改产品。

## 环境与占用核查

开始时 main 与本地 origin/main 同为上述基线、工作区干净，只有主 worktree，无本仓 xcodebuild／XCTest 进程或集成锁。其他 Swift 前端进程属于 Club Circle 的 SourceKit 索引，不终止或接管。原有 LYGlyphText Images Handoff 与其他任务的模拟器处于 Booted；本轮没有启动设备、安装或运行应用，也没有占用模拟器。

| 项目 | 本轮实际探测 |
|---|---|
| 宿主 | arm64，macOS 27.0.1（26A434） |
| 活动 Developer Directory | `/Applications/Xcode_27.1.app/Contents/Developer` |
| Xcode | 27.1（27A9275） |
| 实际 swiftc | `/Applications/Xcode_27.1.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc` |
| 编译器完整版本 | Apple Swift 6.4，swiftlang-6.4.0.34.1，clang-2100.3.34.1；swift-driver 1.168.6 |
| Simulator SDK | iPhoneSimulator27.1.sdk，27.1 |
| 另一套 Xcode | `/Applications/Xcode27.app` 的实际编译器同为上述 Swift 6.4 |
| 系统自定义工具链 | 2024-05-30 为 Swift 5.10-dev；swift-latest 指向它；2024-05-31 目录无 swiftc，不算可用编译器 |
| 用户工具链目录 | 未发现已安装工具链；未发现真实 Swift 6.0.x |
| 可用 iOS runtime 版本 | 18.0／18.1／18.2／18.5／27.0／27.1；没有 iOS 16，逐条 build 见数据文件 |
| 真机 | 两台均 offline／unavailable，记录系统为 26.6.2 和 27.0.1；没有可用 iOS 16 真机 |
| 固定工具 | XcodeGen 2.46.0、SwiftFormat 0.59.1 已存在；版本探测不当作本轮仓库 lint |

完整环境、runtime build、源码哈希、命令数组、退出码与消费者源码见[可复核摘要](data/minimum-compatibility-2026-10-21.json)。原始日志目录为 `.build/verification/r1-20261021-minimum-compatibility/`，其中 `commands.json`、`toolchains.json`、`runtimes.log`、`devices.log`、`device-connections.log`、`device-os-inventory.log` 保留探测原文。已知本仓历史测试设备 UDID 为 `5260ADE6-ADC2-44AA-9EEB-CDEC90196D08`、iOS 27.0（24A434）；它不是本轮 iOS 16 目的地。

## 独立消费者构建

在忽略目录内生成独立 `R1PublicConsumer` 应用，以本地 Package 依赖组件，只使用 `import LYGlyphText`，没有 `@testable`。样例同时包含 UIKit Label、SwiftUI View、segments 与 attributedText 初始化、UIImage／UIView 附件、MainActor provider／onUnmount 和动作回调。它没有测试 target，不把编译当作交互或生命周期运行结果。

事实源为原始目录下 `consumer/Consumer.swift` 与 `consumer/project.yml`；两者完整文本及 SHA-256 已嵌入可复核摘要，可在相同仓库相对位置还原，不依赖未提交文件才可审阅。生成的 xcodeproj、DerivedData 和应用不提交。

从仓库根目录执行的主要命令如下；每个命令的完整参数与退出码另见 JSON。`DEVELOPER_DIR` 仅设置于构建子进程，未运行全局 xcode-select 切换。

```sh
xcrun swiftc --version
xcrun --find swiftc
xcrun --sdk iphonesimulator --show-sdk-path
xcrun simctl list runtimes -j
xcrun simctl list devices -j
xcrun devicectl list devices
xcrun xctrace list devices
xcodegen generate --spec .build/verification/r1-20261021-minimum-compatibility/consumer/project.yml
DEVELOPER_DIR=/Applications/Xcode_27.1.app/Contents/Developer xcodebuild \
  -project .build/verification/r1-20261021-minimum-compatibility/consumer/R1PublicConsumer.xcodeproj \
  -scheme R1PublicConsumer -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/verification/r1-20261021-minimum-compatibility/ConsumerDerivedData \
  -resultBundlePath .build/verification/r1-20261021-minimum-compatibility/ConsumerBuild.xcresult \
  build SWIFT_VERSION=6 SWIFT_STRICT_CONCURRENCY=complete \
  IPHONEOS_DEPLOYMENT_TARGET=16.0 CODE_SIGNING_ALLOWED=NO
```

XcodeGen 与 build 均 exit 0，`BUILD SUCCEEDED`。实际 swiftc 日志中，LYGlyphText 与 R1PublicConsumer 各自包含 arm64／x86_64 两种 `apple-ios16.0-simulator` target、`-swift-version 6`，实际编译器仍是 Swift **6.4**。记录的是 SDK 27.1 下的编译链接成功，不是 Swift 6.0 工具链通过或 iOS 16 执行通过。构建有一条 AppIntents 元数据提取跳过警告（没有 AppIntents.framework 依赖），保留原文；不称控制台无警告。

原始证据：`consumer-generate.log`、`consumer-build.log`、`consumer-compiler-proof.json`、`ConsumerBuild.xcresult` 和独立 `ConsumerDerivedData/`。本轮没有消费者运行、UI 操作或新截图。

## 兼容性结论与所需环境

| 独立门槛 | 实际执行 | 结论 |
|---|---|---|
| Swift 6.0.x 编译 Package／Demo／直接消费者 | 0 次；已安装工具链不包含 Swift 6.0.x | **未验证**；Swift 6 language mode 不能替代 |
| iOS 16 宿主／UI 运行 | 0 宿主、0 UI；缺 runtime 与可用设备 | **未验证**；deployment target 16.0 不能替代 |
| 当前 Swift 6.4 公开接口消费者 | 1 次成功构建，未运行 | 仅本环境编译链接通过 |

静态检查保留 Swift tools 6.0、Swift 6 mode、iOS 16、单一 library／组件 target、纯 Swift、Apple 框架及零第三方运行依赖。检查了 if／switch 表达式、MainActor 默认参数与回调、SwiftUI sizeThatFits／单参数 onChange、traitCollectionDidChange，以及主 RunLoop Timer 内既有 MainActor.assumeIsolated。未修改隔离或并发检查；当前 SDK 编译与静态阅读仍无法排除 Swift 6.0 的 SDK 隔离差异或 iOS 16 行为差异。

补证需要以下具体环境，**本轮下载／安装为 0，未改全局开发环境**：

1. 真实 Swift 6.0.x、匹配的 iOS SDK 和完整 Xcode 构建工具，例如受支持宿主上的适当 Xcode 16.0；先以实际 swiftc 版本确认，不只看应用名称。使用进程级 Developer Directory 和独立缓存构建 Package、Demo、直接消费者。
2. 能运行目标 iOS 16 runtime 的受支持 macOS／Xcode／CoreSimulator 组合，或已连接、具备测试签名条件的 iOS 16 真机。不能假定当前 macOS 27 可直接运行旧工具或 runtime。优先最低版本；实际使用后续 16.x 时只登记该具体版本及 build，不外推全部早期版本。
3. 在该系统保留全部 368 项基线运行适用矩阵；任何不可执行项单列数量、原因与后续要求，不删除或悄悄 skip。先保存失败日志、源码哈希及截图，再做最小修复和相应回归。

未反复调用不存在的工具链／runtime，也未创建虚假失败测试。环境缺失是验收缺口，不是已复现的产品缺陷。

## 基线保留与验证边界

本轮未修改组件、Package、Demo、测试、project.yml 或工具脚本。`source-before.json`／`source-after.json`／`retention-check.json` 核对 **86 个 Swift 文件 before＝after＝P1**；全部 **368 个测试方法**与基线 Git 内容逐文件核对保留（344 宿主＋24 UI）。保持 Core Text 唯一内核、最低系统和并发要求，没有新增公开接口或运行依赖。

Package／Demo 的成功构建与完整回归引用 [P1 原始记录](2026-10-21-performance-readiness.md)及[正式数据](data/performance-regression-2026-10-21.json)：**历史 368／368 Passed，0 failed／skipped／expected failures，runtimeWarnings=[]**，控制台既有 61 条 appearance 警告另列。原始 Package／Demo build 日志仍在 `.build/verification/20261021T064244Z-59342-build/`，完整测试 xcresult 在 `.build/verification/20261021T064418Z-59586-test/Tests.xcresult`。这些不是本轮新增运行，本轮自动测试数为 **0**；不重复相同源码、相同环境的整套检查。

本轮重新核对 [P1 四张已归档截图](data/performance-screenshot-index-2026-10-21.json)的实际 SHA-256，与历史索引一致；摘要明确标记 capturedThisRun=false。原有正式 Debug 截图及全部 UI 附件仍保留于 `.build/verification/p1-final/`。没有把历史截图标为 iOS 16 图。

本轮 `scripts/verify.sh docs` 已 exit 0（28 Markdown、2 Shell 语法检查）；只读证据复核 `audit.py` 已 exit 0，独立核对源码、368方法、历史截图及编译日志。先规格审查批准，再由另一审查者完成独立质量审查并批准，均无必须修改项；两位审查者独立复核了原始构建证据、源码冻结、公开样例和历史结果边界，审批不代表两个最低兼容性门槛通过。审查摘要保存在原始目录的 `spec-review.txt`／`quality-review.txt`。最终候选检查以 `docs-final.log`、`audit-final.log` 和 `verified-candidate.json` 为准。提交、独占锁内快进 main、普通 push 一次、远端 SHA 核对及分支清理的实际结果保存于同目录 `delivery.json` 与 Git 历史，不提前声明远端交付成功。真机、人工 VoiceOver、任意原生后代 AX frame 部分裁切及 Allocations／Leaks 专用分析继续保持各自未验证，不由 R1 构建推导通过。不创建 PR、Tag 或 Release。
