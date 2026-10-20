# 参与 LYGlyphText 开发

先阅读 [开发规则](AGENTS.md)、[编码规范](CODING_STYLE.md)、[实施计划](docs/superpowers/plans/2026-10-20-lyglyphtext-implementation.md) 和 [参考资料](docs/REFERENCES.md)。

当前已提供基础显示、行数限制／尾部省略与 UIImage 附件 Package、UIKit／SwiftUI Demo 与宿主测试。能力和真实环境见 [基础显示验证记录](docs/verification/2026-10-20-basic-display.md)、[截断验证记录](docs/verification/2026-10-20-line-limits.md) 和 [图片附件验证记录](docs/verification/2026-10-20-image-attachments.md)；工具检查与组件运行分别留证。

## 本地工具与检查

需要 Git、Bash、Python 3.9+；组件构建另需 Xcode 和 XcodeGen **2.46.0**，运行测试需要可用的 iOS Simulator；格式工具固定为 SwiftFormat **0.59.1**，上游提交 `22a472ced4c621a0e41b982a6f32dec868d09392`。普通检查不联网、不修改源码或安装工具。

```sh
scripts/verify.sh docs
scripts/verify.sh format
scripts/verify.sh build
scripts/verify.sh test <UDID>
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/tests -v
```

- docs：检查本仓跟踪及未忽略的新文本文件的 UTF-8／LF／末尾换行、Markdown 围栏和本地链接文件存在性、Shell 语法，以及暂存／未暂存 diff。只检查文件路径，不验证链接锚点、远端网页或扫描全部敏感信息；提交前仍需人工审查公开内容。
- format：只 lint 本仓未被忽略、且不在生成目录内的 Swift 文件，使用根目录配置。不重写源码；零 Swift 文件明确输出“不适用”，不是代码格式通过。
- 工具回归测试：在临时 Git 仓库验证链接、检查范围、零文件及工具错误等行为，不包含组件测试，也不需要 Simulator。
- build：核对 XcodeGen 2.46.0，生成忽略的 Demo 工程，分别构建 Package 和 Simulator 应用。
- test <UDID>：核对指定 iOS Simulator，执行 shared scheme 的宿主单测和 UI 测试。根目录 Package 单测源码纳入宿主执行，不额外重复运行。零测试、全跳过、失败结果返回非零。
- build／test 的环境、日志和 xcresult 保存在 `.build/verification/`，不自动删除既有结果。生成工程以 `Examples/LYGlyphTextDemo/project.yml` 为事实源，不直接修改生成文件。未知模式或错误参数返回非零。

首次需要格式工具时，显式安装到本仓忽略的 `.build` 目录；该操作会从公开上游取源码并使用本机 Swift 编译，因此还需要 Xcode／Swift 工具链：

```sh
scripts/swiftformat.sh --bootstrap
```

`LYGLYPHTEXT_BUILD_ROOT` 可指定独立工具缓存目录；`LYGLYPHTEXT_SWIFTFORMAT` 可指定已有二进制的完整路径。每次使用都核对版本，不回退到 PATH 中的任意版本。Bootstrap 核对源码提交号；拒绝覆盖来源不明的已有源码目录。

显式格式化仅用于本任务文件，例如：

```sh
scripts/swiftformat.sh Package.swift
```

不要对上级工作区或第三方参考目录运行格式化。不得因工具无法下载而擅自升级版本、修改全局 Git／代理配置或把检查写成通过。

## 风险验证

| 改动 | 最低验证 |
|---|---|
| 文档与非构建配置 | docs、规范一致性及公开内容审查；格式配置变化另用临时 Swift 样例核对 |
| 工具脚本 | docs、对应工具回归测试、真实工具样例；不启动 Simulator |
| 模型和范围转换 | format、目标单元测试，覆盖 UTF-16／组合字符及失败输入 |
| 布局／绘制／截断 | 几何测试、目标示例和 Simulator 验证 |
| 交互／附件／SwiftUI | 取消／生命周期测试、实际手势及宿主布局验证 |
| 公开接口／并发／依赖 | 扩大到 UIKit／SwiftUI 直接消费者 |
| 发布 | 完整回归、最低 iOS 16 运行及性能记录；发布另行授权 |

