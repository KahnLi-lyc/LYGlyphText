# UIView 附件与生命周期验证

日期：2026-10-20。基于 `160c3c4`，本记录随 V1 功能提交；按 CONTRIBUTING 集成与普通推送，不创建 PR、Tag 或 Release。

## 接口与实际行为

- 新增 MainActor 不可变 `LYGlyphTextViewAttachment` 和引用类型 `LYGlyphTextAttachmentViewProvider`。文档增加默认空的 viewAttachments；图片接口与旧调用兼容。两类描述统一校验 UTF-16 独立占位、唯一 ID、有限正尺寸；同位置冲突明确报错。
- Layout 只保存描述、数值与最终可见几何。所有测量与未进入 window 的离屏布局不调用工厂；声明尺寸决定外框，工厂 frame／intrinsicContentSize 不反馈到文字排版。
- Label 展示布局按自身内容可见区挂载。持续可见实例复用，完全裁切／截断后卸载释放；重新可见新建。部分可见保持完整尺寸，由内容容器裁切，裁切外不响应触摸。父列表屏幕可见性由宿主复用生命周期管理。
- nil／拒绝结果在本次持续可见期间不重复请求。拒绝已有 superview、重复实例、Label 自身或祖先，不抢走外部视图。两个 Label 共用文档时分别拥有实例。
- 同 provider 身份不重建；更换、reload、文档替换／清空、detach 和 SwiftUI dismantle 有幂等清理。每个成功挂载对应一次原 provider 的 onUnmount；未挂载失败结果不回调。
- 版本检查丢弃同步回调产生的过期结果。整个旧附件卸载批次完成前禁止重新挂载；SwiftUI dismantle 原子清空输入，回调不能恢复旧内容。weak 测试检查旧视图和 provider 释放。
- isInteractive 只控制附件自身原生按钮／手势。空容器穿透，文字动作、长按和高亮尚未实现。

## 环境与结果

| 项目 | 实际环境 |
|---|---|
| Xcode／编译器 | 27.1（27A9275）／Apple Swift 6.4 |
| 语言模式／部署目标 | Swift 6／iOS 16 |
| XcodeGen／SwiftFormat | 2.46.0／0.59.1 |
| 独占 Simulator | LYGlyphText Images Handoff，iPhone 17 Pro，arm64 |
| UDID／运行系统 | `5260ADE6-ADC2-44AA-9EEB-CDEC90196D08`／iOS 27.0（24A434） |

```sh
scripts/verify.sh docs
scripts/verify.sh format
scripts/verify.sh build
scripts/verify.sh test 5260ADE6-ADC2-44AA-9EEB-CDEC90196D08
```

- docs 通过；SwiftFormat 0.59.1 检查 **27 个 Swift 文件，0 个需格式化**。使用 LYGLYPHTEXT_SWIFTFORMAT 指定本机已有固定版本，没有下载／升级工具。
- `.build/verification/20261020T080021Z-35232-build/`：Package 和 Demo 均为 **BUILD SUCCEEDED**，Swift 6 language mode；保留环境与日志。
- `.build/verification/20261020T080101Z-35994-test/`：**102／102 Passed，0 failed／0 skipped**。包括 95 项宿主测试（89 项 Package 测试＋6 项 DemoHost）与 7 项真实 UI 测试；保留原有 72 项，新增 30 项。test-summary.json 的 totalTestCount=102、result=Passed，Tests.xcresult 与完整日志保留。
- 规格及独立代码质量审查均通过。测试成功后仅更新文档／复制原始截图，没有修改已验证源码。

## 行为覆盖

