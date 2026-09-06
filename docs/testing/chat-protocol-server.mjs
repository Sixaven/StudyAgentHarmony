// Protocol fixture only. No Agent, model, business persistence, or learning rules.
// node docs/testing/chat-protocol-server.mjs [normal|eof|failed]
import { createServer } from 'node:http';
import { randomUUID } from 'node:crypto';

const scenario = process.argv[2] ?? 'normal';
if (!['normal', 'eof', 'failed'].includes(scenario)) {
  throw new Error('Expected normal, eof, or failed');
}
const messages = [];
const tasks = new Map();
const requests = new Map();
let latest = null;
let sequence = 0;

function message(role, content, requestId, taskId) {
  const saved = {
    messageId: randomUUID(), chatId: 'protocol-chat', sequence: ++sequence,
    role, format: role === 'user' ? 'plain' : 'markdown', content,
    createdAt: new Date().toISOString(), requestId, taskId,
    origin: 'interactive', draftId: null, citations: []
  };
  messages.push(saved);
  return saved;
}

function json(response, status, data) {
  response.writeHead(status, { 'Content-Type': 'application/json' });
  response.end(JSON.stringify({ data }));
}

function event(id, name, task, extra) {
  return Buffer.from('id: ' + id + '\r\nevent: ' + name + '\r\ndata: ' +
    JSON.stringify({ chatId: task.chatId, taskId: task.taskId,
      requestId: task.requestId, ...extra }) + '\r\n\r\n');
}

const server = createServer(async (request, response) => {
  const url = new URL(request.url, 'http://127.0.0.1');
  console.log(request.method, url.pathname);
  if (request.method === 'GET' && url.pathname === '/api/v1/chat') {
    const activeTask = latest?.status === 'running' ? latest : null;
    json(response, 200, { chatId: 'protocol-chat', messages, olderCursor: null,
      activeTask, latestTask: latest });
    return;
  }
  if (request.method === 'POST' && url.pathname === '/api/v1/chat/messages') {
    let body = '';
    for await (const chunk of request) {
      body += chunk;
      if (body.length > 65536) {
        response.writeHead(413).end();
        return;
      }
    }
    const input = JSON.parse(body);
    if (requests.has(input.requestId)) {
      json(response, 200, requests.get(input.requestId));
      return;
    }
    const taskId = randomUUID();
    const saved = message('user', input.text, input.requestId, taskId);
    const task = {
      chatId: 'protocol-chat', taskId, requestId: input.requestId,
      userMessageId: saved.messageId, revision: 1, status: 'running',
      outcome: null, runtimeReason: null, reason: null, error: null,
      savedMessages: [saved], previews: [], canRetry: false
    };
    tasks.set(taskId, task);
    latest = task;
    requests.set(input.requestId, { userMessage: saved, task });
    json(response, 202, { userMessage: saved, task });
    return;
  }
  const match = url.pathname.match(/^\/api\/v1\/tasks\/([^/]+)(\/events)?$/);
  if (match && tasks.has(match[1])) {
    const task = tasks.get(match[1]);
    if (!match[2]) {
      json(response, 200, task);
      return;
    }
    response.writeHead(200, { 'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache', Connection: 'keep-alive' });
    response.flushHeaders();
    response.write(event(1, 'task_snapshot', task, { task }));
    if (task.status !== 'running') {
      response.end();
      return;
    }
    const timer = setTimeout(() => {
      const saved = message('assistant', '## RCP 协议检查\n\n中文与 emoji 😀 已完整保存。\n\n这是协议替身回复。',
        task.requestId, task.taskId);
      task.savedMessages.push(saved);
      task.revision = 2;
      const bytes = event(2, 'message_saved', task, { message: saved, taskRevision: 2 });
      // Force a UTF-8 character across writes; TCP may additionally regroup chunks.
      const split = bytes.indexOf(Buffer.from('中文')) + 1;
      response.write(bytes.subarray(0, split));
      const rest = setTimeout(() => {
        response.write(bytes.subarray(split));
        if (scenario === 'eof') {
          response.end();
          return;
        }
        task.status = scenario === 'failed' ? 'failed' : 'completed';
        task.canRetry = scenario === 'failed';
        task.outcome = 'reply';
        task.revision = 3;
        if (scenario === 'failed') {
          task.error = { code: 'model_timeout', message: '协议替身：保存后失败。' };
        }
        response.write(event(3, 'task_finished', task, { task }));
        response.end();
      }, 100);
      response.on('close', () => { clearTimeout(rest); });
    }, 600);
    response.on('close', () => { clearTimeout(timer); });
    return;
  }
  response.writeHead(404, { 'Content-Type': 'application/json' });
  response.end(JSON.stringify({ error: { code: 'not_found', message: '协议替身未实现此路径。' } }));
});
server.listen(8787, '127.0.0.1', () => {
  console.log('PROTOCOL FIXTURE ONLY:', scenario, 'http://127.0.0.1:8787/api/v1');
});
