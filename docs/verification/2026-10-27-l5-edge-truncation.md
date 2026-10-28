# L5 头部／中间截断验证记录

日期：2026-10-28。基于 L4，分支 `codex/l5-edge-truncation`。契约见 [L 批次](../superpowers/plans/2026-10-27-label-refinements.md) L5。

## 交付内容

- `LYGlyphTextConfiguration.truncationMode`：`.tail`（默认，行为不变）、`.head`、`.middle`，只作用于最后一条可见行。
- head：token＋剩余原文的末尾；middle：本行开头（最多占 token 之外一半宽度）＋token＋剩余原文的末尾。先去掉文档末尾的空白与空白段落，末尾只取最后一个有内容的逻辑段落；没有可保留的末尾时按 `.tail` 处理；token 放不下时与 `.tail` 一样不绘制内容。
- 内部 `Line` 增加 `suffixSegment`：token 之后的原文片段使用独立偏移；命中、选区、动作矩形、附件定位与 AX 统一改为按 run 取偏移。与尾部截断共用的 token 与可用宽度计算抽成 `TruncationSetup`，尾部截断行为由既有等价对照测试保护。

## 行为证据

`Tests/LYGlyphTextTests/EdgeTruncationTests.swift`（6 项）：head 的 token 位于行首、可见区间到文档末尾、宽度不超出、token 在末尾文字之前；middle 保留行首与文档末尾两个区间、被省略的中间原文没有片段、几何顺序为行首→token→末尾；省略号之后的图片附件与动作在 head／middle 下都正确定位，动作事件范围为完整原文范围，选区边界映射正确；末尾只取最后一个段落、末尾的空白段落被忽略（初版测试误以为会回退为 tail，实现与契约一致后修正测试）；RTL head 有效；超宽 token 时为空行；Label 改变模式后重新排版。

## 失败与修正

L4＋L5 定向 128 项中 1 项失败：初版测试预期“末尾只有空白段落时回退为 tail”，而实现先去掉末尾空白段落，再从最后一个有内容的段落取末尾。实现与契约（先清除尾部空白）一致，修正测试与文档注释；修正后 EdgeTruncationTests 6 项通过（`l5-targeted-02/`）。

## 正式检查

| 检查 | 结果 |
|---|---|
| 固定 SwiftFormat 0.59.1 | 118 个 Swift 文件 0 需格式化 |
| `scripts/verify.sh docs`／`build` | PASS |
| `scripts/verify.sh test`（包含 L2—L5 全部代码） | **442／442 Passed（415 宿主＋27 UI）**，0 失败／跳过／预期失败，`runtimeWarnings=[]` |

L1 的 425 个测试方法全部保留，L2—L5 共新增 17 项。合入前核对 L3、L4、L5 各提交的 Swift 文件与该次回归的源码逐字一致（只有文档差异）。证据保存在主 checkout 的 `.build/verification/l45/`（含 `20261028T102434Z-99910-test/`）。
