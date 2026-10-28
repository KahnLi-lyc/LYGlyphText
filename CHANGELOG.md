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

## 2.x Label 能力（未发布）

按 [2.x Label 路线图](docs/superpowers/plans/2026-10-21-label-roadmap.md) 增量交付，只增加 API；无版本 Tag 或 Release。

- 可自定义截断 token（文字、字体、颜色，可点击，事件 `isTruncationToken`）；按下样式 `cornerRadius`；`.shadow`、`.strokeWidth`／`.strokeColor`；`linkPressedStyle` 把 `.link` 转为动作。
- 远程图片附件 `LYGlyphTextRemoteImageAttachment`、加载协议 `LYGlyphTextImageLoading` 与系统框架默认加载器 `LYGlyphTextURLSessionImageLoader`（内存缓存、请求合并、降采样、GIF）；可桥接 Kingfisher 等宿主图片库。
- 后台预排版 `LYGlyphTextPreparedLayout` 与 `LYGlyphTextLabel.apply(_:)`；内部 Layout 层改为非隔离，Swift 6 下无并发逃生标记。
- 长按选择与系统菜单拷贝：`isSelectable`、`selectedRange`、`selectedText`、`onSelectionChange`。
- 文本解析器 `LYGlyphTextParser`：链接、@提及、#话题#、自定义正则与表情短码图片。
- SwiftUI `LYGlyphTextView` 新增 `imageLoader`、`isSelectable`、`onSelectionChange` 参数。
- L 批次：圆角背景／边框 `NSAttributedString.Key.lyGlyphTextBackground`；整段点击 `onTap`；拷贝同时写入纯文本与 RTF、iOS 17+ 放大镜、无障碍“拷贝”动作；`onRemoteImageLoad` 与 `replacingRemoteImageSize(id:size:)`；`truncationMode` 支持 `.head`／`.middle`；SwiftUI 对应新增 `onTap`、`onRemoteImageLoad`。Release 复测见 [L6 记录](docs/verification/2026-10-29-l6-performance-retest.md)。

源码兼容说明：`LYGlyphTextSegment` 新增 `.remoteImage` case、`LYGlyphTextDocumentError` 新增 `.unknownAttachmentID`（L4），对穷举 switch 的宿主代码需要补充分支；其余均为新增可选参数或类型。未提供：编辑器、异步绘制；iOS 16 没有放大镜。验证结果见各阶段记录。