用实际可用 Simulator UDID，不接管其它任务在用的设备；记录 Xcode、Swift、runtime、设备、命令及结果。不默认 clean，不为局部变更反复跑全套；同一已验证 SHA 不重复执行相同检查。零测试匹配不能算通过。

Swift 6 模式编译、Swift 6.0 工具链兼容、iOS 16 运行分别验证；新 SDK、部署目标、静态阅读及 fake 测试不能代替最低系统或真实操作结果。

## 开发、集成与自动推送

连续开发采用 [总计划执行队列](docs/superpowers/plans/2026-10-20-lyglyphtext-implementation.md) 和 [连续开发契约](docs/superpowers/plans/2026-10-20-continuous-development.md)：

- 从上到下选择第一个未完成且依赖已满足的任务，先固定公开接口、生命周期、失败／取消语义与验收范围，再写失败测试、实现最小改动、验证并更新记录。
- 一个任务完成下述提交、集成、普通推送流程后，自动处理下一项，不等待“继续”确认。状态只按真实证据更新，保留既有测试；不以削减原定验收范围使失败消失。
- 必须由用户决定的真实阻塞、改动冲突或反复验证失败才暂停相关任务，并报告已完成内容、阻塞原因和需要的决定；仍可独立推进的任务继续。
- 不可用环境独立标记“未验证”，不阻塞其他工作；最低系统、旧编译器、真机、人工 VoiceOver 与发布资格仍保留各自验收门槛。普通 push 失败保留本地成果与失败证据，不强推或自动变基；不依赖远端交付的后续任务可继续。
- 连续开发授权不包含 PR、Tag、Release 或远端删除。

1. 检查工作区和活动 worktree，明确改动与验收范围。默认目标分支 `main`；使用 `codex/<task>`，需要隔离或并行时使用独立 worktree。
2. 每次提交一个可说明、可验证的任务；不混入无关格式化、依赖升级或重构。不强制 fetch／pull。
3. 验证通过后仅暂存本任务文件并自动提交。标题使用 feat:／fix:／test:／docs:／refactor:／chore: 前缀和简体中文。
4. 本地合入串行执行：在 Git common directory 下用原子 mkdir 获取 `lyglyphtext-integration.lock`，写明任务、进程和目标 SHA；使用 trap 只释放自己持有的锁。已有锁时停止并报告，不自动删除他人锁。
5. 锁内重新核对 feature tip、目标 tip、目标 checkout 的干净状态及 worktree 占用。目标为 feature 祖先时，feature 是快进候选；否则创建本任务候选分支／worktree进行普通合并。只验证最终候选 SHA；目标变化后重新评估，不覆盖或 force-update main。
6. 候选验证通过后，在目标 checkout 以 `git merge --ff-only <candidate>` 更新本地 main。快进后确认 SHA 一致；同 SHA 不再重复检查。冲突、未知文件、锁异常或验证失败时停止并保留现场。
7. 合入结果验证通过后，在集成锁内核对 origin 指向本仓库，待推送提交均为已授权成果，然后默认自动执行一次 `git push origin main`。不推送临时 feature 分支，不需要每轮重复确认；用户明确要求不推送时跳过。范围不明时停止并报告。
8. push 失败不回滚本地合入，不自动 pull／rebase、不强推或改写历史，保留成果并报告失败原因。push 成功后核对远端 main SHA 与候选一致，才能报告远端交付完成。
9. push 无论成功或失败，只要当前 feature tip 已是 main 的祖先，且临时 worktree 干净、没有未知未跟踪／忽略文件，就只清理本任务创建的 worktree 和本地分支；使用 git worktree remove 与 git branch -d，不强制删除。合入或验证失败时不推送、不清理。

上述是人工／代理执行约定，当前检查脚本不代替 Git 集成流程。普通目标分支 push 已由仓库约定默认授权；PR、远端删除、Tag 和 Release 仍需明确任务授权。不自动 pull、rebase 或改写历史。

## 交付说明

记录问题与最终行为、公开 API／依赖变化、目标分支与提交、真实检查、push 结果及限制；明确区分本地完成与远端交付。README 只说明实际状态；安装说明与版本号在真实 Package 可用后补充。

构建产物、工具缓存、签名凭据、个人路径及内部项目源码不进入提交。生成文件先修改事实源；不要把普通源码文件误判为生成物。第三方复用按 REFERENCES 保留许可与来源。
