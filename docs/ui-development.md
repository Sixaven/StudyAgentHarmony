# UI 开发与 M1 验收

2026-09-06。M1 的原生页面、客户端契约与状态归并已实现并在 API 20 模拟器运行；发送闭环、Markdown/来源、真实 HTTP/SSE、停止/重试/持久恢复按后续 Milestone 推进。

## 工程与入口

- DevEco Studio 6.0.0.858，HarmonyOS 6.0.0（API 20），phone，ArkTS / ArkUI 状态管理 V2。
- 页面：`entry/src/main/ets/pages/Index.ets`。依赖组装：`chat/bootstrap/ChatDependencies.ets`，组件不创建服务。
- `createChatViewModel()` 默认使用 `FakeChatService('ready')`。开发时可传入 `empty`、`loading_error`、`running`、`partial_failure`。
- 场景选择仅在组装代码里修改，页面不放场景选择器。顶部“模拟预览”表明当前数据为样例。
- M1 输入可编辑，发送按钮校验空白和忙碌状态；点击只提示预览范围且保留草稿，不调用未实现的发送接口。停止回调亦不伪造成功。
- `running` 初始快照进入核对中，禁止发送；订阅和恢复流程后续接入。
- `FakeChatService.emit()` / `failConnection()` 可受控推进观察者；dispose 仅解除观察，不等于停止任务。模拟服务未实现的方法明确拒绝，不能作为真实能力验收。

参考规划库 `D:/VsCode/Project/StudyAgent/docs/tasks/ui/` 下的任务清单、契约 v0.3 及 `prototype/` 原型。M1 按原型落实配色、阅读版式、用户气泡、底部输入；正文暂为纯文本。明暗主题颜色放在 base/dark 资源中，不仿造系统状态栏。键盘用 API 20 支持的 `KeyboardAvoidMode.RESIZE`，保持标题和输入区可见，列表收缩。

## 数据与协议样例

客户端 DTO 按已确认 UI/API 契约声明；尚未接入 HTTP 服务，以下只是契约样例。UI 不推断学习动作、不访问业务层，也不保存掌握度。

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

2000 按 Unicode 码点计数，原文不 trim 或改写。该服务端约束在发送阶段实现，不能直接用 TextArea.maxLength 的 UTF-16 语义替代。

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
