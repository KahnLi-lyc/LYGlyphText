# 变更记录

## 未发布

这是首版发布说明草案，无版本 Tag 或 Release。

- UIKit／SwiftUI 共用 Core Text 的只读富文本，支持分段构建、样式和段落、换行、行数限制与尾部省略。
- UIImage 与宿主工厂 UIView 行内附件、三种对齐、可见挂载／卸载和原生按钮；文档与测量不创建 UIView。
- 文字 tap／longPress、按下绘制、取消与滚动协作、最新回调、附件触摸优先。
- Auto Layout、StackView、UITableView／UICollectionView 自适应和 SwiftUI 容器／列表矩阵。
- 默认动态 body、语义颜色、RTL、最终可见自动无障碍语义与动作激活。
- 固定负载、Release测量及发布准备按[P1计划](docs/superpowers/plans/2026-10-21-performance-readiness.md)执行，结果见[验证记录](docs/verification/2026-10-21-performance-readiness.md)。

截至P1，Xcode27.1／Swift6.4 的Swift6模式、iOS27 Simulator正式368／368（344宿主＋24UI）通过；九组Release数据、缓存／释放和真实列表证据已归档。此记录不是发布资格证明；Swift6.0编译器、iOS16实际运行、真机、人工VoiceOver及性能结果独立留证。完整门槛与限制见[发布准备](docs/RELEASE_READINESS.md)。
