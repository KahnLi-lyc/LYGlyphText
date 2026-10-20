# 基础富文本显示与自动撑高验证

日期：2026-10-20。本轮完成最小显示闭环，没有发布版本或推送远端。

## 交付与接口

- Package：Swift tools 6.0、Swift language mode v6、iOS 16 部署目标、单一 library、零第三方依赖。
- Document：MainActor 不可变文本与样式值快照，只提供 `init(attributedText:) throws`。标准 attachment 和 U+FFFC 输入明确失败。
- Core Text：字体、前景色、段落对齐／基本方向、多行单词换行与显式换行、UTF-16 行范围、UIKit 坐标基线；测量和绘制共用布局，每 Label 最多两个缓存。
- UIKit：内边距、固有尺寸、preferredMaxLayoutWidth、sizeThatFits、required 横向宽度的 systemLayoutSizeFitting、宽度变化后重新撑高、保留宿主 CHCR、受限高度裁切。
- SwiftUI：UIViewRepresentable 创建／更新／测量／拆卸，提议宽度独立于旧 bounds，替换／清空文档不残留。
- Demo：UIKit／SwiftUI 共用样例，切换短文／多行／混合样式及 160／240／320 point 宽度；UIKit 另有按钮并排和优先级切换。
- 工具：build／test 扩展保留日志和 xcresult，拒绝零测试、全跳过、失败结果和错误工具版本；生成的工程不入库。

## 环境与命令

| 项目 | 实际使用 |
|---|---|
| Xcode | 27.1，27A9275 |
| 编译器 | Apple Swift 6.4，swiftlang-6.4.0.34.1 |
| 语言模式 | Swift 6 |
| XcodeGen | 2.46.0 |
| SwiftFormat | 0.59.1 |
| Simulator | 本任务独立 LYGlyphText Validation，iPhone 17 Pro，arm64 |
| 运行系统 | iOS 27.0，24A434 |

执行命令（设备参数按实际环境填写）：

```sh
scripts/verify.sh build
scripts/verify.sh test <UDID>
scripts/verify.sh docs
scripts/verify.sh format
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/tests -v
```

本地忽略目录内保留本轮证据，不提交构建产物：

- `.build/verification/20261020T050149Z-55885-build/`：最终 Package／Demo generic Simulator 构建成功，分别保存日志和环境。
- `.build/verification/20261020T050041Z-55495-test/`：最终宿主与 UI 测试 **26／26 Passed，0 failed，0 skipped**；包含 tests.log、environment.json、test-summary.json、Tests.xcresult 和截图导出清单。
- 工具回归：**21 项通过**；docs 和固定版本格式检查通过。

Package 测试定义保留在根 Tests 中，并作为源码加入 Demo 单测宿主执行一次；没有以 macOS swift test 代替 iOS 测试。最终构建同时覆盖 Simulator 的 arm64／x86_64 编译；运行证据仅为上述 arm64 设备。

## 行为验收

| 验收内容 | 证据与结果 |
|---|---|
| 可变字符串与段落隔离 | DocumentTests；修改原字符串／paragraph 后文字及右对齐几何保持原值 |
| 明确拒绝附件 | DocumentTests；attachment 属性与 emoji 后的 U+FFFC 返回对应 UTF-16 错误 |
| 字体／颜色／中文／emoji | DocumentTests、LayoutTests；样式保留、UTF-16 范围连续安全、实际彩色像素存在 |
| 显式换行／空白 | LayoutTests；保留末尾空行、纯换行行高、纯空格 advance |
| 宽度与内边距 | LayoutTests；0／有限／无限宽度尺寸有限，inset 不重复计入，不依赖旧高度 |
| 测量无副作用 | LayoutTests；sizeThatFits 前后 frame／constraints 相同 |
| 约束自动撑高 | AutoLayoutTests；左右、固定、宽度上限、preferredMaxLayoutWidth 与 required 宽度离屏测量 |
| CHCR 与收敛 | AutoLayoutTests；按钮保持自然宽度／文本优先压缩、低 Hugging 拉伸、文档更新保留优先级、0→正值／窄宽窄／长短替换 |
| UIKit／SwiftUI 尺寸 | AutoLayoutTests；90／210／300 point 同输入高度差不超过一个物理像素；理想／零宽与替换／nil 更新 |
| 默认字体环境 | AutoLayoutTests；默认 body 随大字号类别变高，显式 UIFont 保持固定 |
| 高度裁切 | LayoutTests 像素检查；受限区域外无文字像素，不缩小字体 |
| 实际页面操作 | 2 项 UI tests；分别进入 UIKit／SwiftUI，多行160→混合320→短文240，断言状态与截图 |

## 截图核对

以下来自最终 UI 测试，系统与设备见上表。已人工核对文字方向、换行、彩色字体、内边距和内容边界。两端多行160及混合320的文字与行高一致；截图只证明这组样例，不替代完整视觉矩阵。

| UIKit | SwiftUI |
|---|---|
| [多行160](images/uikit-multiline-160.png) | [多行160](images/swiftui-multiline-160.png) |
| [混合样式320](images/uikit-mixed-320.png) | [混合样式320](images/swiftui-mixed-320.png) |

另用 RocketSim 实际切换“压缩按钮”，核对按钮缩短而富文本获得更大宽度、行高随之减少，见 [优先级演示截图](images/uikit-button-compressed.png)。

## 本轮发现与修正

- 首次运行因当前 SDK 要求 UIScene 生命周期而无法启动 Demo。改为 SceneDelegate 和自动生成 Scene Manifest 后，真实启动与 UI 测试通过。
- 初版复制段落对象仍未隔离可变输入，测试复现右对齐及对象身份失败。改为提取支持的样式值，再构建不可变 CTParagraphStyle；以实际布局验证原输入修改不再影响文档。
- 初版将零理想宽度视为空内容，纯换行和空白高度为 0。先新增失败测试，再按显式行 advance 计算理想宽度，并为纯换行保留测量路径；回归通过。
- 初始失败／中断日志仍在 `.build/verification/20261020T045603Z-53973-test/`、`20261020T045817Z-54821-test/` 与 `snapshot-newlines-red.log`，没有将失败运行覆盖成成功。
- 独立规格与代码审查已复核上述修正，未发现本轮范围内的阻断问题。

## 未验证与后续边界

- **Swift 6.0 编译器兼容未验证**：本机实际编译器为 Swift 6.4，tools-version 和 v6 语言模式不等同于 Swift 6.0 工具链验证。
- **iOS 16 实际运行未验证**：本机没有该 runtime，部署目标不替代最低系统运行证据。
- 未运行真实设备、完整 Dynamic Type／RTL／VoiceOver、全部 StackView／列表／旋转分屏矩阵，也未做性能基线。
- 图片／UIView 附件、点击／长按／高亮、行数限制／截断、装饰样式尚未实现；总计划对应任务保持待办。
- 未创建 Tag 或 Release，不具备宣称完整首版发布验收通过的条件。
