# S1—S5 剩余功能验证记录

日期：2026-10-29。分支 `codex/s-batch`，起点 main `5f6f1a7`（S0 契约）。契约见 [S 批次](../superpowers/plans/2026-10-29-label-s-batch.md)。设备为本仓专用模拟器 `5260ADE6-ADC2-44AA-9EEB-CDEC90196D08`；运行期间机器上其他任务的模拟器使 load average 维持在 160—350。

## 交付内容

| 编号 | 交付 | 行为证据 |
|---|---|---|
| S1 | 选区拖柄成为可调节无障碍元素：名称取 `selectionStartAccessibilityName`／`selectionEndAccessibilityName`，值为选区文字，increment／decrement 按一个组合字符伸缩对应一端并至少保留一个字符；identifier 为 `LYGlyphText.selectionStart`／`End`，只在有选区时进入无障碍树 | `SelectionHandleAccessibilityTests` 2 项（无障碍树顺序、值、命名、家庭 emoji 组合字符边界、交叉保护）；`FeatureUITests.testDraggingEndHandleExtendsSelection` 按 identifier 拖动结束拖柄使选区变长并截图 |
| S2 | `LYGlyphTextURLSessionImageLoader` 新增 `diskCacheCapacity`（默认 50MB，0 关闭）与 `diskCacheDirectory`，使用专用 `URLCache`，缺失目录自动创建；`removeAllCachedImages()` 清空内存与磁盘 | `ImageDiskCacheTests` 2 项：回环地址上的真实 HTTP 服务器返回 `Cache-Control: max-age=3600`，清空内存缓存后再次加载不再到达服务器；清理后重新请求；容量 0 时每次都请求且不写 `URLCache.shared` |
| S3 | `.markdownEmphasis()`（粗体、斜体、行内代码）与 `.markdownLinks(attributes:pressedStyle:)`（`[文字](url)` → 文字＋URL 动作） | `ParserMarkdownTests` 4 项：原文映射与动作范围、组合字符、与表情／@ 规则共存、不配对标记和空链接文字保留；`FeatureUITests.testMarkdownLinkTapReportsURLAction` 点击“查看文档”收到 URL 动作 |
| S4 | `LYGlyphTextDebugOptions`（行框、基线、附件框、动作区域）；Label 与 SwiftUI `debugOptions` 默认空 | `DebugOverlayTests` 3 项：空选项像素与普通绘制完全一致；各选项在对应几何处出现对应颜色；修改选项不重建布局 |
| S5 | 2.x 演示页增加胶囊背景、截断模式切换、Markdown、调试叠加开关、远程图片真实尺寸回调；页面改为可滚动 | `FeatureUITests` 共 6 项：新增截断模式切换（尾部截断时无障碍树中没有“全文结束”，切到头部／中间后出现，切回后消失）、Markdown 链接与调试叠加截图；原有远程图片断言在按真实尺寸重建后仍为“已加载 1 张” |

## 失败与修复

第一次定向运行（`.build/verification/s-targeted/`）76 项中 70 项通过（单测 5 项、UI 1 项失败）：

- `DebugOverlayTests.testEachOptionDrawsItsGeometry`：1pt 描线落在小数坐标，被抗锯齿到相邻两行，单像素取色过淡。测试改为取 y±1 范围内目标颜色最强的像素；实现不变。
- `ImageDiskCacheTests`：日志显示 `NetworkStorageDB … unable to open database file`，`URLCache(directory:)` 不会创建缺失目录。加载器现在先创建目录。另外，`URLSession` 不会把 `cachedResponse` 交给自定义 `URLProtocol`，所以桩协议无法证明磁盘命中；测试改用 Network.framework 在 127.0.0.1 上启动的最小 HTTP 服务器，由系统 HTTP 协议栈按缓存头判断。
- `testDraggingEndHandleExtendsSelection`：失败截图显示编辑菜单出现在选区下方，盖住了结束拖柄的圆点，拖动从拖柄中心开始时落在菜单上。测试改为从文字行内的竖线部分开始拖动。真实用户同样可能遇到菜单遮挡拖柄圆点，此时可拖动竖线部分；本批次不调整菜单位置。

修复后定向重跑（`s-targeted-02/`、`s-targeted-03/`）全部通过。

## 正式检查

| 检查 | 结果 |
|---|---|
| 固定 SwiftFormat 0.59.1／docs | PASS |
| build（Package 与 Demo，Swift 6 模式） | PASS（`20261028T182133Z-75341-build`） |
| 完整宿主＋UI 回归 | **456／456 Passed**（426 宿主＋30 UI），0 失败／跳过，`runtimeWarnings=[]`（`20261028T182202Z-75728-test`）；原有 442 项全部保留 |

## 未验证

iOS 16 实际运行、Swift 6.0 编译器、真机、人工 VoiceOver 调节拖柄的手感、公网图片服务器的缓存头差异、Kingfisher 桥接编译、Allocations／Leaks。RocketSim 探索式验证见 S6 记录。
