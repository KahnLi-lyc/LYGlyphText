# G5 选择与复制验证记录

日期：2026-10-21。基于 G4，分支 `codex/g5-selection`。执行契约见 [2.x Label 路线图](../superpowers/plans/2026-10-21-label-roadmap.md) G5。

## 设计取舍

路线图原计划实现非编辑 `UITextInput` 并接入 `UITextInteraction(for: .nonEditable)`。实现前评估：自定义视图遵循 `UITextInput`（继承 `UIKeyInput`）成为第一响应者时会请求键盘，需额外隐藏输入视图；协议有约 30 个必需方法，非编辑场景大多为空实现，容易与动作手势、列表滚动产生冲突。改为在现有 Core Text 原文几何上实现选区，配合系统 `UIEditMenuInteraction`（iOS 16）提供拷贝／全选菜单：

- 不引入 TextKit，不显示键盘；选区、拖柄、命中全部复用最终原文 cell 几何（与绘制、动作、无障碍一致）。
- 放大镜（`UITextLoupeSession` 仅 iOS 17+）未提供。

## 交付的公开接口

| 接口 | 行为 |
|---|---|
| `isSelectable` | 默认 false。开启后长按非动作文字（0.5 秒）选中所在单词并显示系统菜单；动作与可交互截断 token 优先。 |
| `selectedRange` | 原文 UTF-16 范围；设置时扩展到完整组合字符，空、越界或不可选时为 nil。 |
| `selectedText` | 选区纯文本；附件输出替代文本，无替代文本的附件不输出。 |
| `onSelectionChange` | 选区变化时回调新范围或 nil。 |
| `copy(_:)`／`selectAll(_:)` | 拷贝写入 `UIPasteboard.general.string`；全选只选择可见原文（截断隐藏部分不选）。 |

拖柄为竖线加圆点，命中区约 44pt，拖动时两端交叉会交换；拖动结束重新显示菜单。点按选区外、替换文档、移出 window、失去第一响应者或关闭 `isSelectable` 时清除选区。选区以宿主 `tintColor` 的 25% 透明度绘制在文字下方。

## 行为证据

- `Tests/LYGlyphTextTests/SelectionTests.swift`（8 项）：按字符中线与最近行求边界、RTL 镜像、单词范围与 ZWJ／组合字符扩展、插入点位置；非可选时 selectedRange 被忽略；附件替代文本与拷贝写入剪贴板、canPerformAction；长按落在动作上让位、落在普通文字上选中单词并成为第一响应者、两个拖柄、拖动扩展与交叉交换；替换文档、移出 window、关闭可选时清除并回调；全选只选可见原文。
- 新增 Demo 页“2.x：截断 token、网络图片、选择拷贝”（`FeatureDemoController`），使用本地生成图片的演示加载器，不访问网络。`LYGlyphTextDemoUITests/FeatureUITests.swift`（2 项）：真实长按选中“选择”并出现系统菜单（Copy／Select All），点 Copy 后 App 读到剪贴板内容；点击“…展开全文”展开，远程图片加载 1 张。
- 定向运行中发现并修正 2 处测试自身问题（断言取错字符位置；SwiftUI 更新在下一周期，改为有限等待真实更新），组件代码未因此改动。拖柄在首行或末行时会被 Label 裁切，已改为移回 bounds 内。
- 截图已人工检查：选区高亮、两端拖柄、系统菜单；截断 token 位于第二行末尾，展开后完整显示。

## 正式检查

| 检查 | 结果 |
|---|---|
| 固定 SwiftFormat 0.59.1 | 107 个 Swift 文件 0 需格式化 |
| `scripts/verify.sh docs`／`build` | PASS |
| `scripts/verify.sh test` | **413／413 Passed（387 宿主＋26 UI）**，0 失败／跳过／预期失败，`runtimeWarnings=[]` |

G4 的 403 个测试方法全部保留，新增 10 项。证据保存在主 checkout 的 `.build/verification/g5/`。人工 VoiceOver 下的选区体验、iPad 指针与外接键盘未验证。
