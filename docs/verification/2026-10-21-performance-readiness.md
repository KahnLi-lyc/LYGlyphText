# P1 固定负载与发布准备验证记录

日期：2026-10-21。基线 `b615c3e036a9816fda9191f52c46915482bd5d1b`，分支 `codex/performance-readiness`。执行契约见[P1计划](../superpowers/plans/2026-10-21-performance-readiness.md)。P1a与P1b代码／定向验收、规格及质量审查通过；根已完成Instruments尝试与归档，正式完整回归368／368及86个Swift前后冻结已通过；最终规格与质量审查均批准；提交集成另按下文留证。

## 已有基线

A1已完成359／359（336宿主＋23UI）、81个Swift冻结、8截图和规格／质量审查，已普通推送核远端SHA一致。本轮保留全部基线；Swift6.0编译器、iOS16、真机、人工VoiceOver和任意原生后代AX frame部分裁切仍独立未验证。

## 静态准备

根已复核Package清单、24个Sources Swift、仅Apple框架导入、零第三方运行依赖、MIT／来源资料、README公开接口和本地Package接入方式。新增[发布门槛](../RELEASE_READINESS.md)及[未发布变更草案](../../CHANGELOG.md)。静态审查不代替实际编译／运行；未创建PR、Tag或Release。

## P1a 输入、缓存与释放

仅新增PerformanceSamples／PerformanceBehaviorTests，不修改组件框架。九组输入精确100／1000／5000 UTF-16×0／3／10附件，20pt字体、320pt宽、24pt附件；3附件为2图1View，10为5图5View，含中文／emoji／阿拉伯文／Latin。完整Character填充后ASCII补齐，metadata保留源位置、字体和配置；makeDocument每次创建独立快照。

- `.build/verification/p1a-fixture-compile/`：缺少样本夹具导致编译失败，0行为测试，不算产品红。
- `p1a-green/`：6／6通过，但新窗口夹具12条appearance警告，不当最终验收。
- `p1a-green-appearance/`：添加didAppear和didDisappear等待后，6项／12个关闭夹具断言失败；隐藏UIWindow不保证根控制器收到didDisappear，该预期不成立，不称组件缺陷。
- `p1a-final/Tests.xcresult`：保留适用的真实didAppear条件等待，**6／6 Passed**，0失败／跳过／预期失败，runtimeWarnings=[]、本块appearance警告0。固定SwiftFormat0.59.1的2文件lint通过，83个Swift before=after=current；根独立复核日志和哈希。

测量覆盖sizeThatFits、intrinsic和fitting，factory=0，frame／bounds／原有约束对象及常量／宿主优先级／子视图不变。九组独立缓存夹具的宽度240,320,240,480,320,240,480对应build1,2,2,3,3,4,4，缓存最多2项；同Document不失效，新Document清缓存且下一查询只增一次build。不将此写为LRU。

六组含View负载各100轮，共600轮真实窗口挂载／稳定布局／reload／移出复挂／清空。每个3附件负载factory=unmount=300，每个10附件负载=1500，三长度合计**5400／5400**，weak存活均0，onUnmount时superview=nil；双宿主实例及清理独立。精确逐组摘要见`p1a-final/verification-summary.json`。这是行为释放证据，不代替进程内存趋势或Instruments。P1a先规格审查、后独立质量审查均批准，无必需修复；当前进入P1b。

## P1b 草稿与失败证据

- `p1b-debug-01` 为 `CGSize` 的 `.infinity` 推断歧义导致编译失败，非行为红；显式 `CGFloat.infinity` 后进入运行。
- `p1b-debug-02` 宿主通过、UI在停止后weak=0等待失败；原始文本显示factory=unmount=1106但同步live=7。下一主队列事件只重新读取真实weak，保留同步值供对比，没有硬置0。
- `p1b-debug-03` 与 `p1b-release-01` 各2／2、runtimeWarnings=[]；86个Swift冻结一致。Debug停止记录为1106／1106、实际weak=0、同步weak=7、action=button=2。Release语义通过后，截图复核发现复用行5／7塌高，故本轮不作为最终视觉验收；规格审查也指出didEndDisplaying清空内容后、willDisplay才重绑可能让空文档参与self-sizing，返回原实施者修复并补行为断言。
- `p1b-height-red-01` 新增真实滚动高度回归，1项／6断言失败：返回后部分cell=21pt、glyph=0，但有效文档natural=74／75pt，预期cell约107.13／108.13pt。保留行为红，不以截图代替断言。修复改为离屏卸载provider／回调／订阅，保留不可变文档和状态字供self-sizing；复用与停止仍完整清空，同一行重绑不先清输入。
- `p1b-debug-04` 自然高度断言无失败，但新宿主夹具未实际挂window，table.window与初始按钮等3项断言失败；UI返回行仍显示button=1，但最终总计button=2，根独立导出的Stop文本为605／605、live=0。原因是单一行刷新闭包被临时测量cell覆盖，改为Apple Combine的每cell独立订阅／独立取消。该轮3方法只有1通过、2失败，不能验收；需修夹具到真实UIWindowScene并等待挂载后再执行。
- `p1b-debug-05` 真实UI 1／1通过（53.051秒），实际window／非空按钮／离屏配对与weak=0断言通过；高度测试误选UIButton.titleLabel且未计UILabel fitting取整，仍失败，不算整轮通过。`p1b-height-green-01` 将差异收窄到物理像素后，52行观测暴露状态字sizeThatFits与fitting向上取整、文字区分配余量，95个断言失败；不改Demo来迁就预期。
- `p1b-height-green-02` 精确选择performanceRowStatus、保留原始高度数据，以natural文字高度＋ceil(status.sizeThatFits.height)＋20pt间距内边距＋separator作为cell预期，cell容差一个物理像素；文字bounds按观察到的fitting分配取整使用±1pt。**1／1通过**、runtimeWarnings=[]，真实离屏卸载与weak=0继续断言。此项可捕获原21pt／glyph0塌高，不能推广所有UIKit版本的取整契约。
- 首次profile尝试设备处于Shutdown，仅container查询失败；启动专用设备后，草稿Allocations记录因无法找到刚启动PID退出21，无trace。应用自己的45.34秒滚动JSON实际记录1次往返、997／997挂载卸载、weak=0；这是修复前夹具观测，不算最终性能或Instruments成功。

