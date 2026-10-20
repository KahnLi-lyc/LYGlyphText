# 行内图片附件验证

日期：2026-10-20。基于 `e8318ac` 实现；本记录随图片附件功能提交。默认仅合入本地 main，不推送，不创建 Tag 或 Release。

## 接口与行为

- 新增 MainActor 的不可变 `LYGlyphTextAttachment`，包含 id、UIImage、明确的 point 尺寸、top／center／bottom 对齐和可选 alternativeText；默认 bottom。
- 文档入口增加默认空的 `[Int: LYGlyphTextAttachment]` 字典。位置使用原文 UTF-16，必须对应独立 U+FFFC；拒绝缺失描述、错误位置、重复 ID、非有限／非正尺寸和标准 NSTextAttachment。
- 保留文本／样式快照隔离和既有调用。图片尺寸不从像素分辨率推导，图片填满声明矩形；超宽图片不可拆分、不自动缩小，越界部分裁切。
- Core Text delegate 仅持有纯数值度量，retain／release 配对；ascent／descent 同时覆盖占位字体区域和图片。小图片独占一行时仍保留字体区域。
- 最终附件几何来自可见 runs，保存原文位置并处理截断行 sourceOffset；隐藏附件不绘制、不贡献最终行高。生成省略号只继承字体、颜色和段落信息。
- UIKit／SwiftUI 共用布局，保留每 Label 两份缓存；测量不改 frame、约束或子视图，文档替换不重置宿主优先级。图片方向由 UIImage 绘制处理，绘制同时受内容区域和外框裁切。
- 两端共用本地生成的非对称箭头图：正常图朝上且橙色标记在左上；`.right` 方向图朝右且标记在右上。没有外部图片或网络依赖。

## 环境与验收范围

| 项目 | 本轮环境 |
|---|---|
| Xcode | 27.1（27A9275） |
| 编译器／语言模式 | Apple Swift 6.4／Swift 6 language mode |
| XcodeGen／SwiftFormat | 2.46.0／0.59.1 |
| Simulator | 独立 LYGlyphText Images Handoff，iPhone 17 Pro，arm64 |
| 运行系统 | iOS 27.0（24A434） |

| 场景 | 证据 |
|---|---|
| 输入、UTF-16、快照、默认值、所有尺寸分量 | AttachmentTests；保留 DocumentTests 回归 |
| 三种对齐、混合字号、小／高／宽图片、连续及行首／行尾图片 | AttachmentTests；几何与声明尺寸断言 |
| 中文、emoji、基本 RTL、软换行后的 RTL 截断 | AttachmentTests；原文位置、run 顺序、前行基线及末行高度 |
| 保留／移除图片、仅 token／无法容纳 token、相邻省略号 | AttachmentTests；可见范围、最终高度和 token 属性 |
| 内边距、零／有限／无限宽度、离屏测量、替换／清空、缓存宽度往返、优先级 | AttachmentTests、既有布局测试 |
| Auto Layout／SwiftUI 宽度和行数矩阵 | AttachmentTests；相同输入高度差不超过一个物理像素 |
| 默认字体随内容大小类别更新图片对齐 | AttachmentTests；显式字体回归保留 |
| 全部 8 种 UIImage 方向，图片 scale 不改变声明尺寸 | AttachmentDrawingTests；对照 UIKit 图片绘制的内部色块主色 |
| 超宽图、高度压缩、内边距、非零 bounds 原点 | AttachmentDrawingTests；在真实父子 layer 变换下检查裁切外像素为空白 |
| 同文档两个 Label 独立绘制／清空 | AttachmentDrawingTests；像素和子视图数量检查 |
| delegate 上下文释放 | AttachmentTests；weak 引用及 autoreleasepool |
| 两端真实控制操作 | DemoUITests；保留原用例并增加图片、三种对齐、宽度及行数切换 |

## 过程与失败记录

