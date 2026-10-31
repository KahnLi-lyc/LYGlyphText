# P2 列表滚动性能（模拟器）验证记录

日期：2026-10-31。起因：[C6 真机初步数据](2026-10-29-c6-device-performance.md)显示，业务图文列表中 LYGlyphText 的滑动卡顿约为系统 UILabel 的 1.5—2 倍。本批次先在模拟器上量化、归因，再优化。

环境：Xcode 27.2，Swift 6 语言模式，Release（`ENABLE_TESTABILITY=YES`）；本仓新建的专用模拟器 `LYGlyphText Perf 20261031`（`A3BA636C-DE71-4394-93B3-54B175525800`，iPhone 18 Pro，iOS 27.2）。原专用模拟器 `5260ADE6…` 已不存在。机器上其他任务的模拟器使 load average 在 100—570 之间波动，因此两种实现交替运行，只比较相对差异。**模拟器使用 Mac 的 CPU／GPU，绝对值不代表真机。**

## 方法

- `FeedScrollBenchmarkTests`（Demo 宿主测试）：在挂到 app scene 的 390×844 window 中放入业务图文列表（180 行，每行 100—300 字、3—5 个表情、@／#／链接，5 行截断，带图文 token；LYGlyphText 组在后台预排版，UILabel 对照组使用相同文字与 NSTextAttachment 表情）。每步把 `contentOffset` 推进 13.3pt 或 46.7pt（对应 60Hz 下 800／2800pt/s），随后 `layoutIfNeeded()` + `CATransaction.flush()`，让布局与绘制在主线程同步完成并计时；300 步，两种实现交替 3 轮。
- 计数器 `MeasurementCounters`（内部）：主线程完整布局构建、无障碍快照构建、trait 失效次数。
- 模拟器 Time Profiler：Release app 以 `--feed-profile` 启动并自动滚动，录制 40 秒，按类别汇总主线程样本（包含式）。

## 基线（优化前，main `eafe0b2` + 基准代码）

| 每帧位移 | 实现 | p95（3 轮） | 300 步总耗时（3 轮） | 完整布局 | 无障碍快照 | trait 失效 |
|---|---|---|---|---|---|---|
| 13.3pt | LYGlyphText | 3.6／4.6／4.0ms | 136／174／150ms | 36 | 33 | 3 |
| 13.3pt | UILabel | 1.7／2.2／1.9ms | 71／304*／81ms | — | — | — |
| 46.7pt | LYGlyphText | 4.0／4.7／3.8ms | 388／436／366ms | 113 | 110 | 3 |
| 46.7pt | UILabel | 2.3／2.2／1.7ms | 238／209／183ms | — | — | — |

\* 该轮出现一次 110ms 的单步异常（机器负载），p95 不受影响。

LYGlyphText 约慢 2 倍，与真机比例一致。计数器显示：**已开启预排版，每个新出现的 cell 仍在主线程做 1 次完整布局，并构建 1 次无障碍快照**；trait 失效只在启动时发生 3 次。

### 主线程耗时归因（Time Profiler，8351 个样本）

| 占比 | 位置 |
|---|---|
| 43.2% | `LYGlyphTextLabel.intrinsicContentSize` → `measuredLayout` → 完整布局 |
| 23.4% | 其中 `LYGlyphTextLayout.init` 生成显示数据（`SourceGeometry` 15.5%，装饰与按下绘制计划 7.7%） |
| 3.3% | `prepareAccessibility` |
| 2.7% | `LYGlyphTextLabel.draw(_:)`（实际绘制） |
| ≈0% | `traitCollectionDidChange` |

结论：差距主要来自 Auto Layout 自适应行高时的尺寸查询。`intrinsicContentSize` 先按“不限宽度”在主线程完整排版（预排版只覆盖实际宽度），而且这次排版还生成了只用于绘制和点击的显示数据；采用预排版时缓存又被清空，导致反复重建。实际绘制只占 2.7%，**异步绘制不能解决这个差距**。

## 优化

