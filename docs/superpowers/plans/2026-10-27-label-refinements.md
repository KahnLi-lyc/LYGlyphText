# LYGlyphText Label 后续完善（L 批次）

> **For agentic workers:** 沿用[连续开发契约](2026-10-20-continuous-development.md)与 [CONTRIBUTING](../../../CONTRIBUTING.md)：每项先写契约与失败测试，再实现、定向测试、docs／format／build／完整宿主＋UI 回归、记录，中文提交，锁内快进 main 并普通推送一次。不创建 PR、Tag 或 Release。

**起点：** main `a3dfd74`，2.x G1—G7 已交付，完整回归 419／419（393 宿主＋26 UI）。

**范围约束：** 只做 Label；Core Text 唯一内核；零第三方运行依赖；iOS 16+、Swift 6；只增加公开 API，默认值保持现有行为。用户于 2026-10-27 选定以下内容，编号 L 以避免与已有任务代号冲突。

| 编号 | 内容 | 接口与行为契约 | 关键验收 |
|---|---|---|---|
| L0 文档修正与契约（已交付 `4d9575b`） | 修正发布准备中过时的范围限制；写入本契约；总计划队列与连续开发契约登记 L 批次 | 只改文档 | docs 检查 |
| L1 文档级圆角背景／边框（已交付 `983833e`） | 公开属性键 `NSAttributedString.Key.lyGlyphTextBackground`，值为 `LYGlyphTextBackgroundStyle`（填充色、描边色、描边宽度、圆角、外扩边距，均可选，非法值清洗）。文档白名单读取；同一样式的片段按行合并后绘制圆角路径，位于普通背景之上、文字之下；不改变测量；可用于解析器规则的 attributes | 像素：圆角角点、描边、跨行分段、RTL；明暗动态颜色；与按下样式叠加；尺寸不变 |
| L2 整段点击回调（已交付 `93ebf0e`） | `LYGlyphTextLabel.onTap`（SwiftUI 对应参数）。仅在设置时安装识别器；落在动作、可交互 token、交互附件或已有选区上不触发；未设置时行为完全不变 | 真实 UI：普通文字触发、动作只发动作、未设置时 cell 可选中、滚动不误触 |
| L3 选择拷贝增强（已交付 `ee1c060`） | 拷贝同时写入纯文本与富文本（附件转替代文本）；iOS 17+ 拖动拖柄显示放大镜，iOS 16 无；有选区时提供无障碍自定义动作“拷贝”；拖柄拖出 Label 时收敛到最近边界 | 剪贴板两种表示一致；AX 动作可执行；UI 拖动拖柄扩大选区 |
| L4 网络图片真实尺寸（已交付 `b662530`） | `onRemoteImageLoad` 回报加载后图片 point 尺寸；`LYGlyphTextDocument.replacingRemoteImageSize(id:size:)` 便于宿主重建。组件不在加载后自动改排版 | 回调时机与尺寸；取消后不回调；替换后测量变化；非法尺寸报错；复用不串行 |
| L5 头部／中间截断（已交付 `4c58a28`） | `LYGlyphTextConfiguration.truncationMode`：`.tail`（默认）、`.head`、`.middle`，只作用于最后一条可见行。head：token＋剩余原文末尾；middle：末行开头＋token＋剩余原文末尾。内部把单一原文偏移推广为分段映射，命中、选区、附件、AX、绘制统一使用 | 既有截断测试全部通过；LTR／RTL／emoji／附件／跨省略处动作的命中与可见区间；截图 |
| L6 Release 性能复测（已交付 `1b22ca7`） | 以 P1 方法重跑九组 Release 计时与预排版计时，对比 P1 原始数据；不设硬阈值，明显回退先定位再修 | 数据入 `docs/verification/data/` 并有对比表 |
| L7 收尾（已交付 本提交） | README、CHANGELOG、发布门槛、路线图与 SwiftUI 参数补齐 | 完整回归 |

L5 改动面最大，放在功能项最后，失败不影响 L1—L4 交付。需要用户环境或授权的补证（Swift 6.0、iOS 16、真机、人工 VoiceOver、真实项目中的 Kingfisher 桥接、版本与 Tag）不在本批次。

**完成情况（2026-10-29）：** L0—L7 全部交付并推送；各阶段记录见 `docs/verification/2026-10-27-l*.md` 与 `2026-10-29-l6-performance-retest.md`。包含 L2—L5 全部代码的完整回归 442／442（415 宿主＋27 UI）；L6 与 L7 未改 Swift 源码，沿用该次回归。仍未验证：Swift 6.0 编译器、iOS 16 运行、真机、人工 VoiceOver、真实网络与 Kingfisher 桥接编译、Allocations／Leaks 专用分析。
