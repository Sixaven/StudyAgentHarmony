import { createServer, request } from 'node:http';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';

// Test-only fault host. All /api/v1 responses come from the actual backend.
if (!process.argv[2] || !process.argv[3]) {
  throw new Error('Usage: node real-chat-server.mjs <backend-root> <isolated-test-directory>');
}
const backend = resolve(process.argv[2]);
const directory = resolve(process.argv[3]);
mkdirSync(directory, { recursive: true });
const load = (path) => import(pathToFileURL(join(backend, 'dist', path)));
const { openBusinessSystem } = await load('src/bootstrap/business.js');
const { openChatApi } = await load('src/bootstrap/chat/api.js');
const { loadConfig } = await load('src/bootstrap/config.js');
const { createChatScript } = await load('fixtures/agent/chat-script.js');
const { persistentSource, publishAgentFixture } = await load(
  'scripts/support/agent/persistent-fixture.js',
);
const controlPath = join(directory, 'controls.json');
function controls() {
  try {
    return JSON.parse(readFileSync(controlPath, 'utf8'));
  } catch {
    return {};
  }
}
function consume(key) {
  const value = controls();
  if (!value[key]) {
    return false;
  }
  delete value[key];
  writeFileSync(controlPath, JSON.stringify(value));
  return true;
}
const business = {
  config: loadConfig({
    STUDY_DATABASE_PATH: join(directory, 'studyagent.sqlite'),
    STUDY_RAW_FILES_PATH: join(directory, 'raw'),
  }),
  sources: [persistentSource],
};
const system = openBusinessSystem(business);
publishAgentFixture(system);
await system.close();
const script = createChatScript();
const api = await openChatApi({
  userId: 'ui-m4',
  port: 3001,
  business,
  taskTimeoutMs: 180000,
  model: async (context, signal) => {
    const flags = controls();
    if (flags.holdRouting && context.system.startsWith('CHAT_ROUTER')) {
      return new Promise(() => {});
    }
    const saved = (name) =>
      context.messages.some(
        (m) =>
          m.role === 'tool' &&
          m.observation.toolName === name &&
          m.observation.result.status === 'success',
      );
    if (flags.failAfterEvaluation && saved('submit_evaluation')) {
      throw new Error('UI M4 injected failure after committed evaluation');
    }
    if (flags.holdAfterQuestion && saved('save_step')) {
      return new Promise(() => {});
    }
    await delay(flags.delayMs ?? 700, undefined, { signal });
    return script(context, signal);
  },
});
const proxy = createServer((incoming, outgoing) => {
  console.log(incoming.method, incoming.url);
  let dropKey = 'loseSend';
  if (incoming.url.endsWith('/stop')) {
    dropKey = 'loseStop';
  } else if (incoming.url.endsWith('/retry')) {
    dropKey = 'loseRetry';
  }
  const drop = incoming.method === 'POST' && consume(dropKey);
  const upstream = request(
    {
      host: '127.0.0.1',
      port: 3001,
      path: incoming.url,
      method: incoming.method,
      headers: incoming.headers,
    },
    (response) => {
      if (drop) {
        response.resume();
        response.on('end', () => {
          console.log('DROPPED', dropKey);
          outgoing.destroy();
        });
        return;
      }
      outgoing.writeHead(response.statusCode, response.headers);
      response.on('data', (chunk) => {
        outgoing.write(chunk);
        if (
          incoming.url.endsWith('/events') &&
          chunk.toString().includes('event: message_saved') &&
          consume('disconnectAfterSaved')
        ) {
          setTimeout(() => outgoing.destroy(), 100);
        }
      });
      response.on('end', () => outgoing.end());
      outgoing.on('close', () => upstream.destroy());
    },
  );
  upstream.on('error', () => outgoing.destroy());
  incoming.pipe(upstream);
});
await new Promise((resolve) => proxy.listen(3000, '127.0.0.1', resolve));
console.log('READY: real Agent/HTTP/SSE/SQLite, script model; proxy 3000, backend 3001');
process.on('SIGINT', async () => {
  proxy.closeAllConnections();
  proxy.close();
  await api.close();
  process.exit(0);
});
