# 变更记录

## 1.0.0-beta.1 — 2026-10-29

首个预发布版本，合并此前内部批次（1.0 只读组件、2.x Label 路线图 G1—G7、L 批次、S 批次）。Tag `1.0.0-beta.1`，未创建 GitHub Release。

### 基础能力

- UIKit／SwiftUI 共用 Core Text 的只读富文本，支持分段构建、样式和段落、换行、行数限制与尾部省略。
- UIImage 与宿主工厂 UIView 行内附件、三种对齐、可见挂载／卸载和原生按钮；文档与测量不创建 UIView。
- 文字 tap／longPress、按下绘制、取消与滚动协作、最新回调、附件触摸优先。
- Auto Layout、StackView、UITableView／UICollectionView 自适应和 SwiftUI 容器／列表矩阵。
- 默认动态 body、语义颜色、RTL、最终可见自动无障碍语义与动作激活。
- 固定负载、Release测量及发布准备按[P1计划](docs/superpowers/plans/2026-10-21-performance-readiness.md)执行，结果见[验证记录](docs/verification/2026-10-21-performance-readiness.md)。

### Label 增强能力

- 可自定义截断 token（文字、字体、颜色，可点击，事件 `isTruncationToken`）；按下样式 `cornerRadius`；`.shadow`、`.strokeWidth`／`.strokeColor`；`linkPressedStyle` 把 `.link` 转为动作。
- 远程图片附件 `LYGlyphTextRemoteImageAttachment`、加载协议 `LYGlyphTextImageLoading` 与系统框架默认加载器 `LYGlyphTextURLSessionImageLoader`（内存缓存、请求合并、降采样、GIF）；可桥接 Kingfisher 等宿主图片库。
- 后台预排版 `LYGlyphTextPreparedLayout` 与 `LYGlyphTextLabel.apply(_:)`；内部 Layout 层改为非隔离，Swift 6 下无并发逃生标记。
- 长按选择与系统菜单拷贝：`isSelectable`、`selectedRange`、`selectedText`、`onSelectionChange`。
- 文本解析器 `LYGlyphTextParser`：链接、@提及、#话题#、自定义正则与表情短码图片。
- SwiftUI `LYGlyphTextView` 新增 `imageLoader`、`isSelectable`、`onSelectionChange` 参数。
- L 批次：圆角背景／边框 `NSAttributedString.Key.lyGlyphTextBackground`；整段点击 `onTap`；拷贝同时写入纯文本与 RTF、iOS 17+ 放大镜、无障碍“拷贝”动作；`onRemoteImageLoad` 与 `replacingRemoteImageSize(id:size:)`；`truncationMode` 支持 `.head`／`.middle`；SwiftUI 对应新增 `onTap`、`onRemoteImageLoad`。Release 复测见 [L6 记录](docs/verification/2026-10-29-l6-performance-retest.md)。
- S 批次：选区拖柄成为可调节无障碍元素（`selectionStartAccessibilityName`／`selectionEndAccessibilityName`）；`LYGlyphTextURLSessionImageLoader` 新增专用磁盘缓存（`diskCacheCapacity`、`diskCacheDirectory`、`removeAllCachedImages()`）；解析规则 `.markdownEmphasis()` 与 `.markdownLinks(attributes:pressedStyle:)`；调试叠加 `LYGlyphTextDebugOptions` 与 Label／SwiftUI 的 `debugOptions`。验证见 [S1—S5 记录](docs/verification/2026-10-29-s1-s5-label-features.md) 与 [S6 RocketSim 记录](docs/verification/2026-10-29-s6-rocketsim.md)。

### 兼容性与验证状态

源码兼容说明：`LYGlyphTextSegment` 新增 `.remoteImage` case、`LYGlyphTextDocumentError` 新增 `.unknownAttachmentID`（L4），对穷举 switch 的宿主代码需要补充分支；其余均为新增可选参数或类型。未提供：编辑器、异步绘制；iOS 16 没有放大镜。验证结果见各阶段记录。

发布前完整回归在 Xcode 27.1／Swift 6.4 的 Swift 6 模式、iOS 27 Simulator 上通过，数量见 [S7 记录](docs/verification/2026-10-29-s7-release.md)。以下仍未验证，这是本版本标为 beta 的原因：Swift 6.0 实际编译器、iOS 16 实际运行、真机、人工 VoiceOver、真实公网图片服务器、Kingfisher 桥接编译、Allocations／Leaks 专用分析。完整门槛见 [发布准备](docs/RELEASE_READINESS.md)。
