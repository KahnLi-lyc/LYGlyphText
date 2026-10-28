# L3 选择拷贝增强验证记录

日期：2026-10-28。基于 L2，分支 `codex/l3-selection-copy`。契约见 [L 批次](../superpowers/plans/2026-10-27-label-refinements.md) L3。

## 交付内容

- `copy(_:)` 同时写入 `public.utf8-plain-text` 与 `public.rtf`：富文本按文档白名单样式重建（字体、前景、背景、下划线、删除线、字距、基线偏移），附件输出替代文本；两种表示的文字一致。
- iOS 17+ 拖动拖柄时显示系统放大镜（`UITextLoupeSession`，以 `#available` 隔离），iOS 16 没有放大镜。
- 有选区时，文字无障碍元素提供自定义动作，名称为 `LYGlyphTextLabel.selectionCopyAccessibilityName`（默认“拷贝”），执行即拷贝。
- 拖柄拖出 Label 时按最近行、最近字符边界收敛；拖柄视图保持在 bounds 内。

## 行为证据

`Tests/LYGlyphTextTests/SelectionCopyTests.swift`（3 项）：剪贴板同时有纯文本和 RTF，RTF 解析后文字一致、首字为 22pt 粗体、下划线保留、附件为替代文本；无选区时没有自定义动作，有选区时动作名可替换且执行后写入剪贴板；拖柄拖到远处时选区扩展到可见首尾，拖柄框在 bounds 内。

放大镜依赖真实拖动手势，自动化无法定位未暴露给无障碍的拖柄视图，未做 UI 自动化验证；人工 VoiceOver 体验未验证。

## 失败与修复

L3 第一次完整回归 433 项中 432 通过：新测试 `testDraggingHandlesBeyondLabelClampsToVisibleBoundaries` 发现选区从首字开始时开始拖柄 x 为 -5，超出 Label 左边界被裁切。原实现只把拖柄限制在上下边界内（G5），现补充左右方向的限制。修复后 SelectionCopy／Selection 11 项与 FeatureUITests 3 项通过（`l3-targeted-02/`）。

## 正式检查

| 检查 | 结果 |
|---|---|
| 固定 SwiftFormat 0.59.1／docs／build | PASS |
| 第一次完整回归 | 432／433，失败即上述拖柄缺陷 |
| 修复后定向 | 14／14 通过 |
| 包含 L2—L5 全部代码的完整回归（L5 候选） | **442／442 Passed**，0 失败／跳过，`runtimeWarnings=[]` |

证据保存在主 checkout 的 `.build/verification/l3/`。
