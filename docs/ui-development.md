# UI 开发与阶段验收

2026-09-06。M1、M2 的原生聊天页、Markdown/来源和模拟发送闭环已实现并在 API 20 模拟器运行。M3 HTTP/SSE 客户端适配与协议替身设备检查已完成，真实 Agent API 连通待服务端交付；停止/重试及持久恢复按 M4 推进。

## 工程与入口

- DevEco Studio 6.0.0.858，HarmonyOS 6.0.0（API 20），phone，ArkTS / ArkUI 状态管理 V2。
- 页面：`entry/src/main/ets/pages/Index.ets`。依赖组装：`chat/bootstrap/ChatDependencies.ets`，组件不创建服务。
- `createChatViewModel()` 默认使用 `FakeChatService('ready')`。开发时可传入 `empty`、`loading_error`、`running`、`partial_failure`。
- 场景选择仅在组装代码里修改，页面不放场景选择器。顶部“模拟预览”表明当前数据为样例。
- M2 已接通模拟发送：原文接受后转为正式用户消息，随后完整保存助手回复。按 Unicode 码点显示 2000 上限；处理中可编辑新草稿，不可并发发送。停止仍提示尚未接入，其实现属于 M4。
- `running` 初始快照进入核对中，禁止发送；启动恢复流程在 M4 接入。M2 已观察本次新发送的任务。
- `FakeChatService.emit()` / `failConnection()` 可受控推进观察者；dispose 仅解除观察，不等于停止任务。模拟服务未实现的方法明确拒绝，不能作为真实能力验收。

参考规划库 `D:/VsCode/Project/StudyAgent/docs/tasks/ui/` 下的任务清单、契约 v0.3 及 `prototype/` 原型。M1 按原型落实配色、阅读版式、用户气泡、底部输入；M2 已将助手 markdown 消息接入原生内容渲染；用户内容仍为普通文本。明暗主题颜色放在 base/dark 资源中，不仿造系统状态栏。键盘用 API 20 支持的 `KeyboardAvoidMode.RESIZE`，保持标题和输入区可见，列表收缩。

## 数据与协议样例

客户端 DTO 按已确认 UI/API 契约声明；以下是契约样例，M3 已实现 HTTP/SSE 校验与适配，尚未完成真实 Agent 服务联调。UI 不推断学习动作、不访问业务层，也不保存掌握度。

- 正式消息按 messageId 去重，sequence 排序；相同正文不同 ID 保留。重复快照不修改初次 requestId/taskId。
- 用户消息 requestId 匹配时移除待确认项；助手消息的相同 requestId 不能确认用户发送。
- origin 保留 interactive/legacy/local，旧消息可空 requestId/taskId；draftId 为 null、previews 为空。
- TaskSnapshot 保留 revision、outcome、runtimeReason、reason、error、savedMessages、canRetry。已保存成果不会随 failed 消失。
- 服务契约覆盖初次加载、历史、发送、请求查询、任务查询、订阅释放、停止、重试。方法返回解包后的 data；拒绝由 ChatServiceError 表达。
- ChatServiceError.kind=rejected 表示未接受的服务拒绝；network 表示是否接受未知，后续先查询原 requestId。接受后的失败由 TaskSnapshot 表达。

HTTP 未接受样例：

```json
{
  "error": { "code": "invalid_input", "message": "请输入不超过 2000 个字符的内容。" },
  "requestId": "client-request"
}
```

2000 按 Unicode 码点计数，原文不 trim 或改写。M2 在发送前和输入计数中使用同一个码点函数，不能直接用 TextArea.maxLength 的 UTF-16 语义替代。

GET /api/v1/chat 的成功外壳：

```json
{
  "data": {
    "chatId": "demo-chat",
    "messages": [],
    "olderCursor": null,
    "activeTask": null,
    "latestTask": null
  }
}
```

SSE 首版仅使用 task_snapshot、task_progress、message_saved、task_finished。例如：

```text
id: 3
event: task_progress
data: {"chatId":"demo-chat","taskId":"demo-task","requestId":"demo-request","phase":"searching"}

```

task_snapshot/task_finished 带 task，message_saved 带 message/taskRevision；所有事件带 chatId/taskId/requestId。ChatEvent 是传输无关的客户端信封，HTTP/SSE 原始 JSON 的字段校验在 M3 实现。

Agent 已确认首版 ProgressPhase 只有 processing/searching/saving；停止中用 task.status=stopping 表示，不增加 phase。发送返回 data={userMessage,task}；停止、重试和单任务查询直接返回 data=TaskSnapshot；请求查询返回 data={requestId,kind,task}。现有 ChatService 返回解包后的对应类型，不额外包裹 task。HTTP 200 读取 failed 快照仍是正常返回，不转换成拒绝错误。

