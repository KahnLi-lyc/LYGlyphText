# 真机功能验证记录（网络图片列表、内存与泄漏、附件释放、触摸）

日期：2026-11-02。设备 iPhone 12 Pro Max（iPhone13,4，A14，60Hz，逻辑宽度 428pt），iOS 27.0.1；Xcode 27.2（27B52），Swift 6.4.2。性能与内存录制用 Release（`SWIFT_VERSION=6`），UI 测试用 `xcodebuild test` 默认的 Debug；个人开发证书签名只在命令行传入，不写入仓库。基线为 main `6d9fe98` 加本批次的 Demo 改动。录制期间手机保持解锁、亮屏；只从 Demo App 自己沙盒的 Documents 取回 `feed-profile.json`、`performance-scroll.json`，没有读取手机上的其他数据。

## 本批次改动（只涉及 Demo）

- `FeedPerformanceController` 新增 `-feedRemoteImages YES`：偶数行 2 张、奇数行 1 张 `LYGlyphTextRemoteImageAttachment`（48×24pt，scaleAspectFit，占位图 `photo`），共 270 个地址，均为 `https://raw.githubusercontent.com/onevcat/Kingfisher/master/images/logo.png?feed=<行>-<序号>`。`-feedImageLoader kingfisher` 改用 Demo 的 `KingfisherImageLoader`，默认用内置 `LYGlyphTextURLSessionImageLoader`。启动时清空所用加载器的内存与磁盘缓存，每次录制都是冷缓存。解析器的输出不能再插入远程图片，所以这个模式在 Demo 内按解析器的规则把表情、@、#、链接拆成图片和动作片段，再用 `LYGlyphTextDocument(segments:)` 构造；文字、截断配置和后台预排版与原模式相同。
- `--feed-profile` 在自动滚动期间每秒记录一次进程 RSS（`mach_task_basic_info.resident_size`，与 `PerformanceListController` 同一来源），结束后连同图片加载回调次数写入沙盒 Documents 的 `feed-profile.json`。
- `ActionDemoDiagnostics` 的 `lineEnd` 诊断点修正，见“触摸”一节。

## 1. 带网络图片的业务列表

`--feed-profile -feedRemoteImages YES`，2800pt/s 自动往返滚动 45 秒；Animation Hitches 每组 55 秒，卡顿时间比取录制时间轴 8—48 秒窗口，进程过滤 `LYGlyphTextDemo`（导出 XML 中 id／ref 已解引用）。两组的 `feed-profile.json` 都记录了 1328 次图片加载回调（270 个附件随滚动反复挂载），说明图片确实经网络加载并显示。

| 加载器 | 窗口内卡顿 | 卡顿时间比 | RSS 起点／峰值／终点（MiB） | 8—44 秒 RSS 范围 |
|---|---|---:|---|---|
| 内置 `LYGlyphTextURLSessionImageLoader` | 0 次（窗口外 6.1 秒有 1 次 16.7ms，标注“1 offscreen pass”） | **0ms/s** | 112.5／140.5／139.7 | 139.7—140.5 |
| Kingfisher 8.14.0 桥接 | 1 次，16.7ms | **0.42ms/s** | 114.0／143.4／143.0 | 143.0—143.4 |

加 RSS 采样之前的同场景构建也各录过一次：内置加载器 2 次、0.83ms/s（最长 16.7ms），Kingfisher 0 次、0ms/s。两次结果都低于 C6 的 5ms/s 门槛，与不带图片时的 0.8ms/s 处于同一水平。

Allocations（内置加载器，60 秒）：All Heap & Anonymous VM 曲线在滚动开始后约 5 秒内升到平台，之后到录制结束保持水平；结束时常驻 70.19 MiB（330,350 个对象），期间累计分配 4.44 GiB（7,189,375 次），绝大部分是滚动中的临时分配。Allocations 下 App 自测 RSS 147.1／175.3／175.3 MiB，8—44 秒在 174.5—175.3 之间。**结论：没有观察到内存持续上涨。** RSS 在滚动开始后的几秒内上升，进入平台后不再增长；上升部分没有单独归因（候选是首批图片解码与内置加载器的内存缓存，上限 100 张）。

## 2. 内存与泄漏

Leaks 与 Allocations 的统计表不能用 `xctrace export` 导出（TOC 只有 signpost、进程等表，与 2026-10-21 的记录相同），所以在 Instruments 中打开 trace 读取：Leaks 轨道的每次检查都显示为绿色，Leaks 明细表为空；Allocations 数值取统计表的 All Heap & Anonymous VM 行（录制结束时）。RSS 取 App 自己记录的 resident size。Instruments 的分配追踪本身会占用内存并拖慢进程，因此录制下的 RSS 比不录制时高约 35 MiB，`--performance-profile` 在录制下滚得也更慢。

| 场景 | 模板 | 泄漏检查 | 结束时堆＋匿名 VM 常驻 | App RSS 起点／峰值／终点（MiB） |
|---|---|---|---|---|
| `--feed-profile`（本地表情） | Leaks，90 秒 | 7 次，均无泄漏 | 67.93 MiB | 145.0／174.3／170.8 |
| `--feed-profile` | Allocations，60 秒 | — | 66.29 MiB（累计 752.8 MiB） | 146.8／171.6／169.9 |
| `--performance-profile`（180 行固定负载） | Leaks，60 秒 | 5 次，均无泄漏（最后一次在停止并清空之后） | 17.14 MiB | 96.6／116.3／104.6 |
| `--performance-profile` | Allocations，60 秒 | — | 14.64 MiB（累计 4.68 GiB） | 96.5／121.9／109.7 |
| `--performance-profile` | 不录制 | — | — | 59.7／86.1／73.2 |

