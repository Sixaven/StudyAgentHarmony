import { ChatMessage, Citation, MessagePage } from '../contracts/ChatMessage';
import { ChatSnapshot } from '../contracts/ChatService';
import { TaskSnapshot } from '../contracts/ChatTask';

export function sampleMessage(id: string, sequence: number, content: string,
  role: 'user' | 'assistant' = 'assistant', requestId: string | null = null): ChatMessage {
  return {
    messageId: id, chatId: 'demo-chat', sequence: sequence, role: role,
    format: role === 'user' ? 'plain' : 'markdown', content: content,
    createdAt: '2026-09-06T00:00:00.000Z', requestId: requestId, taskId: null,
    origin: 'local', draftId: null, citations: []
  };
}

export function sampleCitation(id: string): Citation {
  return {
    citationId: id, label: id, title: '模拟资料：Agent 的基本组成',
    originalUrl: 'https://example.com/agent', sourceType: 'official_documentation',
    publishedAt: null, text: '工具提供受控能力，状态记录执行进度。',
    documentVersionId: 'demo-version-1', chunkId: 'demo-chunk-' + id,
    location: { sectionPath: ['Agent', '工具与状态'], start: 0, end: 23 }
  };
}

export function sampleTask(status: 'running' | 'stopping' | 'completed' | 'failed' | 'cancelled',
  revision: number = 1): TaskSnapshot {
  return {
    chatId: 'demo-chat', taskId: 'demo-task', requestId: 'demo-request',
    userMessageId: 'demo-user', revision: revision, status: status,
    outcome: null, runtimeReason: null, reason: null, error: null,
    savedMessages: [], previews: [], canRetry: status === 'failed'
  };
}

export function initialChat(): ChatSnapshot {
  const user = sampleMessage('demo-user', 2, '我想了解 Agent 的基本组成。', 'user', 'demo-request');
  user.origin = 'interactive';
  user.taskId = 'demo-task';
  const reply = sampleMessage('demo-reply', 3,
    '我们从一个小问题开始。\n\nAgent 会根据目标选择下一步行动。你可以先把它理解为三个部分：\n\n模型：理解问题，决定下一步。\n工具：查询资料，执行受控操作。\n状态：记录已经发生的事情。\n\n想一想：如果没有工具，模型还能做什么？');
  reply.citations = [sampleCitation('1'), sampleCitation('2')];
  const task = sampleTask('completed', 3);
  task.outcome = 'reply';
  task.savedMessages = [user, reply];
  return { chatId: 'demo-chat', messages: [user, reply], olderCursor: 'demo-older',
    activeTask: null, latestTask: task };
}

export function olderPage(): MessagePage {
  const legacy = sampleMessage('demo-legacy', 1, '欢迎回来。这里会保留已经保存的学习内容。');
  legacy.origin = 'legacy';
  return { messages: [legacy, initialChat().messages[0]], olderCursor: null };
}

export function partialFailure(): TaskSnapshot {
  const task = sampleTask('failed', 5);
  task.savedMessages = [sampleMessage('demo-code', 4, '已保存的示例：\n\n```ts\nconst tools = [search];\n```')];
  task.error = { code: 'model_timeout', message: '本次生成未完成，已保存的内容仍可阅读。' };
  return task;
}