## P1b 最终定向与 Release 数据

最终 `.build/verification/p1b-release-02/Tests.xcresult`：**3／3 Passed**（2宿主＋1UI），exit0、0跳过／预期失败、runtimeWarnings=[]。86个Swift before=after=current，根独立核SHA；P1b先规格、再质量审查均批准，无必修项。全量回归尚另验。

九组各30次Document、30次新Label首次sizeThatFits、5次独立warmup、200次hot、30次cachedBitmap，共**2655**个原始ns。根独立核每个样本数／nearest-rank分位数、首次build=1、hot及draw不增build、factory=0。Release02新编译Demo／host的12条swiftc均为-O／WMO／Swift6／enable-testing且无coverage；框架和UITest共29个Swift与Release01一致，沿用同DerivedData及01实际-O编译日志，不以Release名字推导优化。

[原始Release数据](data/performance-release-2026-10-21.json)、[根独立重算](data/performance-release-recomputed-2026-10-21.json)、[52条行高记录](data/performance-row-heights-2026-10-21.json)及[截图SHA索引](data/performance-screenshot-index-2026-10-21.json)已跟踪保存。环境为Xcode27.1／Swift6.4／iOS27 Simulator，320pt、20pt字体、scale3；表内为 **p50／p95，单位µs**，不表示真机或进程冷启动。

| UTF-16／附件数 | 文档构造 | 新Label首次测量 | 同Label热缓存 | 缓存位图绘制 |
|---|---:|---:|---:|---:|
| 100／0 | 14.542／28.875 | 1640.959／2195.667 | 0.209／0.250 | 352.875／416.042 |
| 100／3 | 15.458／19.500 | 1732.709／1923.959 | 0.209／0.250 | 446.959／473.541 |
| 100／10 | 19.292／23.167 | 1808.459／1844.292 | 0.209／0.250 | 586.500／709.792 |
| 1000／0 | 97.083／106.708 | 11420.959／11831.666 | 0.209／0.250 | 1033.541／1152.292 |
| 1000／3 | 99.500／104.458 | 11719.041／12763.875 | 0.209／0.250 | 1096.125／1123.542 |
| 1000／10 | 101.125／109.792 | 11965.625／13332.875 | 0.209／0.250 | 1203.000／1267.500 |
| 5000／0 | 478.084／511.458 | 58998.750／62154.750 | 0.250／0.250 | 2584.666／2664.750 |
| 5000／3 | 488.250／517.792 | 60672.666／64710.750 | 0.250／0.250 | 2652.166／2789.625 |
| 5000／10 | 498.166／542.000 | 60243.167／61955.291 | 0.209／0.250 | 2597.583／2796.834 |

位图为预分配960×480px（320×160pt），每轮计时外clear，裁切自然不限行布局，`includesViewSubtree=false`。不把该数值当原生附件／整页渲染成本。长文首次测量开销显著高于热缓存；不设未经约定的FPS／内存门槛，真机性能仍需补证。

真实180行列表为9组×20，320pt、3行省略；实际AX操作文字和原生按钮，滚离后其他行状态0，返回后二次操作保持各自行状态。最终Stop原始文本factory=unmount=605、live=0、action=button=2，同步临时live=12单列。52行cell最大误差约0.00000254pt、glyph最大1pt。根已逐张检查四图，完整可见行无细条，视口边界的部分行裁切符合预期：

- [首次动作与按钮](images/performance-actions-native-button.png)
- [滚动复用](images/performance-reused-scrolled.png)
- [返回行状态](images/performance-return-state.png)
- [停止清空](images/performance-stopped-cleared.png)

## Instruments 与持续滚动