| 步骤 | 提交 | 内容 |
|---|---|---|
| P2.0 | `4a4ee05` | 基准测试、计数器、基线与归因 |
| P2.1 | `39ded51` | 不限宽度的尺寸查询（`intrinsicContentSize`、无限宽 `sizeThatFits`、非 required 的 `systemLayoutSizeFitting`）改走只求尺寸路径：只算行、截断与高度，不生成源几何、装饰、动作索引与按下绘制计划；`LayoutCache` 单独保存理想宽度尺寸，采用预排版时保留；预排版在后台一并算好理想宽度尺寸。`IdealSizeTests` 断言 7 组输入 × 2 种显示比例 × 4 种宽度下尺寸与完整布局完全一致 |
| P2.2 | `663eb1d` | 无障碍元素按需构建：只在 VoiceOver／切换控制运行时随展示事务提前准备，其余情况在 `accessibilityElements` 读取时构建；UI 测试 30 项通过 |
| P2.3 | `7fa120c` | `traitCollectionDidChange` 只在 `LayoutEnvironment` 变化时重新排版；新增尺寸类别不重排、明暗仍重排的测试 |

## 优化结果（main `7fa120c`）

| 每帧位移 | 实现 | p95（3 轮） | 300 步总耗时（3 轮） | 完整布局 | 无障碍快照 | trait 失效 |
|---|---|---|---|---|---|---|
| 13.3pt | LYGlyphText | 0.91／0.82／0.82ms | 48／46／47ms | 0 | 0 | 0 |
| 13.3pt | UILabel | 1.83／1.44／1.63ms | 77／62／74ms | — | — | — |
| 46.7pt | LYGlyphText | 0.98／1.02／0.88ms | 105／104／104ms | 0 | 0 | 0 |
| 46.7pt | UILabel | 2.78／1.58／2.08ms | 270／176／214ms | — | — | — |

与基线比较（同一轮内相对 UILabel）：每步 p95 从约 2 倍降到约 0.5 倍；46.7pt 每帧位移下 300 步总耗时从 366—436ms 降到 104—105ms。各轮次的机器负载不同（基线时 load average 约 110—570，结果时约 11—22），绝对值不宜跨轮直接相减，以同轮内与 UILabel 的比值为准。`FeedScrollBenchmarkTests` 现断言：采用预排版后滚动中主线程完整布局为 0，辅助功能未运行时无障碍快照为 0。

### 主线程耗时归因（优化后，5459 个样本）

| 占比 | 位置 | 基线 |
|---|---|---|
| 0.7% | `intrinsicContentSize` → 完整布局 | 43.2% |
| 0% | `prepareAccessibility` | 3.3% |
| 7.5% | `LYGlyphTextLabel.draw(_:)` | 2.7% |
| 0% | `traitCollectionDidChange` | ≈0% |

绘制本身没有变慢，占比上升是因为总量下降。LYGlyphText 在主线程上剩下的主要成本是绘制（7.5%），其余主要是 UITableView 布局与 Core Animation 提交，与 UILabel 组相同。

## 正式检查

| 检查 | 结果 |
|---|---|
| 固定 SwiftFormat 0.59.1／docs | PASS |
| build（Package 与 Demo，Swift 6 模式） | PASS |
| 完整宿主＋UI 回归（main `7fa120c` 代码） | **484／484 Passed**（454 宿主＋30 UI），0 失败／跳过，`runtimeWarnings=[]`（`20261031T094544Z-93923-test`）；原有 478 项全部保留 |

## 结论与后续

- 模拟器上，业务图文列表的滚动成本已低于系统 UILabel 对照组；差距的主要原因（尺寸查询在主线程重复完整排版）已消除。
- 异步绘制：模拟器归因显示绘制只占主线程 7.5%，暂无立项依据。按 C6 门槛，下次接真机时复测 Animation Hitches；只有真机仍超过 5ms/s 且卡顿帧主要耗时在 LYGlyphText 绘制，才新开异步绘制批次。
- 模拟器数据不代表真机；真机复测未做。
