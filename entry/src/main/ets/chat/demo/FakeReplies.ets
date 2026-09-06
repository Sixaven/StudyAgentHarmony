import { TaskSnapshot } from '../contracts/ChatTask';
import { ChatMessage } from '../contracts/ChatMessage';
import { sampleCitation, sampleMessage } from './ChatFixtures';

export type ReplyScenario = 'normal' | 'clarification' | 'no_evidence' | 'lesson_question' |
  'partial_failure' | 'duplicate_events' | 'terminal_snapshot' | 'rejected';

export function fakeReplies(scenario: ReplyScenario, taskId: string, requestId: string,
  sequence: number): ChatMessage[] {
  let text = '## 从一个最小 Agent 开始\n\n**模型**选择行动，*工具*提供能力，状态保存执行进度。\n\n' +
    '- 读取目标\n- 选择受控工具\n- 保存结果\n\n' +
    '下面是不会实际执行的示例：\n\n```ts\ninterface AgentState {\n  goal: string;\n  steps: string[];\n}\n\n' +
    'const state: AgentState = {\n  goal: "学习 Agent 的基本组成",\n  steps: []\n};\n\n' +
    '// 这是一行用于检查横向阅读的较长代码：只展示示例，不调用模型、不访问工具、不改变学习状态。\n' +
    'state.steps.push("读取目标");\n```\n\n' +
    '你可以阅读[示例链接](https://example.com/agent)。';
  if (scenario === 'clarification') {
    text = '你想先了解 Agent 的组成，还是工具调用的过程？请补充一下你的目标。';
  } else if (scenario === 'no_evidence') {
    text = '当前资料中没有找到足够证据。你可以补充关键词或换一个问题。';
  }
  const reply = sampleMessage(taskId + '-reply', sequence, text, 'assistant', requestId);
  reply.taskId = taskId;
  reply.origin = 'interactive';
  if (scenario !== 'clarification' && scenario !== 'no_evidence') {
    reply.citations = [sampleCitation('1'), sampleCitation('2')];
  }
  if (scenario === 'lesson_question') {
    const question = sampleMessage(taskId + '-question', sequence + 1,
      '想一想：为什么保存工具结果后，还需要让模型决定下一步？', 'assistant', requestId);
    question.taskId = taskId;
    question.origin = 'interactive';
    return [reply, question];
  }
  return [reply];
}

export function copyTask(task: TaskSnapshot): TaskSnapshot {
  return {
    chatId: task.chatId, taskId: task.taskId, requestId: task.requestId,
    userMessageId: task.userMessageId, revision: task.revision, status: task.status,
    outcome: task.outcome, runtimeReason: task.runtimeReason, reason: task.reason,
    error: task.error, savedMessages: task.savedMessages.slice(), previews: [], canRetry: task.canRetry
  };
}
