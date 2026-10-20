# LYGlyphText 下一轮：UIView 附件工厂、挂载复用与生命周期

> 后续实施提案，尚未执行。执行时使用 executing-plans 逐项推进，不在图片附件轮次加入 UIView 功能。

**目标：** 在已验收的图片几何之上支持宿主独占的真实 UIView，先保证测量无副作用、可见性同步和幂等清理。

**架构：** Core Text 仍只消费不可变尺寸，不持有 UIView／工厂；Label 在 MainActor 根据最终可见几何管理子视图，SwiftUI 包装复用同一宿主。保持 iOS 16+、Swift 6、纯 Swift、零第三方运行依赖。

## 接口与默认方案

- 保留现有 LYGlyphTextAttachment 的 UIImage 属性及初始化接口。新增独立 `LYGlyphTextViewAttachment`，包含 id、viewID、明确 size、alignment（默认 bottom）、alternativeText 和 isInteractive（默认 false），不持有 UIView 或闭包。
- 文档入口新增默认空的 `viewAttachments: [Int: LYGlyphTextViewAttachment]`；与图片共用 UTF-16 独立 U+FFFC 校验，跨两种附件校验唯一 ID，同一位置只能声明一种附件。
- 新增 MainActor 的 `LYGlyphTextAttachmentViewProvider` 引用类型，保存 makeView 和可选 onUnmount 闭包。对象身份表示工厂版本：同一对象重新赋值不重建，替换对象或调用 `reloadAttachments()` 显式失效。makeView 接收视图附件描述并返回 UIView?，onUnmount 接收描述和已挂载视图。
- UIKit 增加 viewProvider 和 reloadAttachments；SwiftUI 输入同一个 provider 对象，updateUIView 总更新输入但按对象身份判断是否更换，不通过比较闭包或每次 update 自动重建。
- 本轮只接入附件自身的 UIControl／手势；文字点击、长按、高亮、附件额外内边距、网络加载和跨 Label 全局复用池仍不纳入。

## 实施任务

- [ ] **模型与统一几何。** 新增描述及错误测试；让内部附件度量与最终可见放置结果同时覆盖图片和 UIView，保留现有图像回归。工厂实际 frame／intrinsicContentSize 不能改变声明排版尺寸。
- [ ] **可见挂载与局部复用。** 仅在展示布局阶段调用工厂；按完整矩形与实际内容可见区的交集管理挂载。连续可见的同 ID 只更新 frame；完全隐藏／被截断时卸载并释放，重新出现再创建，不保留隐藏视图缓存。部分可见视图通过宿主内容容器裁切，裁切外不响应触摸。
- [ ] **失败与所有权。** 同一工厂版本下，nil／拒绝结果在附件持续可见期间不反复重试；离开可见集后重入或显式 reload 可重试。返回带有 superview 的视图或已被当前宿主其他 ID 使用的同一实例时拒绝，不抢占、不输出完整文本。两个 Label 必须独立调用工厂并持有不同实例。
- [ ] **生命周期。** 文档替换、nil 清空、provider 更换／reload、移出 window 及 SwiftUI dismantle 均卸载当前集合。每次成功挂载对应一次 onUnmount，重复清理无副作用，工厂 nil 不触发该回调。移出 window 保留配置，重新进入时重新挂载；dismantle 清空文档及 provider，解除闭包持有。清理不初始化 lazy 子视图，deinit 不访问 UI。
- [ ] **示例与验收。** 两端使用同一描述，提供 UIImageView、按钮、自定义徽章、nil 工厂和清空／reload 控制；加入列表复用和真实按钮操作测试，记录工厂／卸载计数、weak 释放证据、尺寸与截图。

## 测试与交付

- 所有测量入口、宽度往返、SwiftUI proposal 与 Auto Layout 离屏测量的工厂调用数为 0；声明尺寸变更通过新文档失效布局。
- 持续可见的附件换宽不重建；被截断或外部高度完全隐藏时卸载；恢复、文档替换、nil 失败、reload 和 provider 更换的调用／清理次数精确断言。
- 同文档双宿主独立；错误共享视图不被抢走；部分裁切区域不响应，按钮实际点击只执行自身事件；布局优先级、现有图片方向和尾部省略回归保留。
- SwiftUI 同 provider 更新不重建、换 provider 使用新闭包、dismantle 重复安全；weak 引用验证旧视图和旧 provider 释放。示例闭包避免强持有宿主形成循环。
- 运行 docs、固定版本 format、build 和指定独占 Simulator 的完整宿主／UI 测试，记录非零数量和截图；Swift 6.0 编译器、iOS 16、VoiceOver 和真实设备各自留证，不由新 SDK 编译推导通过。
- 验证通过后使用任务分支并按独占集成锁安全合入本地 main，随后按 CONTRIBUTING 默认普通推送至 origin/main；不创建 Tag 或 Release。
