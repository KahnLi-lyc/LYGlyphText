# M1a 分段与动作描述验证

日期：2026-10-20。基于 UIView 附件提交 `70e8340`；M1a 提交 `b74a0cb` 已按独占集成锁快进合入 main 并普通推送，远端 SHA 已核对一致，临时分支已安全删除。本阶段交付安全输入和数据描述，不包含文字点击、长按或高亮；后续为 M1b 样式与几何，再进入 I1。

## 实际接口与行为

- MainActor 不可变 `LYGlyphTextPressedStyle`、`LYGlyphTextAction` 和 `LYGlyphTextSegment`；颜色保持语义值，默认按下背景为 tertiarySystemFill。
- Document 的 attributedText 入口追加默认空 actions，已有两类附件入口兼容；新增 `init(segments:)`，使用拼接器 UTF-16 length 自动建立图片／视图占位和独立动作。
- 快照发生于 Document 初始化。图片／视图属性不继承相邻文字；调用方后续修改原字符串或段落样式不影响文档。
- 动作先按输入顺序校验 ID、数值、组合字符边界，再稳定排序副本检查半开区间重叠。保存输入顺序，允许相邻范围与重复 ID；不 trim 或修改 ID 大小写。
- 数值判断先于范围末端加法；NSNotFound、负数、零长度、越界和 Int.max 输入安全报错。使用 Swift Character 边界和系统范围转换，拒绝拆开 emoji、重音与 CRLF；普通文字样式仍可拆分组合字符。
- Swift 6 实测 enum case 的默认值不继承 MainActor，且 case 不能标记全局 actor。三个 case 保留显式 pressedStyle，提供同名 MainActor static 便利重载；默认和显式调用、switch 模式均由宿主编译验证，没有并发逃生标记。
- 共用图片 Demo 改用 segments，原文和位置 2／6、声明尺寸及方向保持一致；UIView 示例保持原入口。不新增假交互。

## 失败与针对性证据

日志和 xcresult 位于忽略的 `.build/verification/`：

| 路径 | 真实结果 |
|---|---|
| `m1a-api-red` | 旧实现缺少公开 API，编译失败；不是运行通过 |
| `m1a-validation-red`／`m1a-case-actor-probe` | MainActor enum case 默认表达式／case actor 编译失败，确定便利重载方案 |
| `m1a-validation-red-run` | 22 项测试产生 37 个预期失败断言，复现动作与构建逻辑缺口 |
| `m1a-cluster-diagnostic` | 1 项测试产生 2 个 CRLF 边界失败断言；仅 NSString composed 检查不足 |
| `m1a-targeted-pass` | 77／77 Passed，0 failed／0 skipped；涵盖动作、分段、原文档、两类附件及 DemoHost |
| `m1a-contract-regressions` | 25／25 Passed，0 failed／0 skipped；补充不继承前文样式及字符内部样式分段回归 |

没有删除原有回归或弱化断言使失败消失。规格与独立代码质量审查均通过。

## 正式检查

环境：Xcode 27.1（27A9275）、Apple Swift 6.4／Swift 6 language mode、XcodeGen 2.46.0、SwiftFormat 0.59.1。独占设备为 LYGlyphText Images Handoff，iPhone 17 Pro arm64，iOS 27.0（24A434），UDID `5260ADE6-ADC2-44AA-9EEB-CDEC90196D08`。

```sh
scripts/verify.sh docs
scripts/verify.sh format
swift package dump-package
scripts/verify.sh build
scripts/verify.sh test 5260ADE6-ADC2-44AA-9EEB-CDEC90196D08
```

- 固定版本 format：32 个 Swift 文件，0 个需格式化；指定本机已有工具，没有安装或升级。
- Package 清单解析通过，Swift tools 6.0、iOS 16 部署目标与零第三方依赖保持。
- `.build/verification/20261020T082640Z-53235-build/`：Package 和 Demo 的 Swift 6 模式构建通过，保存环境和两份构建日志。
- `.build/verification/20261020T082700Z-53804-test/`：**127／127 Passed，0 failed／0 skipped**，包括 120 项宿主（114 Package＋6 DemoHost）及 7 项 UI；保留 V1 的 102 项，新增 25 项。test-summary.json、Tests.xcresult 与完整日志留存。
- docs：16 个 Markdown 文件、2 项 Shell 语法及文本／链接检查通过。测试后仅更新文档并复制原始截图，没有修改已验证源码。

## 截图检查

从本次成功的 Tests.xcresult 原样导出至 `.build/verification/m1a-final-attachments/`，manifest.json 保存测试和原图映射。已逐张检查 [UIKit 240／居中](images/m1a-segments-uikit-240-center.png) 和 [SwiftUI 240／居中](images/m1a-segments-swiftui-240-center.png)。两端原文、换行、图片尺寸和方向一致：上箭头橙标在左上，右箭头橙标在右上；分段改造没有改变显示。其余原文／图片／UIView／列表 UI 回归均通过，未将截图推导为文字动作已可交互。

## 未验证与后续

Swift 6.0 编译器兼容、iOS 16 运行、真机与人工 VoiceOver 仍未验证。动作当前仅是经过校验的描述，不提供 onAction、手势、按下态或无障碍激活；这些由后续 I1／A1 交付。M1b 尚未完成，不能由本次模型测试推导装饰或段落样式通过。
