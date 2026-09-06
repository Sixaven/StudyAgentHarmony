# UI Milestone 4 实施与验收记录

2026-09-06。UI 工程 D:/Harmony/Project/StudyAgent，分支 codex/ui-milestone-4；后端基线 8429f8a。UI-CTRL-01、UI-CTRL-02、UI-REC-01、UI-INT-01 已完成；M3 的真实 Agent API 连通门槛同时关闭。

## 实现

- 独立 stop 请求和停止收尾；202 不提前解锁，终态与 HTTP 响应交错不回退。
- 原请求核对与新业务重试分开，两者按钮都叫“重试”；未知记录不丢弃、查询不可用不重发；旧资格冲突刷新当前任务。
- Preferences 持久化最小 send/retry/stop 日志；存储失败阻止写请求，应用重开先核对再恢复。正式消息与 canRetry 来自服务端。
- Ability/页面共同管理观察生命周期，后台迟到回调隔离，销毁释放 RCP 而不停止业务；历史稳定归并和滚动。
- 增加 StopFlow、RetryFlow、RecoveryFlow、设备 ChatFlow 及真实后端故障宿主。设备存储和测试 ID 支持注入，不把固定模型结果写进生产 UI。

## 检查结果

| 检查 | 结果 |
|---|---|
| API 20 应用 / ohosTest HAP | 编译及打包通过 |
| Code Linter | 0 错误，原有 6 条组件拆分建议 |
| 本地 Hypium | 71 项通过，0 失败/错误 |
| 设备 Hypium | 3 项通过，0 失败/错误；真实服务显式开启 |
| 后端 chat:acceptance | 25 项真实 HTTP/SSE/SQLite 检查通过 |

## 真实设备联调证据

设备为已有 Mate 70 Pro / HarmonyOS 6.0.0.48（API 20），通过显式 hdc rport 连接本机真实 API。Agent 与业务存储均使用正式实现；模型为脚本模型、资料为明确标记的本地固定资料。代理只注入连接故障，不伪造 API 数据。

| 场景 | 观察结果 |
|---|---|
| 学习、澄清、追问、回答与来源 | 正式消息分次出现；设备 ChatFlow 校验消息/终态/草稿，来源弹层可读；真实后端检查确认追问不推进原题 |
| 接受后响应丢失 | 待确认气泡和“重试”保留；点击后查询原请求，SQLite 中该用户消息仅一条 |
| 评价保存后失败 | 评价仍可读，canRetry=true；业务重试继续生成下一题，答案与评价不重复 |
| 停止响应丢失与应用重开 | 服务端 cancelled/user_stop；UI 保留核对入口，force-stop 应用后重开从 Preferences 找回停止请求并恢复终态 |
| 成果保存后服务进程崩溃 | 原任务 running/revision 3 时强制结束隔离测试进程，原库重启；设备查询后显示 failed/server_restarted，消息数量不变，未自动业务重试 |
| 主题切换后旧重试失效 | 另一个已接受的“切换：Agent”推进 latestTask；旧按钮调用被拒绝，页面显示当前主题任务和拒绝原因，无静默重路由 |
| 停止竞争、重复停止/重试、同 ID 重放、迟到事件 | 本地状态测试及真实后端验收覆盖；终态优先，只有一个重试后继 |

设备自动化首次因默认 5 秒超时中断；设置明确 60 秒单项超时后 3 项全部通过。没有把编译成功或测试命令退出码代替测试报告。原始本地 Hypium 报告在 entry/.test/default/intermediates/test/coverage_data/test_result.txt。

## 运行与边界

UI 默认恢复 fake/空地址，不提交临时服务地址、数据库或生成产物。可复核命令与故障开关见 UI 工程 docs/ui-development.md 末尾 M4 章节及 docs/testing/real-chat-server.mjs。

M4 未修改业务/Agent 源码或公共 API 契约，没有新增需其他层协商的问题。规划库 docs 已被 Git 忽略，本记录和清单在本地同步；可提交的同版验收记录保存在 UI 工程 docs/ui-milestone-4-acceptance.md。

本次不声称真实模型教学质量、真机或跨 SDK 兼容通过；来源外链仍需具备浏览器的设备复核。应用进程重开不恢复未发送草稿，只恢复最小未确认操作和服务端事实。

补充集成修正：RcpTransport 将配置验证移至请求入口，错误配置由页面加载失败状态展示，不在 Ability 初始化时崩溃；新增对应本地回归检查。
