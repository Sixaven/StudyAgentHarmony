# StudyAgent · HarmonyOS

面向 AI 工程、Agent 与 AI Coding 学习的 HarmonyOS 原生客户端。用一个持续聊天窗口承载讲解、提问、实践、反馈和来源查看，通过 HTTP/SSE 连接 [StudyAgent 后端](https://github.com/Sixaven/studyAgent)。

客户端使用 ArkTS、ArkUI 状态管理 V2 和 Remote Communication Kit（RCP）。学习动作判断、模型调用、评价、掌握度与正式聊天记录由后端负责，客户端不持有模型密钥。

## 功能与范围

- 持续聊天：多行输入、待确认消息、历史分页、基础 Markdown 与代码块阅读。
- 消息级来源：查看资料标题、发布日期、引用片段和原文链接。
- 请求控制：处理进展、停止确认、网络结果核对和业务失败重试。
- 恢复：应用重开后核对未确认操作、恢复服务端正式消息与任务状态。
- 模拟模式与真实 API 模式可切换，真实模式失败不会自动回退到模拟数据。

首版在消息保存后整条展示，不提供逐字生成和行内引用。Markdown 支持标题、段落、列表、强调、链接及围栏代码块；复杂嵌套、表格、图片和 HTML 不作完整语法渲染。进程重开不恢复未发送草稿。

## 开发环境

已验证环境为 DevEco Studio 6.0.0.858、HarmonyOS 6.0.0（API 20）、phone 模拟器。工程的目标与最低兼容版本均为 API 20，构建使用 Hvigor，测试使用 Hypium。

1. 克隆本仓库，在 DevEco Studio 中打开项目根目录。
2. 安装对应 HarmonyOS SDK，完成工程同步与依赖安装。
3. 启动 API 20 手机模拟器，选择 entry 模块运行。

提交版本默认使用模拟模式，无需启动后端或配置模型即可查看页面和模拟交互。SDK 路径、IDE 配置与生成产物保存在本地；真机安装需要自行配置签名，仓库不提供签名证书。

## 模式与后端联调

修改 [ChatConfig.ets](entry/src/main/ets/chat/bootstrap/ChatConfig.ets) 中的配置对象，然后重新构建运行。

| 字段 | 提交版本默认值 | 含义 |
| --- | --- | --- |
| mode | fake | fake 使用内存模拟服务；real 连接后端 API |
| baseUrl | 空字符串 | real 模式需填写设备可访问、包含 /api/v1 的地址 |
| requestTimeoutMs | 15000 | 普通请求超时，毫秒 |
| streamIdleTimeoutMs | 90000 | 流式连接空闲超时，毫秒 |

模拟场景在 [ChatDependencies.ets](entry/src/main/ets/chat/bootstrap/ChatDependencies.ets) 和 demo/ 中组装，页面不提供场景选择器。

先在后端仓库根目录启动脚本模型服务：

```sh
npm ci
npm run chat:serve -- --mode script --dir var/chat-api-script
```

该模式使用真实 Agent 编排、HTTP/SSE 和 SQLite，模型输出与示例资料为预设数据。后端默认只读模式不能发送消息，联调时需要显式使用 script 或 real。

若使用模拟器到开发电脑的端口转发，可在 PowerShell 执行以下示例。Studio 路径和设备 ID 请按本机调整：

```powershell
$studioPath = 'D:\Harmony\IDE\DevEco Studio'
& "$studioPath\sdk\default\openharmony\toolchains\hdc.exe" list targets
& "$studioPath\sdk\default\openharmony\toolchains\hdc.exe" -t '127.0.0.1:5555' rport tcp:3000 tcp:3000
```

完成转发后，将客户端 mode 设为 real，baseUrl 设为 `http://127.0.0.1:3000/api/v1`。没有转发时，设备的 127.0.0.1 指向设备自身；局域网连接需要配置设备可达的主机地址、后端监听地址及网络访问权限。

客户端 real 表示连接真实 API，不决定后端是否调用真实模型。真实模型凭据、资料准备，以及 manual / langchain 引擎选择均在后端配置，见后端 README。联调配置可留在本地，提交时保持通用默认值。

## 目录导航

| 路径 | 职责 |
| --- | --- |
| entry/src/main/ets/pages/Index.ets | 聊天页面 |
| entry/src/main/ets/entryability/ | Ability 生命周期 |
| entry/src/main/ets/chat/bootstrap/ | 配置、依赖组装与观察生命周期 |
| entry/src/main/ets/chat/contracts/ | 消息、任务及 ChatService 契约 |
| entry/src/main/ets/chat/state/ | ViewModel、消息归并与输入状态 |
| entry/src/main/ets/chat/components/ | 消息列表、输入区和状态提示 |
| entry/src/main/ets/chat/content/、sources/ | Markdown、代码块与来源弹层 |
| entry/src/main/ets/chat/transport/、streaming/ | HTTP 校验、UTF-8 解码与 SSE 订阅 |
| entry/src/main/ets/chat/recovery/ | 未确认操作的设备存储与恢复契约 |
| entry/src/main/ets/chat/demo/ | 模拟服务、消息和回复样例 |
| entry/src/test/、entry/src/ohosTest/ | 本地单元测试与设备测试 |
| docs/ | 开发说明、验收记录及联调脚本 |

组件通过参数和事件协作，ViewModel 统一管理交互状态。Preferences 只保存最小未确认操作日志，正式消息和学习事实以服务端为准；退出页面或释放订阅不会停止服务端任务。

## 构建与测试

日常可通过 DevEco Studio 构建、运行及测试。已配置 DevEco CLI 的环境也可在本仓库根目录执行：

```powershell
$env:DEVECO_CLI_STUDIO_PATH = 'D:\Harmony\IDE\DevEco Studio'
devecocli build
devecocli check lint
devecocli run --device '127.0.0.1:5555'
```

本地 Hypium 测试使用 Studio 自带 Hvigor：

```powershell
$studioPath = 'D:\Harmony\IDE\DevEco Studio'
$env:DEVECO_SDK_HOME = "$studioPath\sdk"
$env:NODE_HOME = "$studioPath\tools\node"
& "$studioPath\tools\hvigor\bin\hvigorw.bat" --mode module -p product=default -p 'module=entry@default' test
```

2026-09-06 的阶段验收记录包含：71 项本地测试、3 项设备测试通过，API 20 构建通过；模拟器已与脚本模型、真实 API 和 SQLite 完成聊天、停止、重试及重启恢复联调。这些是已有验收结果，不代表真实模型教学质量、真机或跨 SDK 兼容性已通过。来源弹层已验证，原文外链成功打开仍需具备浏览器的设备验证。

详细步骤与故障注入方式见 [开发说明](docs/ui-development.md) 和 [M4 验收记录](docs/ui-milestone-4-acceptance.md)。开发说明保留各阶段历史，当前行为以末尾 M4 章节为准。