- 接手前的 `image-attachments-red.log` 是新公开类型缺失导致的编译失败，`image-attachments-first.log` 是测试中 infinity 类型歧义的编译失败，均不算运行通过。
- `image-attachments-second.log` 执行 13 项，其中 11 项通过；两项因测试中手写 UTF-16 位置错误失败，核对原文后分别修正为 5 和 8。
- `images-handoff-red.log` 在接手后执行 18 项，新增小图片独占行测试实际复现两种对齐下字体 descent 丢失；现改为图片和字体联合度量。
- 第一版绘制测试逐像素比较设备 scale 的 layer 图与 scale 1 参考图，在色块边缘产生插值差异。现比较色块内部主色并要求覆盖全部三种主色，保留全部 8 种方向验收。非零 bounds 通过父视图渲染包含 bounds→frame 变换，避免直接渲染子 layer 本地坐标造成假偏移。
- `images-drawing-colors.xcresult` 的 3 项图片绘制测试全部通过；`images-handoff-targeted2.log` 中 18 项附件行为测试通过，绘制测试当时仍因上述插值差异失败，不能作为整轮通过。
- 第一轮完整回归的离屏 Auto Layout 测试，在行数变化但父容器宽度相同时未请求父容器布局；按已有 TruncationTests 的宿主方式补充 setNeedsLayout 后复验。
- 失败运行自动收集模拟器诊断耗时较长；保留测试失败日志，并终止该失败轮次所属的诊断子进程。定向调试使用 `-collect-test-diagnostics never`，正式入口保持仓库脚本不变。
- 固定格式工具下载因网络不可达失败后，使用本机已有的 SwiftFormat 0.59.1，并通过脚本核对版本；未改变工具版本或全局网络配置。
- 规格审查与代码质量审查均未发现阻止合入的实现问题；运行和截图验收独立记录。

## 最终结果与证据

```sh
scripts/verify.sh docs
scripts/verify.sh format
scripts/verify.sh build
scripts/verify.sh test 5260ADE6-ADC2-44AA-9EEB-CDEC90196D08
```

- docs 和 SwiftFormat 0.59.1 检查通过，22 个 Swift 文件无需改写。format 使用 LYGLYPHTEXT_SWIFTFORMAT 指向本机已安装的固定版本工具。
- `.build/verification/20261020T065655Z-3043-build/`：Package 与 Demo 的 Swift 6 模式 Simulator 构建通过，保留 environment.json 和构建日志。
- `.build/verification/20261020T070151Z-6892-test/`：**72／72 Passed，0 failed，0 skipped**。包括 68 项宿主测试（20 项附件行为、3 项图片绘制及既有回归／Demo 测试）和 4 项真实 UI 测试；保留 tests.log、test-summary.json、environment.json 和 Tests.xcresult。
- 最终运行中，UIKit／SwiftUI 相同输入、宽度和 0／1／2 行限制的高度差不超过一个物理像素；宽度往返与自动撑高通过。
- 截图从最终成功的 xcresult 导出到 `.build/verification/images-final-attachments/`，manifest.json 保留测试名与附件文件的对应关系；以下 12 张图片原样复制入仓库，未裁剪或修饰。
- 第一轮完整回归保留在 `.build/verification/20261020T065754Z-3728-test/`：68 项宿主测试中 1 项失败（2 个断言）、4 项 UI 测试通过，整轮失败。停止诊断子进程后 Xcode 结果导入另报 resourceChanged，不能将该轮作为成功或替代最终结果。

## 最终截图检查

| 场景 | UIKit | SwiftUI |
|---|---|---|
| 顶部，160，无限行 | [截图](images/image-attachments-uikit-160-top-unlimited.png) | [截图](images/image-attachments-swiftui-160-top-unlimited.png) |
| 居中，240，无限行 | [截图](images/image-attachments-uikit-240-center-unlimited.png) | [截图](images/image-attachments-swiftui-240-center-unlimited.png) |
| 底部，320，无限行 | [截图](images/image-attachments-uikit-320-bottom-unlimited.png) | [截图](images/image-attachments-swiftui-320-bottom-unlimited.png) |
| 底部，160，单行截断 | [截图](images/image-attachments-uikit-160-bottom-one-line.png) | [截图](images/image-attachments-swiftui-160-bottom-one-line.png) |
| 底部，240，两行截断 | [截图](images/image-attachments-uikit-240-bottom-two-lines.png) | [截图](images/image-attachments-swiftui-240-bottom-two-lines.png) |
| 混合字号，320，居中三行 | [截图](images/image-attachments-uikit-mixed-320-center-three-lines.png) | [截图](images/image-attachments-swiftui-mixed-320-center-three-lines.png) |

逐张检查上述 12 张截图：两端的图片方向、色块位置、三种字体区域对齐、换行和截断一致。160 单行时上向图片保留，右向图片被省略且没有残影；240 两行时两图保留；混合字号样例保留字体／颜色与最终省略号。截图只证明这些 fixture，Unicode／RTL、全部 UIImage 方向及边界结论由专项测试提供证据。

## 未验证与边界

- Swift 6.0 编译器兼容未验证：本轮实际编译器为 Swift 6.4。
- iOS 16 实际运行未验证：本机可用 runtime 不含 iOS 16，部署目标不替代运行证据。
- alternativeText 只保留描述数据，完整 VoiceOver 行内语义仍未验收。
- UIView 工厂／挂载复用／生命周期、点击、长按、高亮、完整列表与国际化交互、真实设备及性能仍属后续范围。
