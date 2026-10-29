# C6 真机性能测量（初步，未完成）

日期：2026-10-29。设备 iPhone 12 Pro Max（A14，60Hz），iOS 27.0.1；Release（`-O -whole-module-optimization`）、个人开发证书签名（只在命令行传入，不写入仓库）。录制工具 `xctrace` 的 Animation Hitches 模板，每组 55 秒，其中自动往返滚动 45 秒。

## 场景

Demo 新增 `FeedPerformanceController`（启动参数 `--feed-profile`）：180 行，每行 100—300 字、3—5 个表情、@／#／链接，5 行截断并带图文 token，后台预排版后 cell 直接采用。`-feedScrollSpeed` 调整滚动速度，`-feedUseUILabel YES` 改用系统 UILabel（相同文字与 NSTextAttachment 表情，无预排版）作为对照组。

## 初步数据

卡顿时间比 = 应用进程 hitch 总时长 ÷ 录制跨度，**包含启动阶段**（未按滚动区间裁剪：Animation Hitches 模板没有记录 Demo 的 signpost）。

| 场景 | LYGlyphText | UILabel 对照 |
|---|---|---|
| 2800pt/s | 22.6 ms/s（59 次，最大 50ms） | 15.2 ms/s（37 次，最大 83ms） |
| 800pt/s | 56.1 ms/s（140 次，最大 200ms） | 26.3 ms/s（57 次，最大 217ms） |

两者都超过 5ms/s，LYGlyphText 约为对照组的 1.5—2 倍；Instruments 对多数卡顿标注为“Potentially expensive app update(s)”（主线程更新耗时）。

## 尚未完成（用户要求本轮先收尾，后续继续）

- Time Profiler 归因：卡顿帧里主要耗时是否在 LYGlyphText 绘制（门槛的第二个条件），尚未录制。
- 按滚动区间裁剪统计（改用 Time Profiler／自定义模板记录 signpost，或在 Demo 内用 CADisplayLink 自测掉帧）。
- 180 行固定负载列表（`--performance-profile`）录制被中止；设备上的 `PerformanceMeasurementTests` 未运行。

**结论暂不下**：卡顿门槛的第一个条件已满足，第二个条件（耗时主要在 LYGlyphText 绘制）尚未验证，异步绘制是否立项待归因后决定。原始 trace 保存在本地 `.build/verification/c6-device/`（不提交）。