| 范围 | 证据 |
|---|---|
| 默认值、两类冲突、UTF-16、位置／尺寸／ID、快照 | ViewAttachmentTests；保留既有 Document／图片测试 |
| 三种对齐、混合字号、RTL、图片与 UIView 几何一致 | ViewAttachmentTests；共用最终 run 与原文位置 |
| 最终截断保留／移除、恢复后新建 | ViewAttachmentTests；隐藏集合与精确 factory／unmount 次数 |
| 全部测量入口及离屏布局零工厂 | ViewAttachmentTests；sizeThatFits、intrinsic、system fitting、纯布局及 SwiftUI |
| 持续可见宽度往返、inset、非零 bounds、部分高度裁切 | ViewAttachmentTests；实例身份、完整 frame、可见触摸范围 |
| 所有权拒绝、nil 缓存、两宿主独立 | ViewAttachmentTests；拒绝不卸载外部视图，双宿主不同实例 |
| 替换／清空、reload、provider 身份、detach／reattach | ViewAttachmentTests；原 provider 恰好一次卸载、weak 释放 |
| factory／onUnmount／视图层级回调同步重入 | ViewAttachmentTests；版本核对、旧批次事务及原子 dismantle |
| UIKit／SwiftUI 真实按钮与控制操作 | 两项新增 UI 测试；点击计数 1→清空→重载→2，操作三种对齐、160／240／320 宽与行数 |
| UITableView 滚动／复用／返回 | 新增 UI 测试；滚动后按钮行号与当前内容一致，返回第 0 行从 0 再点击为 1 |
| 列表实际宽度与高度 | DemoHostTests；390→320→600→390、row 0／28／50／0，实际 label 高度容纳同宽测量结果 |

## 失败、修复与针对性结果

- `v1-red-api`：旧实现缺少描述、入口和几何类型，编译失败，不能算运行通过。
- `v1-lifecycle-1`：fixture 的显式 self 捕获编译失败；`v1-lifecycle-2` 的 17 项中两项因 autoreleasepool 未排空、weak 变量指向后续合法实例而失败。修正 fixture，保留计数和释放断言；`v1-lifecycle-3` 为 17／17 通过。
- `v1-consumers-1`：22 项附件＋5 项 DemoHost＋3 项新增 UI，全部通过；这是补充测试，最终计数以上述完整回归为准。
- `v1-list-height-red`：新增真实列表宽度／滚动测试复现 28 个高度断言失败，截图第 28 行说明被裁切。cell 的 systemLayoutSizeFitting 使用传入目标宽度减实际约束边距设置 preferredMaxLayoutWidth，避免复用旧 bounds 估算。
- `v1-cleanup-batch-red`：一个多旧附件重入测试实际出现 3 个失败断言。现以清理深度保护整个容器移除、detach 和回调批次，避免旧 onUnmount 处理新挂载的同一实例。
- `v1-cleanup-list-green-1`：24 项附件＋1 项列表高度测试，25／25 通过。`v1-list-ui-fixed`：列表 UI 1／1 通过，复查原缺口截图；随后完整 102 项回归通过。

上述日志与 xcresult 均保留在 `.build/verification/`；没有通过缩减内容、删除原用例或减少断言使失败消失。

## 截图检查

从最终成功的 Tests.xcresult 导出至 `.build/verification/v1-final-attachments/`，manifest.json 关联测试与原始图片。下列八张原样复制入仓库，逐张检查，未裁剪／修饰。

| 场景 | UIKit | SwiftUI |
|---|---|---|
| 顶部，160，单行省略 | [截图](images/view-attachments-uikit-160-top-one-line.png) | [截图](images/view-attachments-swiftui-160-top-one-line.png) |
| 居中，240，两行 | [截图](images/view-attachments-uikit-240-center-two-lines.png) | [截图](images/view-attachments-swiftui-240-center-two-lines.png) |
| 底部，320，无限行 | [截图](images/view-attachments-uikit-320-bottom-unlimited.png) | [截图](images/view-attachments-swiftui-320-bottom-unlimited.png) |

两端相同输入显示一致，UIImageView、按钮、徽章与文字区域的对齐一致；160 单行只保留前两个附件及省略号，240／320 显示徽章与后续文本；真实按钮计数为 2。nil 工厂仍保留声明占位。

列表 [滚动后](images/view-attachments-list-scrolled.png) 与 [返回第 0 行](images/view-attachments-list-return.png) 显示当前行按钮和完整文案，没有复用旧计数；第 28 行文字已完整。截图只证明这些 fixture，精确生命周期／RTL／裁切断言由测试提供。

## 未验证与后续

- Swift 6.0 编译器兼容、iOS 16 实际运行、真机与人工 VoiceOver 仍未验证；当前 Swift 6.4／iOS 27.0 结果不能替代。
- alternativeText 仍为描述数据；完整 VoiceOver 行内语义由 A1 验收。
- 完整 StackView／UICollectionView／SwiftUI 列表矩阵由 H1 完成；本次 UITableView fixture 不代表全部宿主矩阵已通过。
- 后续依次实现 M1 分段／动作描述／样式、I1 文字交互、H1、A1 和 P1；不提前勾选环境或发布门槛。