根在Release02同源binary上串行执行三轮；每轮删除上次app输出、启动新的`--performance-profile`进程，保存独立trace和JSON，不复用旧文件。每轮实际应用自动滚动约45秒，每帧检查、普通采样间隔至少1秒（停止时另补一条），记录offset／方向／累计挂载卸载／实际weak及`mach_task_basic_info.resident_size`。死亡weak包装在追加时剪枝，不保活UIView。RSS包含App、系统缓存、采样工具和Demo诊断开销，不能当附件占用、无泄漏结论或真机性能。

[三轮摘要](data/performance-profiles-2026-10-21.json)、[Allocations滚动原始值](data/performance-scroll-allocations-2026-10-21.json)、[Leaks滚动原始值](data/performance-scroll-leaks-2026-10-21.json)、[Time Profiler滚动原始值](data/performance-scroll-time-profiler-2026-10-21.json)及[CPU样本摘要](data/performance-time-profile-2026-10-21.json)已跟踪。

| 模板 | trace秒 | 录制器退出 | 应用秒／完整往返 | factory／unmount／weak | RSS初／峰／末 MiB |
|---|---:|---|---|---|---|
| allocations | 35.695597 | 控制器80秒超时；正常退出未确认 | 45.310／0 | 601／601／0 | 237.55／325.48／302.30 |
| leaks | 35.624735 | 0 | 45.116／0 | 318／318／0 | 237.67／332.55／288.25 |
| time-profiler | 35.614770 | 0 | 45.056／2 | 1718／1718／0 | 237.53／292.45／279.69 |

三轮各有33／18／44条观测；采样受主线程开销影响，Leaks最大间隔10.6秒，不称固定频率或流畅性通过。三轮trace的TOC均导出exit0，报告Time limit reached；process-info表均导出exit0。Allocations在80秒控制器时限后被终止录制器，保留可读trace，不能称录制命令正常结束。Leaks与Time Profiler录制和保存均exit0。Time Profiler的time-profile表导出exit0，31269条样本、31255条主线程；样本含系统及Demo，不转换为FPS或组件独占CPU。

当前xctrace TOC未暴露Allocations／Leaks专用统计表，故只确认模板实际运行与trace保存，**分配／泄漏专用结果解释仍未验证**；没有声明“无泄漏”。RSS末值也高于初值，不推导为已稳定或泄漏。原始trace／TOC／导出XML、完整命令／退出状态／环境路径留在：

- `.build/verification/p1-profile-allocations-20261021T063253Z/`
- `.build/verification/p1-profile-leaks-20261021T063649Z/`
- `.build/verification/p1-profile-time-profiler-20261021T063855Z/`

实际触摸来自Release UI，不拿自动滚动的action=button=0替代按钮测试。自动滚动在采样开销下实际完成的往返数分别0／0／2，如实记录，不捏造固定轮次或帧率门槛。

## 正式回归与交付

正式 `scripts/verify.sh docs`、SwiftFormat0.59.1（86文件，0需格式化）及Swift6模式Package／Demo build均exit0。完整 `scripts/verify.sh test 5260ADE6-ADC2-44AA-9EEB-CDEC90196D08` 已exit0，**368／368 Passed（344宿主＋24UI）**，0失败／跳过／预期失败，xcresult `runtimeWarnings=[]`。[正式回归摘要、环境与86个源码哈希](data/performance-regression-2026-10-21.json)已跟踪保存。命令不含only-testing或skip-testing；原有359方法及对应文件内容完整保留，新增8宿主＋1UI。正式Debug计时仅为sanity，不填入上述Release表。

- 构建：`.build/verification/20261021T064244Z-59342-build/`。
- 完整测试：`.build/verification/20261021T064418Z-59586-test/Tests.xcresult`、`test-summary.json`及`tests.log`。
- 汇总与源码：`.build/verification/p1-final/summary.json`、`test-tree.json`、`baseline-retention.json`、`swift-before.json`和`swift-after.json`；86个Swift before=after=current。
- 正式UI附件全部已导出到`.build/verification/p1-final/attachments/`，性能四图另命名保存在`screenshots/`；逐张复核无完整行塌高，返回行动作／按钮各2次，停止后**599／599、weak=0**，同步weak=12单列。正式Debug与Release02的605／605计数不同，按各轮原始观测保留，不互相替代。

控制台仍有既有**61条appearance警告**；另有Xcode环境`invalidDigitCount(94232)`及debugger version lookup诊断，不声称已消除；xcresult runtimeWarnings为空不等于控制台无警告。未修改组件源码、Package或project.yml。

最终规格审查批准后，独立质量审查也批准，无必须修复项；两位审查者分别复核当前diff、测试树、源码冻结与证据。按CONTRIBUTING在独占锁内验证同一候选、快进main、普通push一次并核对远端SHA；结果保存在本机`.build/verification/p1-final/delivery.json`和Git历史，不用待执行操作冒充当前远端状态。Swift6.0编译器、iOS16、真机、人工VoiceOver以及分配／泄漏专用表仍未验证。连续队列中可独立执行的首版实现与准备已验收；后续只按[发布补证清单](../RELEASE_READINESS.md)推进，不扩充首版范围或创建Tag／Release。
