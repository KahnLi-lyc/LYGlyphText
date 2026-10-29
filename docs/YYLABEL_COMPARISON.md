# LYGlyphText 与 YYLabel 能力对比

对照对象：YYText 的 YYLabel（仓库外参考源码，只研究不移植）与 LYGlyphText `1.0.0-beta.1` 之后的 main。LYGlyphText 一列已对照本仓源码核实；YYLabel 一列来自参考源码阅读，没有在本仓运行。

## 定位

LYGlyphText 只做只读 Label，服务三个核心场景：

1. **图文混排**：本地图片、网络图片、UIView 附件与文字同排；
2. **文字高亮可点击**：链接、@提及、#话题#、自定义范围的点击／长按与按下反馈；
3. **长按复制**：长按选择、拖柄调整、系统菜单拷贝。

不追求与 YYLabel 逐项对齐。下表“处理”一列：

- ✅ 已有：已交付并有自动测试；
- ✅ C*n*：在 [C 批次](superpowers/plans/2026-10-29-label-c-batch.md) 对应步骤补齐（见 [C 批次验证记录](verification/2026-10-29-c-batch.md)）；
- ⛔ 不做：不在核心场景内，理由见[不做清单](#不做清单)；
- 🔍 C6：由 C6 真机性能测量决定。

## 一、排版与显示

| 能力 | YYLabel | LYGlyphText | 处理 |
|---|---|---|---|
| 富文本输入 | `attributedText`，另有 `text`／`font`／`textColor` 便捷属性 | 只接受 `LYGlyphTextDocument`（由 NSAttributedString 或分段构造） | ✅ C2 `LYGlyphTextDocument(text:font:foregroundColor:)`；Label 不加便捷属性 |
| 行数限制、截断位置 | ✅ 头／中／尾 | ✅ `.head`／`.middle`／`.tail` | ✅ |
| 截断 token | ✅ 任意 NSAttributedString，可带图片和高亮 | ⚠️ 只能设文字、字体、颜色，可点击 | ✅ C3 `pieces` 支持多段文字与图片 |
| 垂直对齐、内边距 | ✅ | ✅ | ✅ |
| 单词／字符换行 | ✅ | ✅ | ✅ |
| 异形容器 `textContainerPath`、绕排 `exclusionPaths` | ✅ | ❌ | ⛔ |
| 竖排 `verticalForm` | ✅ | ❌ | ⛔ |
| 统一行位置修正 `linePositionModifier` | ✅ | ❌ 用段落最小／最大行高代替 | ⛔ |
| Auto Layout 自适应、`preferredMaxLayoutWidth` | ✅ | ✅ 有 UITableView／UICollectionView 自适应行高测试 | ✅ |
| Dynamic Type、暗黑模式语义色、RTL | 基本没有 | ✅ | ✅ LY 更强 |
| SwiftUI | ❌ | ✅ `LYGlyphTextView` | ✅ LY 更强 |

## 二、文本属性

| 能力 | YYLabel | LYGlyphText | 处理 |
|---|---|---|---|
| 系统标准属性（字体、颜色、字距、段落、下划线、删除线等） | ✅ | ✅ | ✅ |
| 阴影 | ✅ 可叠多层 subShadow，可设混合模式 | ⚠️ 单个 NSShadow | ✅ 单个阴影；多层 ⛔ |
| 内阴影 `YYTextInnerShadow` | ✅ | ❌ | ⛔ |
| 自定义线型（线宽、带阴影的下划线／删除线） | ✅ | ⚠️ 标准线型和虚线等样式，无线宽和线阴影 | ⛔ |
| 圆角背景／边框 `YYTextBorder` | ✅ 含虚线边框、边框阴影 | ✅ 填充、描边、圆角、外扩 | ✅ 常用部分；虚线边框和边框阴影 ⛔ |
| 整段块边框 `YYTextBlockBorder` | ✅ | ❌ | ⛔ |
| 字形变换 `GlyphTransform` | ✅ | ❌ | ⛔ |
| 文字描边 | ✅ | ✅ | ✅ |
| `YYTextBackedString`（拷贝时还原原文） | ✅ 通用 | ⚠️ 附件拷贝时输出 `alternativeText`，表情还原成 `[微笑]` 这类短码 | ✅ 复制场景够用；通用形式 ⛔ |

## 三、附件

| 能力 | YYLabel | LYGlyphText | 处理 |
|---|---|---|---|
| UIImage 附件 | ✅ 支持 contentMode 和 contentInsets | ⚠️ 本地图片拉伸填满声明尺寸；网络图片已支持 `contentMode` | ✅ C1 本地图片支持 `contentMode`；contentInsets 用“更大的声明尺寸 + `.center`／`.scaleAspectFit`”实现 |
| UIView 附件 | ✅ 直接放入视图实例 | ✅ 由工厂创建，可见时挂载、离屏时卸载，测量时不创建视图 | ✅ LY 生命周期更严谨 |
| CALayer 附件 | ✅ | ❌ | ⛔ |
| 对齐到字体 | ✅ 上／中／下 | ✅ 上／中／下 | ✅ |
| 网络图片 | ❌ 需宿主加载后替换 | ✅ 远程附件、加载协议、回报真实尺寸 | ✅ 见[网络图片与缓存](#网络图片与缓存) |

## 四、交互

| 能力 | YYLabel | LYGlyphText | 处理 |
|---|---|---|---|
| 区域点击／长按 | ✅ 闭包存在字符串里（`YYTextHighlight`） | ✅ 用 `actionID` 标记，统一回调 `onAction` | ✅ 写法不同 |
| 按下效果 | ✅ `highlight.attributes` 可换任意属性 | ⚠️ 前景色、背景色和圆角 | ✅ 点击高亮够用；任意属性 ⛔ |
| 按下渐隐 `fadeOnHighlight` | ✅ | ❌ | ⛔ |
| 整段点击 | ✅ `textTapAction` | ✅ `onTap` | ✅ |
| 整段长按 | ✅ `textLongPressAction` | ❌ 长按用于选择文字 | ⛔ |
| 点击截断 token 展开 | 需自己在 token 里加高亮 | ✅ 内置，事件带 `isTruncationToken` | ✅ LY 更方便 |
| 选择与拷贝 | ❌（只有 YYTextView） | ✅ 拖柄、iOS 17+ 放大镜、纯文本和富文本拷贝 | ✅ LY 更强 |
| 无障碍 | 很弱，基本把全文当一个标签 | ✅ 每个可点区域、附件、拖柄都是独立元素 | ✅ 人工 VoiceOver 未验收 |
| 文本解析器 | ✅ `YYTextParser`：表情、简易 Markdown | ✅ 链接、@提及、#话题#、正则、表情、简易 Markdown | ✅ |
| 调试叠加 | ✅ `debugOption` | ✅ `debugOptions`：行框、基线、附件框、可点区域 | ✅ |

## 五、性能与线程

| 能力 | YYLabel | LYGlyphText | 处理 |
|---|---|---|---|
| 异步绘制 `displaysAsynchronously` | ✅ | ❌ | 🔍 C6 |
| 预排版、提前算行高 | ✅ 后台生成 `YYTextLayout`，配合 `ignoreCommonProperties` | ✅ `LYGlyphTextPreparedLayout` 在后台排版 | ✅ |
| 在后台构建富文本 | ✅ 全流程可在后台线程 | ⚠️ 文档在主线程构建，排版可放后台 | ⛔ |
| 维护与并发安全 | 多年未维护 | Swift 6 严格并发 | ✅ |
| 最低系统 | iOS 6 | iOS 16 | — |

已有 Release 数据（[P1 记录](verification/2026-10-21-performance-readiness.md)，iOS 27 Simulator、320pt、20pt 字体、scale 3，p50，无附件）：

| 文本长度（UTF-16） | 文档构造 | 新 Label 首次排版 | 位图绘制 |
|---:|---:|---:|---:|
| 100 | 约 15µs | 约 1.6ms | 约 0.35ms |
| 1000 | 约 0.1ms | 约 11.4ms | 约 1.0ms |
| 5000 | 约 0.5ms | 约 59ms | 约 2.6ms |

首次排版最贵，已经可以用预排版移到后台；文档构造很便宜，放到后台收益很小；主线程上剩下的主要是绘制。是否需要异步绘制，按 C6 的门槛在真机上判定。模拟器数据不代表真机。

## 网络图片与缓存

网络图片分两层：公开的加载协议 `LYGlyphTextImageLoading`，以及只用系统框架的内置加载器 `LYGlyphTextURLSessionImageLoader`。

| | YYWebImage + YYImageCache | LYGlyphText 内置加载器 | LYGlyphText + 宿主图片库 |
|---|---|---|---|
| 缓存 | 内存和磁盘两级，按 LRU 和过期时间淘汰，不看缓存头 | NSCache 内存缓存；专用 URLCache 磁盘缓存，遵循 HTTP 缓存头 | 由 Kingfisher／SDWebImage 提供 |
| 格式与动图 | WebP、APNG；按需解码帧，省内存 | 解码交给 ImageIO；多帧动图只读取 GIF 帧时长，最多 300 帧一次全部解码进内存 | 由图片库提供 |
| 维护 | 多年未维护 | 功能冻结，只修缺陷 | 活跃维护 |
| 依赖 | YYKit 系列 | 无 | 宿主自有，组件不依赖 |

结论：

- 内置加载器是**兜底**，用于没有图片库的宿主和 Demo；功能冻结，不再增强缓存、格式或动图。
- 生产环境推荐用加载协议桥接已有的图片库，例如 Kingfisher 或 SDWebImage。桥接只需一个实现协议的小类；Kingfisher 版本见 Demo 中已编译的 [KingfisherImageLoader.swift](../Examples/LYGlyphTextDemo/LYGlyphTextDemo/KingfisherImageLoader.swift)，组件本身不依赖它。
- 与 YYWebImage 比较时，对象应是桥接后的图片库，而不是内置加载器。

## 不做清单

以下能力都不会自动排进后续批次。只有出现具体需求（设计稿要求或线上问题）时，才单独提出来评估，不会为了追平 YYLabel 成批去做。

| 能力 | 理由／替代做法 |
|---|---|
| Label 上的 `text`／`font`／`textColor` 便捷属性 | C2 的一行构造文档已经够用；Label 只保留 `document` 一个输入，避免两套状态 |
| 异形容器、绕排、竖排 | 与图文混排、点击、复制三个场景无关 |
| `linePositionModifier` | 图文混排要固定行高时，用段落的最小／最大行高，并让图片高度不超过行高 |
| 多层阴影、内阴影、线宽／线阴影、虚线边框／边框阴影、整段块边框、字形变换 | 装饰特效，不在核心场景内 |
| `YYTextBackedString` 的通用形式 | 复制场景已由附件 `alternativeText` 满足；链接、@、话题本身就是原文 |
| CALayer 附件 | UIView 附件已覆盖 |
| 按下效果换任意属性、`fadeOnHighlight` | 点击高亮只需要变色、背景和圆角；设计确实要求按下加下划线或渐隐时再单独评估 |
| 整段长按 | 长按已用于选择复制，两者冲突 |
| 在后台构建文档 | 文档构造本身很便宜（见上方数据）；MainActor 文档是 Swift 6 并发设计的一部分，改动收益不抵成本 |
| 自研图片缓存增强（LRU、WebP／APNG 动图、按需解码帧） | 桥接 Kingfisher／SDWebImage 即可获得，组件保持零第三方依赖 |

异步绘制不在此表：由 C6 真机测量决定，达到门槛才排期，否则移入本表并附上数据。

## 发布前仍需补的验证

能力对比不代表发布资格。`1.0.0` 之前仍需补齐 Swift 6.0 编译器、iOS 16 运行、真机、人工 VoiceOver 等门槛，详见[发布准备](RELEASE_READINESS.md)。
