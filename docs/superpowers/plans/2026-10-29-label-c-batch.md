# LYGlyphText C 批次：核心场景收口

> **For agentic workers:** 沿用[连续开发契约](2026-10-20-continuous-development.md)与 [CONTRIBUTING](../../../CONTRIBUTING.md)；模拟器测试串行。

**起点：** main `f663c01`，`1.0.0-beta.1` 之后。范围约束不变：只做 Label、Core Text 唯一内核、零第三方运行依赖、iOS 16+、Swift 6，公开 API 只增加。

**背景：** 组件只服务图文混排、文字高亮可点击、长按复制三个场景。对照 YYLabel 后，只补这三个场景内的小缺口，其余差距按[能力对比](../../YYLABEL_COMPARISON.md)的不做清单处理，不成批追平。

| 编号 | 内容 | 接口与行为契约 | 关键验收 |
|---|---|---|---|
| C0 契约 | 能力对比文档、本文件与总计划登记 | 只改文档 | docs 检查 |
| C1 本地图片 contentMode | `LYGlyphTextAttachment` 新增 `contentMode: UIView.ContentMode`，默认 `.scaleToFill`（保持现有拉伸行为）。绘制矩形语义与 UIImageView 一致：`.scaleToFill`、`.scaleAspectFit`、`.scaleAspectFill`、`.center` 与 top／left／bottom／right 及四角对齐；`.redraw` 按 `.scaleToFill`。超出声明框的部分按声明框裁切。排版尺寸、动作、选择与无障碍几何不变 | 非正方形图片画进正方形框：fit 留白、fill 裁切、center 居中、默认拉伸；声明框外无像素 |
| C2 便捷构造文档 | `LYGlyphTextDocument.init(text:font:foregroundColor:) throws`：只在文本含 U+FFFC 时抛 `unsupportedObjectReplacementCharacter`，与其他入口一致，不静默替换字符。nil 沿用现有默认（动态 body 字体、label 颜色）；显式字体保持固定 | 与等价 NSAttributedString 构造的文档排版尺寸、样式快照一致；nil 字体／颜色快照为 nil（动态 body 由既有环境测试覆盖）；U+FFFC 报错位置 |
| C3 富文本截断 token | `LYGlyphTextTruncationToken.Piece`：`.text(String, font:, foregroundColor:)` 与 `.image(UIImage, size:, alignment:)`；新增 `pieces` 与 `init(pieces:actionID:...)`。`pieces` 非空时取代 `text`／`font`／`foregroundColor`；文字片段 nil 字体／颜色像现在一样继承最后一条可见行起点；图片片段按声明尺寸参与宽度计算并相对 token 字体对齐，不随按下状态变色。整个 token 仍是一个点击区域；无障碍朗读文字片段的拼接，图片只是装饰。保持 `Equatable`／`Sendable` | 尾部／头部／中间截断下混合颜色与“文字 + 图标”的位置和像素；宽度不足时整体省略；点击图标触发 `isTruncationToken`；RTL；旧 API 结果不变；无障碍标签 |
| C4 Kingfisher 桥接与加载器冻结 | Demo 工程（只有 Demo App target）以确切版本引入 Kingfisher，桥接实现放在 Demo 源码并在 Swift 6 模式编译；网络图片演示可切换内置加载器／Kingfisher。README 与内置加载器文档注释写明：内置加载器是兜底、功能冻结，生产推荐桥接图片库。组件 Package 不变 | Package 依赖为零；Demo 构建通过；模拟器中两种加载器都能显示图片 |
| C5 Demo、回归与记录 | 演示页展示 C1 与 C3；CHANGELOG“未发布”登记 C1—C4；验证记录 | format、build、完整 test；截图检查 |
| C6 真机性能测量 | Release 构建在真机上运行 180 行固定负载列表与业务风格图文列表（每行 100—300 字、3—5 个表情或网络图片、开启预排版），Instruments Animation Hitches 记录匀速与快速滑动；设备上运行 `PerformanceMeasurementTests` 与 P1 对比 | 门槛：任一场景卡顿时间比 ≥ 5ms/s，且 Time Profiler 显示卡顿帧主要耗时在 LYGlyphText 绘制 → 新开异步绘制批次；否则在能力对比中把异步绘制移入不做清单并附数据。无真机时记为未验证，不阻塞 C0—C5 |

**决定（2026-10-29，用户确认）：**

- 内置加载器保留现有内存与磁盘缓存，功能冻结；不删除、不增强。组件不依赖 Kingfisher，Kingfisher 只进入 Demo 工程。
- C 批次之外与 YYLabel 的差距全部按不做清单处理；只有具体需求出现时单项评估。
- 异步绘制由 C6 真机数据决定，不预先实现。