ServiceError.details 是可选对象，支持 existingTaskId。ChatServiceError 构造器及 fromServiceError 保留该字段；缺失详情时不编造 ID。fromServiceError 接受已校验 DTO，原始 HTTP JSON 校验留在 M3。

同一原任务已有直接后继时，新的重试请求返回 HTTP 409：

```json
{
  "error": {
    "code": "retry_not_allowed",
    "message": "该任务已有后续重试，请查看已有任务。",
    "details": { "existingTaskId": "successor-task" }
  },
  "requestId": "new-retry-request"
}
```

此 ID 用于后续查询任务并刷新聊天，不自动再发 retry。同 requestId 的幂等重放仍优先返回原成功结果；其他无后继的资格失败不携带 existingTaskId。以上对接已获 Agent 确认，M1 无需等待后端上线，真实通信联调仍属于后续阶段。

## 已执行的检查

本机 PowerShell 显式指定 Studio 路径后，DevEco CLI 的 build/run/check lint 可用：

```powershell
$env:DEVECO_CLI_STUDIO_PATH = 'D:\Harmony\IDE\DevEco Studio'
devecocli build
devecocli check lint
devecocli run --device '127.0.0.1:5555'
devecocli ui layout --device '127.0.0.1:5555'
```

- build/run：CompileArkTS、资源编译、HAP 打包通过，并在 Mate 70 Pro / HarmonyOS 6.0.0.48（API 20）模拟器安装及启动成功。
- lint：0 错误，4 条 avoid-overusing-custom-component-check 警告，分别针对任务清单明确拆出的 MessageList、MessageItem、Composer、RequestStatus。保留职责边界，未禁用规则；没有收到这四条以外的代码问题。
- 用户已确认不执行跨 SDK 兼容性扫描，不列为待办或验收门槛；仅验证当前 API 20。
- emulator list：CLI 子命令要求 Studio 6.1.0；使用 6.0 Studio 自带 Emulator 启动已有 API 20 实例，无下载或升级。
- 未配置签名时构建产生 unsigned HAP，此模拟器已成功安装。真机签名和发布证书不属于此次验收。
- 本机缺少 wmic 会产生 Hvigor 环境警告，但构建与测试正常结束。

本地 Hypium 单元测试通过 Studio 自带 Hvigor 执行：

```powershell
$env:DEVECO_SDK_HOME = 'D:\Harmony\IDE\DevEco Studio\sdk'
$env:NODE_HOME = 'D:\Harmony\IDE\DevEco Studio\tools\node'
& 'D:\Harmony\IDE\DevEco Studio\tools\hvigor\bin\hvigorw.bat' --mode module -p product=default -p 'module=entry@default' test
```

实测 11 项通过、0 失败、0 错误（10 项 ChatState/契约检查 + 1 项模板），包括此次新增的错误详情保留及缺省详情检查。检查跨页重叠、相同正文不同 ID、旧消息空归属、待确认转正式、加载失败重试、活跃任务阻止发送、低版本忽略、部分成果保留、分页/重新加载草稿保留及卸载后丢弃加载结果。

结果文件：`entry/.test/default/intermediates/test/coverage_data/test_result.txt`；HTML 报告位于 `entry/.test/default/outputs/test/reports/index.html`。这些是生成产物，不提交 Git。

## 设备检查与限制

已检查初始消息显示、空草稿发送禁用、输入后发送启用、点击模拟发送保留草稿、键盘展开时标题与输入区可见、列表滚动及回到最新。历史分页采用稳定 ID 和 maintainVisibleContentPosition 保持阅读位置；新增消息仅在跟随底部时自动滚动。

`.test/` 保存本机设备截图，供复核，Git 忽略。此次只在上述模拟器验收，未声称已覆盖真机、多窗口、长时间运行或 M2–M4 的交互闭环。


## M2 实现与内容组件选择

M2 包含 UI-VIEW-02、UI-SOURCE-01、UI-SEND-01。以上 M1 检查记录保留为历史证据，本节说明当前行为。

采用 API 20 自带 Text/Span、Scroll、bindSheet，未引入第三方渲染包。当前 entry 依赖清单为空，已安装 SDK 的原生组件声明中未发现 Markdown 组件；本阶段没有经过 API 20/V2 验证的第三方整套组件可直接复用。因此按任务允许的最小原生方案实现固定语法子集，并以本机编译和设备展示验证，不宣称穷尽或验证了第三方库。`entry/oh-package.json5` 与锁文件无需变更。

