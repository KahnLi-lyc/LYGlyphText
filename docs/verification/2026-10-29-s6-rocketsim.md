# S6 RocketSim 自动验证记录

日期：2026-10-29。被测版本 main `4f2dd1f`（S1—S5）的 Demo Debug 构建，修复后为分支 `codex/s6-rocketsim`。工具 RocketSim 16.7.0 CLI（`rs/1`），设备为本仓专用模拟器 `5260ADE6-ADC2-44AA-9EEB-CDEC90196D08`（iOS 27），所有命令显式指定 `--udid`。契约见 [S 批次](../superpowers/plans/2026-10-29-label-s-batch.md) S6。

这是探索式补充验证，不代替 XCUITest，也不计入自动回归数。截图、录屏、元素快照与 audit JSON 保存在主检出的 `.build/verification/s6-rocketsim/`（忽略目录，不入库）。

## 驱动的流程

| 流程 | 操作 | 结果 |
|---|---|---|
| 长按选择 | 在“选择”处长按 1 秒 | 状态为“已选：选择”；无障碍树出现 `slider` 选区开始／选区结束，值为“选择” |
| 拖动拖柄 | 从结束拖柄竖线拖到首行 70% 处，同时录屏（`03-handle-drag.mp4`） | 选区扩展为“选择这段文字，然后在系统菜单”，两个拖柄的值同步更新，系统编辑菜单重新出现；文字元素带“拷贝”自定义动作 |
| 系统菜单拷贝 | 点菜单 Copy | 状态为“已拷贝：选择这段文字，然后在系统菜单” |
| 截断 token | 点“…展开全文” | “已展开”，全文 7 行 |
| 整段点击与动作 | 先点非动作文字，再点“作者” | 先“整段点击 1 次”，再“动作：author”，互不串扰 |
| Markdown 链接 | 点“查看文档” | “链接：https://example.invalid/docs” |
| 截断模式 | 切到 head、middle | head 下无障碍树出现“全文结束”；middle 显示“开头部分很长的中间内…很长的中间内容全文结束”（`05-`、`06-` 截图） |
| 调试叠加 | 打开开关 | 行框、基线、动作区域（含截断 token、话题胶囊）按预期描出（`07-`、`09-` 截图） |
| 远程图片 | 页面加载 | “已加载 1 张”“按真实尺寸 120×60”，图片按 120×60 重新排版 |

## accessibility-audit 结果与处理

2.x 页修复前 63 个元素、8 错误、13 警告，得分 78（`08-audit-features.json`）。先保留证据再处理：

| 发现 | 判断 | 处理 |
|---|---|---|
| 拖柄 `hit_region_small`（10×30pt） | 真实问题：触摸命中区约 44×54pt，但无障碍框只有可见竖线 | 修复：`SelectionHandleView.accessibilityFrame` 与 `point(inside:with:)` 共用同一扩展区域；单测断言 ≥44pt 且中心可命中。复查后不再报告 |
| 调试开关无名称（`checkBox` 空标签） | 真实问题（Demo） | 修复：设置 `accessibilityLabel = "调试叠加"`，复查显示“调试叠加” |
| 调试叠加看不到远程图片的附件框 | 真实问题（截图发现，非 audit）：UIView 附件盖在 `draw(_:)` 的描线之上 | 修复：UIView 附件（含远程图片）的框描在视图外侧 1pt；新增像素单测。附件贴着 Label 边缘时，外侧那条边会被 Label 边界裁掉 |
| “作者”“查看文档”“…展开全文”命中区小于 28pt | 段落中的行内链接，属 WCAG 2.5.8 行内例外 | 不修改，记录 |
| 拖柄与所在文字元素重叠 | 拖柄本来就压在文字上，VoiceOver 按顺序逐个访问 | 不修改，记录 |
| 话题胶囊被拆成 5 段（`fragmented_group`） | 动作范围单独成元素以便激活；示例未设置 `onAction`，所以表现为普通文字 | 不修改，记录为后续可评估项 |
| 标题特征、分段控件尺寸 | 启发式误报或系统控件 | 不修改 |

修复后复查（`10-audit-features-after.json`）：60 个元素、7 错误，均为上表中“不修改”的项。首页（`11-audit-home.json`）只报告 13 个系统 disclosure 指示箭头 `chevron` 命中区过小，属系统控件，不修改。

## 工具限制

- RocketSim 原始坐标 tap 两次都没有切换 `UISwitch`，改用 `interact activate`（AXPress）后切换成功；XCUITest 的 tap 可以切换，因此记录为工具输入差异，不是组件缺陷。
- 按 label 选择器长按会落在多行文字中心而不触发选择，改用截图换算的坐标。
- XCUITest 安装新构建并重启 App 后，RocketSim 读到 0 个元素；重启该专用模拟器后恢复。`doctor` 当时检查的是另一台设备，没有给出结论。

## 修复后的检查

修复后定向运行 SelectionHandleAccessibility／DebugOverlay／Selection／SelectionCopy／Accessibility 共 45 项与 FeatureUITests 6 项通过。拖柄无障碍框变大后，XCUITest 用归一化坐标定位拖柄会偏离竖线，UI 测试改为按拖柄中心 x 与首行高度定位。完整回归结果见 S7 记录。

## 未验证

人工 VoiceOver 下的拖柄调节与阅读顺序、iOS 16、真机、iPad 指针。