- 业务列表：滚动期间堆曲线保持水平；Leaks 第一次 60 秒录制里 App 尚未滚完（录制下启动和预排版变慢），改为 90 秒重录，结果以重录为准。第一次录制的 4 次检查同样无泄漏。
- 固定负载页：停止并清空后堆曲线明显回落，结束时常驻 14.64—17.14 MiB。不录制时 RSS 从 59.7 MiB 升到最高 86.1 MiB，清空后为 73.2 MiB。终点高于起点的部分没有单独归因；Leaks 无泄漏，附件计数见下一节。
- **结论：两个页面都没有检测到泄漏，滚动中内存进入平台后不再上涨。** 这仍只覆盖 Leaks 能识别的不可达内存；仍被引用的对象（逻辑泄漏）要靠下一节的附件计数和弱引用检查。

## 3. 附件释放

真机不录制，运行 `--performance-profile`：自动滚动 45 秒后自动“停止并清空”，从 Demo 沙盒取回 `performance-scroll.json`。

| 指标 | 值 |
|---|---:|
| 滚动时长／方向切换／完整往返 | 45.02 秒／6／3 |
| factory（附件视图创建） | 2266 |
| unmount（附件卸载） | 2266 |
| 滚动中最多同时存活的附件视图 | 18 |
| 停止并清空时同步读取的存活视图（`stopSynchronousLiveWeakViews`） | **0** |
| 下一个主队列事件读取的存活视图（`finalLiveWeakViews`） | **0** |
| 停止后残留的动作／按钮 | 0／0 |

Leaks 与 Allocations 录制下的两次运行（factory／unmount 为 139／139 和 475／475）同样以存活 0 结束。**结论：每个创建的附件视图都被卸载，停止后没有存活的附件视图。**

## 4. 触摸

`xcodebuild test -only-testing:LYGlyphTextDemoUITests`，目标为该 iPhone。

| 轮次 | 结果 |
|---|---|
| 第一次（修正前） | 29 通过，1 失败：`ActionDemoUITests.testSelectableActionListSeparatesActionsFromBlankSpace` |
| 修正 `lineEnd` 诊断点后 | **30／30 通过**，0 跳过，`runtimeWarnings=[]` |

失败分析：失败步骤是“点击跨行动作首行行尾之后的空白，应选中列表行而不触发动作”。状态栏显示这一点击触发了第三次 `cross` 动作，没有选中列表行。只运行这一项并打印诊断点后，失败可以复现：这个 Label 两侧内边距为 18pt，`lineEnd` 恰好等于 `contentClip.maxX − 2`，说明旧的计算 `min(contentClip.maxX − 2, 首行.maxX + 12)` 把点夹回了内容边缘。428pt 宽的屏幕上，跨行动作“第一段动作\n第二段动作”在首行排到了内容边缘，夹回后的点落在动作矩形内。组件的命中测试是严格的矩形包含，没有扩展热区，这次点击触发动作是正确行为；问题出在测试夹具假设首行行尾一定有空白，**属于设备环境（屏宽）问题，不是组件代码缺陷**。修正后，跨行动作除最后一行外，取行尾后确有 12pt 空白的第一行：模拟器上仍是首行（行为不变），这台设备上是首行折行后、换行符之前的第二行。测试意图与断言不变。

## 正式检查

| 检查 | 结果 |
|---|---|
| 固定 SwiftFormat 0.59.1（改动的 3 个 Swift 文件）／docs | PASS |
| 真机 Release 构建（Swift 6 模式） | PASS |
| 真机 UI 测试 | 30／30 Passed |
| 完整宿主＋UI 回归（模拟器，最终代码） | **484／484 Passed**（454 宿主＋30 UI），0 失败／跳过，`runtimeWarnings=[]`（`20261102T035247Z-50991-test`） |

模拟器：原专用模拟器 `A3BA636C…` 在本批次中途从 `simctl` 列表消失（不是本任务删除的），改用新建的 `LYGlyphText DeviceFunc 20261102`（iPhone 18 Pro，iOS 27.2）。`lineEnd` 修正之前的一次完整回归是 483／484，唯一失败是 `DemoUITests.testSwiftUIStylesWrappingVerticalAlignmentAndNativeButtons` 报“Test crashed with signal term”（UI 测试进程被终止），与本批次改动无关；最终代码的回归中该项通过。

## 范围与未验证

- 只测了一台 A14 设备、iOS 27.0.1、一个公网图片源（raw.githubusercontent.com，`cache-control: max-age=300`）与当时的网络；弱网、其他服务器缓存头、iOS 16、更旧设备未测。
- 网络图片场景只测了 2800pt/s；Allocations 只录了内置加载器。
- 方向变化未测。人工 VoiceOver 不在本批次范围内，仍未验证。
- 原始 trace、xcresult、日志与回归运行目录（`.build/device-functional/`、`.build/verification/20261102T0*`）未提交，2026-11-02 已按用户要求删除以释放磁盘空间，新建的模拟器 `LYGlyphText DeviceFunc 20261102` 也已删除；本文数值是删除前读取的。App 自测 JSON 汇总保留在 [device-functional-2026-11-02.json](data/device-functional-2026-11-02.json)。