参考 [OpenHarmony Text/Span 文档](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-basic-components-span.md)，最终接口以本机 API 20 SDK 编译结果为准。`UIAbilityContext.openLink` 的 SDK 声明 since 12，当前 API 20 构建通过；外部打开统一经 SourceLink，限定 http/https。

- `MarkdownParser.ets`：ATX 标题、段落、有序/无序列表、单层粗体/斜体、行内代码、简单链接、反引号/波浪号围栏代码。保留代码缩进和空行；不完整围栏保留原文。复杂嵌套行内语法、表格、图片和 HTML 不作完整 Markdown 解释，保留可读文字。没有 HTML/WebView/脚本执行、流式拼接或代码执行。
- `CodeBlock.ets`：等宽字体、长行横向滚动、超过 8 行可展开。状态由组件拥有，消息列表按 messageId、块按稳定位置标识；重复正式消息不会重建内容或折叠代码。
- `SourceSheet.ets`：使用消息自带 citations，保持顺序、原文 URL 与历史版本信息，不检索、不改绑、不推断行内证据。日期为空显示未知，证据片段可展开；没有 citations 就没有来源按钮。
- `InputText.ets`：统一码点计数及空白/超限校验。发送即固定 requestId/原文并显示待确认项；新的草稿不会因迟到接受或拒绝被覆盖。明确拒绝时仅在没有后续编辑的情况下恢复原文；未知结果保留待确认状态，禁止再次发送。
- `ChatViewModel.ets`：进展仅作提示，message_saved 立即合并完整消息，终态合并全部成果并结束等待。已失败任务保留成果；completed 仅表示本次处理结束。已结束的接受响应或同步终态快照都不继续等待事件。观察释放不调用 stop。

## M2 模拟场景与复核

在 `ChatDependencies.ets` 创建的 FakeChatService 上设置 `replyScenario`，可选 normal、clarification、no_evidence、lesson_question、partial_failure、duplicate_events、terminal_snapshot、rejected。场景由开发配置指定，完全不解析用户文字来模拟业务路由。默认 normal 每 900ms 推进一个完整事件，不逐字生成。测试设置 `autoAdvance = false` 后调用 `advance()`，不依赖实际等待时间；网络断开用 `failConnection()`。

UI 代码新增范围还包括 MessageList 的来源/链接错误回调传递、ChatService 回调的显式函数类型（满足 ArkTS 对对象字面量的限制）、独立解析/输入/模拟回复文件。未更改 Agent 公共 DTO 字段或业务规则。

M2 验收：当前 API 20 ArkTS build 通过；Code Linter 0 错误、6 条组件拆分建议（M1 的 4 条加 CodeBlock、SourceSheet），未关闭规则。Hypium 共 26 项通过，0 失败/错误；包含已完成 M1 的 11 项与本次 15 项。测试覆盖 Unicode 边界、原文、双击发送、明确拒绝与未知接受、后续草稿、澄清/无证据、分次保存、部分失败、重复事件、直接终态与观察释放，以及 Markdown 的不完整输入和非 Web 链接拒绝。

模拟器实测发送和完整回复、代码展开/横向滚动、滚动后返回最新且展开状态保留、来源弹层/证据片段、键盘布局。点击 http/https 原文后系统显示“暂无可用打开方式”，应用显示失败说明；这一设备缺少可用打开方式，未声称浏览器成功展示网页。成功打开需要在装有浏览器的设备复核。截图保存在 Git 忽略目录 `.test/m2-*.png`。

M2 全部为模拟服务交互；真实 HTTP/SSE 在 M3，停止、重试、初始化活跃任务恢复与持久恢复在 M4。没有新增需要业务层协商的事项。

## M3 HTTP/SSE 适配与运行配置

M3 客户端实现已完成：ChatApi 通过 RcpTransport 提供 HTTP 请求，TaskSubscription 负责 SSE 观察。编译依据是本机 API 20 的 RemoteCommunicationKit 声明（@hms.collaboration.rcp.d.ts），实际 RCP 请求和 UTF-8 分块消息已在 API 20 模拟器与协议替身之间验证。真实 Agent 聊天 HTTP/API 尚未交付，不将此结果称为 Agent 联调通过。

