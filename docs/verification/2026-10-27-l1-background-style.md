# L1 文档级圆角背景／边框验证记录

日期：2026-10-28。基线 `4d9575b`，分支 `codex/l1-background-style`。契约见 [L 批次](../superpowers/plans/2026-10-27-label-refinements.md) L1。

## 交付的公开接口

- `NSAttributedString.Key.lyGlyphTextBackground`，值为 `LYGlyphTextBackgroundStyle`（Equatable、Sendable）：`fillColor`、`strokeColor`、`strokeWidth`、`cornerRadius`、`padding`。非有限或负的宽度、圆角按 0，非有限外扩按 0；绘制前再次清洗，防止公开 var 被改写成非法值。没有填充也没有有效描边的样式、以及非该类型的属性值被忽略。
- 绘制：相邻且样式相等的范围合并后，按最终行取可见片段并集再外扩，绘制圆角填充与内收半个线宽的描边；位于普通 `.backgroundColor` 之上、文字之下；截断隐藏的原文没有形状；动态颜色按显示环境解析；不改变测量。
- 可通过 `LYGlyphTextParser` 规则的 `attributes` 直接生成话题胶囊。

## 行为证据

`Tests/LYGlyphTextTests/BackgroundStyleTests.swift`（6 项）：圆角角点不着色而直角会着色；描边在外缘、外扩边距准确、测量尺寸不变；不同前景色的相邻同样式片段合并为 1 个形状、不同样式分开、换行后按行分段；截断隐藏部分无形状、非法值清洗、空样式与错误类型被忽略；明暗动态颜色、RTL 形状覆盖字形范围；解析器规则带出样式并保留动作。

定向：BackgroundStyle／DecorationDrawing／DisplayFeature／Style 共 75 项通过（`.build/verification/l1-targeted-01/`）。测试先于实现编写，实现前因类型不存在无法编译，不另计行为红。

## 正式检查

| 检查 | 结果 |
|---|---|
| 固定 SwiftFormat 0.59.1 | 112 个 Swift 文件 0 需格式化 |
| `scripts/verify.sh docs`／`build` | PASS |
| `scripts/verify.sh test` | **425／425 Passed（399 宿主＋26 UI）**，0 失败／跳过／预期失败，`runtimeWarnings=[]` |

G7 的 419 个测试方法全部保留，新增 6 项。运行期间机器负载很高（其他任务占用大量模拟器），未出现超时。证据保存在主 checkout 的 `.build/verification/20261028T085358Z-45004-test/` 与 `l1/`。
