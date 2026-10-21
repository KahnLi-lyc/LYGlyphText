# G3 网络图片验证记录

日期：2026-10-21。基于 G2，分支 `codex/g3-remote-images`。执行契约见 [2.x Label 路线图](../superpowers/plans/2026-10-21-label-roadmap.md) G3。

## 交付的公开接口

| 接口 | 行为 |
|---|---|
| `LYGlyphTextRemoteImageAttachment` | MainActor 不可变描述：id、url、声明尺寸、对齐、contentMode（默认 scaleAspectFill 并裁切）、placeholder、failureImage、alternativeText。与图片、视图附件共用 U+FFFC 位置、唯一 ID、尺寸与位置冲突校验。 |
| `LYGlyphTextDocument(... remoteImages:)`、`LYGlyphTextSegment.remoteImage` | 远程图片在内部转为不可交互的视图附件参与排版与可见性计算；宿主工厂不会收到这些描述。新增枚举 case 对穷举 switch 的宿主代码是源码变化，1.0 尚未发布，已记录于 CHANGELOG。 |
| `LYGlyphTextImageLoading`／`LYGlyphTextImageLoadingTask` | MainActor 协议，completion 在 MainActor 至多调用一次，可在返回任务前同步调用；取消后不得回调。可桥接 Kingfisher 等宿主图片库。 |
| `LYGlyphTextURLSessionImageLoader` | 只用 URLSession、NSCache、ImageIO：同 URL 同目标像素尺寸的请求合并，内存缓存命中同步回调，按目标尺寸降采样并应用方向，多帧 GIF 生成动画图片（默认最多 300 帧，过短延时按 0.1 秒）。无磁盘缓存；非 2xx 状态与无法解码分别报错。没有全局共享实例，由宿主创建并共享。 |
| `LYGlyphTextLabel.imageLoader`、`LYGlyphTextView(imageLoader:)` | 默认 nil 时只显示占位图。更换加载器卸载全部附件并重新请求；SwiftUI 拆卸释放加载器。 |

## 生命周期

- 测量（sizeThatFits、intrinsicContentSize、fitting）不创建视图、不发请求。
- 附件进入最终可见区域并挂载后才请求；离屏、移出 window、替换文档、reload 或更换加载器时取消，迟到回调被忽略。
- 加载结果不改变排版尺寸；需要按图片真实宽高排版时，宿主用获得的尺寸重建文档。路线图中的 `.fitWidth` 自动改尺寸本阶段不交付：它会让测量结果依赖异步状态，与“测量稳定、不反算”的现有契约冲突。

## Kingfisher 桥接示例

见 README“网络图片”一节；组件 Package 不依赖 Kingfisher。

## 行为证据

新增 `Tests/LYGlyphTextTests/RemoteImageTests.swift`（11 项），网络部分只用本地 URLProtocol 桩与模拟加载器，不访问外网：

- 文档：远程图片与图片附件重复 ID、位置不是 U+FFFC、与视图附件同位置、非法尺寸分别报错；内部视图描述为不可交互。
- Label：sizeThatFits／intrinsicContentSize 零请求；挂载后请求一次，参数为声明尺寸与窗口 scale；重复布局不重复请求；成功与失败（failureImage）结果；移出 window、替换文档、更换加载器均取消，迟到回调不改变已卸载视图；同步缓存结果立即显示；无加载器显示占位图；宿主工厂只收到宿主视图描述；AX 使用替代文本；SwiftUI 传递加载器、拆卸释放。
- 内置加载器：同 URL 同尺寸两次请求只发 1 次网络请求且返回同一图片，降采样到 20pt×scale 2；再次请求命中缓存并同步回调；全部等待者取消后不回调、进行中请求为 0；404 与无法解码分别报错；3 帧 GIF 解码为 3 帧动画、时长 0.15 秒，帧数上限生效。
- 既有 `SegmentTests` 的穷举 switch 补充了 `.remoteImage` 分支（新增 case 的源码影响，见 CHANGELOG）。

## 正式检查

| 检查 | 结果 |
|---|---|
| 固定 SwiftFormat 0.59.1 | 99 个 Swift 文件 0 需格式化 |
| `scripts/verify.sh docs`／`build` | PASS |
| 第一次完整回归 | 396 通过、1 失败：既有 UI 用例 `testUIKitImageAlignmentWidthsAndTruncation` 在点“1 行”后等待 App 空闲约 380 秒超时；同时段另一台模拟器在做 Release 编译与计时，机器负载很高（load average 曾超过 59）。该页面只用 UIImage 附件，G3 未改动其代码路径。 |
| 单独重跑该用例 | 无并行负载时 54 秒通过 |
| 无并行负载的完整回归 | **397／397 Passed（373 宿主＋24 UI）**，0 失败／跳过／预期失败，`runtimeWarnings=[]` |

G2 的 386 个测试方法全部保留，新增 11 项。证据保存在主 checkout 的 `.build/verification/g3/`（含失败的第一次运行）。按路线图自查规格与质量；路线图中的 `.fitWidth` 自动改尺寸未交付，原因见上文。Swift 6.0 编译器、iOS 16 运行与真实网络仍未验证。
