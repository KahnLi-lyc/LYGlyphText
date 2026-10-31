# 变更记录

## 未发布

C 批次（核心场景收口）：只补图文混排、高亮点击、长按复制三个场景内的小缺口；与 YYLabel 的逐项对比和不做清单见[能力对比](docs/YYLABEL_COMPARISON.md)。以下均为新增 API，旧调用行为不变。

### 新增

- 本地图片附件 `LYGlyphTextAttachment` 新增 `contentMode`（默认 `.scaleToFill`，保持原拉伸行为），语义与 UIImageView 相同，超出声明框的部分裁切，不改变排版。
- `LYGlyphTextDocument(text:font:foregroundColor:)`：纯文本一行构造文档；文本含 U+FFFC 时与其他入口一样抛错。
- 截断 token 支持文字与图片片段：`LYGlyphTextTruncationToken.Piece`、`pieces` 与 `init(pieces:...)`，可组合“…全文 + 图标”；头部、中间、尾部截断与预排版都适用，无障碍朗读文字片段与图片替代文本。
- Demo 固定引入 Kingfisher 8.14.0（只用于 Demo App target；该版本要求 swift-tools 6.2，Demo 因此需要 Swift 6.2 及以上工具链），提供已编译的 `KingfisherImageLoader` 桥接与加载器切换演示；组件 Package 仍无第三方依赖。

### 性能

- 列表自适应行高时，不限宽度的尺寸查询改走只求尺寸路径并随预排版提供，采用预排版后滚动中不再在主线程重新排版；无障碍元素改为按需构建；只有排版相关的 trait 变化才重新排版。模拟器业务图文列表基准中，滚动每步 p95 从约为系统 UILabel 的 2 倍降到约 0.5 倍，见 [P2 记录](docs/verification/2026-10-31-p2-scroll-performance.md)。公开 API 与尺寸结果不变。

### 说明

- 内置加载器 `LYGlyphTextURLSessionImageLoader` 定位为没有图片库时的兜底，功能冻结、只修缺陷；生产环境推荐通过 `LYGlyphTextImageLoading` 桥接 Kingfisher、SDWebImage 等宿主图片库。

### 修复

- Markdown 强调：`我*很*好` 等紧挨中文的斜体可以识别；没有斜体字形的字符（如苹方中文）改用合成倾斜，不再只去掉星号；标记内侧紧挨空白时保持原样（`a * b * c`）；行内代码内的星号与链接地址不再被当成强调改写。
- 字形绘制改用每段文字自带的文字矩阵，带变换矩阵的字体（例如合成倾斜字体）按矩阵绘制；普通字体的矩阵为单位矩阵，显示不变。
- 选区拖柄用 VoiceOver 调节后，布局变化通知把焦点留在该拖柄上，不再传 nil。

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