在 chat/bootstrap/ChatConfig.ets 中设置 mode、baseUrl、requestTimeoutMs、streamIdleTimeoutMs。提交默认是 fake 和空地址；选择 real 后必须填设备可访问、包含 /api/v1 的 http/https 地址。ChatDependencies 不会因错误回退到 FakeChatService。页面标明“模拟预览”或“在线服务”；“在线服务”只描述通信模式，不表示模型、数据库或 Agent 已验收。客户端不包含模型密钥。

- RcpTransport 使用 Session.fetch(Request)，每个操作独立拥有 Session；普通请求在 finally 关闭，流式观察释放只取消当前请求。ChatApi.close() / RcpTransport.close() 提供整体取消入口；应用前后台与依赖销毁的统一所有权仍由 M4 接入。
- 普通请求默认 15 秒；SSE 无整体传输时限，连接超时 15 秒、空闲超时 90 秒，服务端应在空闲时限内提供心跳。全部关闭自动重定向，不执行隐式 POST 重试；取消已发送 POST 不证明服务端未接受。
- HTTP 成功和失败外壳均校验。已约定 HTTP 拒绝保留 code/message/details.existingTaskId；写请求的错误外壳还必须对应原 requestId。网络失败、非法 JSON、身份不匹配或未知响应保留 network 类别，并用 protocol_error 区分协议问题。HTTP 200 的 failed 任务和 202 的终态发送响应均正常返回。
- ResponseValidation 独立校验 ID、安全整数、枚举、UTC 时间、消息/引用/定位与 task；允许 legacy/local 空归属，首版 draftId=null、previews=[]。字段校验不会重新检索来源或推断学习动作。
- HTTP 正文最多 8 MiB；SSE 单帧及未完成行最多 1 Mi 个 UTF-16 单元，UTF-8 解码最多保留一个未完成码点。超过边界报告协议异常，不截断正式内容。SSE 支持跨字节中文/emoji、BOM、CRLF/LF/CR、注释心跳和多行 data。
- SSE 先校验 200 与 text/event-stream，再消费字节；第一条已知事件必须是 task_snapshot。连接内 id 去重和缺口检查覆盖未知事件，但未知事件正文不解析。已知事件非法则核对；未知进展 phase 按已确认契约降级为 processing。
- 缺口仅自动建立一次全新快照订阅，不发 Last-Event-ID；再次缺口或普通断流通知 ViewModel 进入 checking。订阅代次隔离旧回调，初始终态快照即可释放连接；EOF 永远不生成任务终态。
- ViewModel 独立合并正式消息，使用 message_saved.taskRevision 防止旧 HTTP/事件快照更新任务状态；同 ID 消息不重复，不跨任务比较 revision。停止、失败重试、断线按钮操作和重开恢复仍属于 M4。

## M3 可重复协议检查

本地测试沿用前述 Hvigor test 命令，新增 ChatApi、SseDecoder、TaskEvents，共 51 项通过（原 26 项 + M3 25 项）。API 20 构建通过，Code Linter 0 错误、原有 6 条组件拆分建议。测试替身直接注入 ChatTransport，不替代 SDK 编译及设备传输检查。

设备网络检查使用 docs/testing/chat-protocol-server.mjs，它只提供固定协议响应，没有 Agent、模型、学习规则或持久数据库。运行：

~~~powershell
node docs/testing/chat-protocol-server.mjs normal
# 或 eof：保存完整消息后断流；failed：保存后发送失败终态。
~~~

本次使用已有 Mate 70 Pro / HarmonyOS 6.0.0.48（API 20）模拟器。明确建立设备到主机的端口转发后，临时 real 配置才使用 http://127.0.0.1:8787/api/v1：

~~~powershell
& 'D:/Harmony/IDE/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe' -t 127.0.0.1:5555 rport tcp:8787 tcp:8787
~~~

这里的 localhost 由显式转发成立；真机或无转发环境应填主机可达地址，不照抄。协议替身仅监听主机 127.0.0.1，普通局域网真机连接需要另行配置可达接口。

本次设备检查确认 GET 聊天、POST 接受、SSE 保存中文/emoji 完整消息及正常终态；另以 eof 场景确认已保存内容仍显示，页面进入“正在确认上次处理结果”，不解除发送限制。截图保存在 Git 忽略目录 .test/m3-rcp-*.png。检查结束恢复 fake/空地址默认值，不提交临时端口地址。

真实联调待 Agent 层交付：契约 v0.3 的聊天读取/接受/查询与 SSE 初始快照、消息保存、公开终态接口及启动方式。当前没有新增需要 UI 与业务层直接协商的事项。M3 实现已交付，但完整阶段的真实 Agent 连通门槛仍未关闭；M4 不因协议替身通过而视为完成。
