# 首版发布准备

状态：未发布。路线图允许完成准备和验证，不授权 PR、Tag、Release 或远端删除。最终是否可发布取决于以下独立门槛；自动测试通过不等于全部门槛满足。

## 已核源码边界

- Package 为一个 library product／一个组件 target，`swift-tools-version: 6.0`、Swift 6 language mode、最低声明 iOS 16；不存在第三方 Package 依赖。
- Sources 仅 Swift 文件，导入 UIKit、SwiftUI、CoreText、Foundation、os 等 Apple 框架；Core Text 统一测量／绘制／截断／动作几何，没有 TextKit 或网络加载器。
- 文档／UI／provider／回调使用 MainActor；没有 Sendable 逃生标记。文档不持有 UIView 或业务闭包，工厂不参与测量，每 Label 最多两份布局缓存。
- [MIT 许可](../LICENSE)和[参考来源及许可边界](REFERENCES.md)存在；第三方参考仓库在本仓外，不随组件分发。当前没有第三方源码移植登记，不因“参考”推导获准复制。
- [README](../README.md)描述现有公开接口、point／UTF-16、附件生命周期、宿主／SwiftUI 测量、动作取消与自动无障碍；本地 Package 接入可用，没有虚构版本号安装方式。

以上是 P1 静态源码／清单审查，不代替编译、运行、许可证法律意见或第三方依赖构建结果。具体行为与真实运行以各专项记录为准。

## 验证门槛

| 门槛 | 当前证据及边界 |
|---|---|
| Xcode27.1／Swift6.4 的 Swift6模式 | P1 Package／Demo build 与368／368（344宿主＋24UI）通过，86 Swift冻结一致 |
| 最新可用 iOS Simulator | iPhone17Pro／iOS27，P1完整宿主与UI通过，Release四图与正式四图已导出检查 |
| Swift6.0实际编译器 | R1 已探测，未安装真实 Swift6.0.x，仍未验证；Swift6.4 的 v6 模式不代替，见[R1记录](verification/2026-10-21-minimum-compatibility.md) |
| iOS16实际运行 | R1 未发现 iOS16 runtime／可用设备，0宿主＋0UI，仍未验证；部署目标和新SDK编译不代替运行 |
| 独立公开API消费者 | R1 在Swift6.4／SDK27.1下构建成功（arm64／x86_64、target16.0）；没有运行，不计入上述两项兼容性通过 |
| 真机 | 未验证；模拟器性能不代表设备性能 |
| 自动AX语义／激活 | A1完整回归通过；保留原生附件子树 |
| 人工VoiceOver | 未验证：顺序、停顿、重复朗读、焦点、滚动及按钮体验 |
| 原生任意后代AX frame部分裁切 | 未验证／不保证；父clipsToBounds不保证后代AX frame |
| 固定负载Release与滚动／Instruments | 九组Release、缓存／weak释放与真实列表UI已验收；CPU采样及RSS已归档，分配／泄漏专用结果仍未验证，见[性能记录](verification/2026-10-21-performance-readiness.md) |
| 发布动作 | 未授权，不创建Tag／Release |

## 2.x Label 增量能力的独立门槛

2.x 能力（截断 token、特效、网络图片、预排版、选择拷贝、解析器）按 [2.x 路线图](superpowers/plans/2026-10-21-label-roadmap.md) 逐阶段交付，自动检查结果见各阶段验证记录。以下与 1.0 门槛同样独立、仍未验证：

- 真实网络：内置加载器只用本地 URLProtocol 桩与模拟加载器测试，未连接真实服务器；没有磁盘缓存。
- Kingfisher 桥接：README 示例按其公开 API 编写，本仓不依赖 Kingfisher，未编译。
- 选择拷贝：真实长按与系统菜单拷贝、整段点击与动作分离已有 UI 测试；iOS 17+ 放大镜与拖柄拖动没有 UI 自动化（拖柄未暴露给无障碍），人工 VoiceOver 下的选区、“拷贝”动作与 token 朗读、iPad 指针与外接键盘未验证；iOS 16 没有放大镜。
- 头部／中间截断：自动测试覆盖 LTR、RTL、附件与跨省略处动作；只作用于最后一条可见行，末尾文字取自最后一个有内容的段落。
- 预排版：Release 计时为模拟器数据，不代表真机；后台线程上的 UIFont／动态颜色解析在 iOS 16 上未实际运行。
- iOS 16 运行与 Swift 6.0 编译器同样覆盖 2.x 新代码，均未验证。

## 已知范围限制

只读展示（2.x 已提供选择拷贝、网络图片附件与后台预排版，见上节独立门槛），未提供编辑器、HTML／Markdown、竖排、绕排、异步绘制、放大镜、任意SwiftUI行内视图、内置磁盘图片缓存。标准NSTextAttachment明确拒绝；附件尺寸只来自声明，不按factory intrinsicContentSize反算。StackView首／末文字基线与UILabel等价尚未承诺。

部分既有无scene测试窗口存在appearance控制台警告；A1完整回归61条，xcresult runtimeWarnings为空，已在[A1记录](verification/2026-10-21-environment-accessibility.md)单列，不声称已修复或生产必现。

## 发布前补证顺序

1. 获取真实Swift6.0.x及匹配SDK／完整Xcode构建环境，分别构建Package、Demo、独立公开API消费者并记录实际swiftc路径／版本／日志；本轮未安装或下载，所需环境见[R1记录](verification/2026-10-21-minimum-compatibility.md)。
2. 获取受支持宿主上的iOS16 runtime或具备测试签名条件的可用设备，保留全部368项基线运行适用矩阵；记录具体小版本／build、实际数量及未执行原因，同时保留当前系统证据，不用部署目标代替，不由后续16.x外推更早版本。
3. 真机滚动、内存、方向、触摸及附件释放观测，单列设备和构建配置。
4. 人工启用VoiceOver，逐项检查逻辑阅读、动作／按钮、装饰附件、裁切、滚动和焦点；发现缺陷先保留证据再修复。
5. 在可解释Allocations／Leaks专用表的环境补齐分配与泄漏分析，核对RSS初／峰／末及稳定阶段；已有trace／weak=0不推导为无泄漏。
6. 根据实际验证修订[未发布变更记录](../CHANGELOG.md)、已知限制和版本方案；达到门槛后再由用户授权Tag／Release。
