import { copyTask, fakeReplies, ReplyScenario } from './FakeReplies';
import { ChatMessage, MessagePage } from '../contracts/ChatMessage';
import { AcceptedMessage, ChatObserver, ChatService, ChatServiceError, ChatSnapshot,
  ChatSubscription, RequestResult, SendRequest } from '../contracts/ChatService';
import { ChatEvent, isActiveTask, TaskSnapshot } from '../contracts/ChatTask';
import { initialChat, olderPage, partialFailure, sampleTask, sampleMessage } from './ChatFixtures';

export type FakeScenario = 'ready' | 'empty' | 'loading_error' | 'running' | 'partial_failure';

class FakeSubscription implements ChatSubscription {
  private release: () => void;

  constructor(release: () => void) {
    this.release = release;
  }

  dispose(): void {
    this.release();
  }
}

// Explicit controls model network/stop races without putting learning rules in the client.
export class FakeChatService implements ChatService {
  scenario: FakeScenario;
  loseNextResponse: boolean = false;
  stopCompletesFirst: boolean = false;
  stopCount: number = 0;
  retryCount: number = 0;
  private requests: Map<string, RequestResult> = new Map();
  private bodies: Map<string, string> = new Map();
  private tasks: Map<string, TaskSnapshot> = new Map();
  private successors: Map<string, string> = new Map();
  private observers: ChatObserver[] = [];
  replyScenario: ReplyScenario = 'normal';
  autoAdvance: boolean = true;
  sendCount: number = 0;
  private latest: TaskSnapshot | null = null;
  private messages: ChatMessage[] = [];
  private replies: ChatMessage[] = [];
  private step: number = 0;
  private eventNumber: number = 0;

  constructor(scenario: FakeScenario = 'ready') {
    this.scenario = scenario;
  }

  async loadChat(): Promise<ChatSnapshot> {
    if (this.scenario === 'loading_error') {
      throw new ChatServiceError('network', 'unavailable', '暂时无法加载，请重试。');
    }
    const snapshot = initialChat();
    if (this.scenario === 'empty') {
      snapshot.messages = [];
      snapshot.olderCursor = null;
      snapshot.latestTask = null;
    } else if (this.scenario === 'running') {
      snapshot.activeTask = sampleTask('running');
      snapshot.latestTask = snapshot.activeTask;
    } else if (this.scenario === 'partial_failure') {
      snapshot.latestTask = partialFailure();
    }
    if (this.latest !== null) {
      snapshot.messages = snapshot.messages.concat(this.messages);
      snapshot.latestTask = this.latest;
      snapshot.activeTask = isActiveTask(this.latest) ? this.latest : null;
    }
    return snapshot;
  }

  async loadOlder(cursor: string): Promise<MessagePage> {
    if (cursor !== 'demo-older') {
      throw new ChatServiceError('rejected', 'invalid_input', '无法加载更早的消息。');
    }
    return olderPage();
  }

  async send(request: SendRequest): Promise<AcceptedMessage> {
    const replay = this.requests.get(request.requestId);
    if (replay !== undefined) {
      if (replay.kind !== 'send' || this.bodies.get(request.requestId) !== request.text) {
        throw new ChatServiceError('rejected', 'request_conflict', '同一请求内容不一致。');
      }
      const task = await this.getTask(replay.task.taskId);
      return { userMessage: task.savedMessages[0], task: task };
    }
    if (isActiveTask(this.latest)) {
      throw new ChatServiceError('rejected', 'busy', '请等待当前任务结束。');
    }
    this.sendCount++;
    this.invalidateLatest();
    if (this.replyScenario === 'rejected') {
      throw new ChatServiceError('rejected', 'invalid_input', '模拟服务未接受此消息，请修改后发送。');
    }
    const task = sampleTask('running');
    task.taskId = 'demo-task-' + this.sendCount.toString();
    task.requestId = request.requestId;
    task.userMessageId = task.taskId + '-user';
    const sequence = 10 + this.messages.length;
    const user = sampleMessage(task.userMessageId, sequence, request.text, 'user', request.requestId);
    user.taskId = task.taskId;
    user.origin = 'interactive';
    task.savedMessages = [user];
    this.messages.push(user);
    this.latest = task;
    this.replies = fakeReplies(this.replyScenario, task.taskId, request.requestId, sequence + 1);
    this.step = 0;
    this.requests.set(request.requestId, { requestId: request.requestId, kind: 'send', task: task });
    this.bodies.set(request.requestId, request.text);
    this.tasks.set(task.taskId, task);
    this.maybeLoseResponse();
    return { userMessage: user, task: task };
  }

  async findRequest(requestId: string): Promise<RequestResult> {
    const result = this.requests.get(requestId);
    if (result === undefined) {
      throw new ChatServiceError('rejected', 'not_found', '尚无对应请求。');
    }
    return { requestId: requestId, kind: result.kind, task: await this.getTask(result.task.taskId) };
  }

  async getTask(taskId: string): Promise<TaskSnapshot> {
    if (this.latest !== null && this.latest.taskId === taskId) {
      return this.latest;
    }
    const previous = this.tasks.get(taskId);
    if (previous !== undefined) {
      return previous;
    }
    const snapshot = await this.loadChat();
    const task = snapshot.activeTask ?? snapshot.latestTask;
    if (task === null || task.taskId !== taskId) {
      throw new ChatServiceError('rejected', 'not_found', '未找到对应任务。');
    }
    return task;
  }

  subscribe(taskId: string, observer: ChatObserver): ChatSubscription {
    const filtered: ChatObserver = {
      onEvent: (event: ChatEvent) => {
        if (event.taskId === taskId) {
          observer.onEvent(event);
        }
      },
      onError: (error: ChatServiceError) => observer.onError(error)
    };
    this.observers.push(filtered);
    let timer = -1;
    if (this.latest !== null && this.latest.taskId === taskId) {
      observer.onEvent(this.event('task_snapshot', this.latest));
      if (this.autoAdvance) {
        timer = setInterval(() => { this.advance(); }, 900);
      }
    }
    return new FakeSubscription(() => {
      this.observers = this.observers.filter((item: ChatObserver) => item !== filtered);
      if (timer !== -1) {
        clearInterval(timer);
      }
    });
  }

  private event(kind: 'task_snapshot' | 'task_progress' | 'message_saved' | 'task_finished',
    task: TaskSnapshot): ChatEvent {
    this.eventNumber++;
    return { id: this.eventNumber.toString(), event: kind, chatId: task.chatId,
      taskId: task.taskId, requestId: task.requestId, task: task };
  }

  advance(): void {
    const current = this.latest;
    if (current !== null && current.status === 'stopping') {
      const terminal = copyTask(current);
      terminal.status = 'cancelled';
      terminal.canRetry = true;
      terminal.revision++;
      this.latest = terminal;
      this.tasks.set(terminal.taskId, terminal);
      this.emit(this.event('task_finished', terminal));
      return;
    }
    if (current === null || current.status !== 'running') {
      return;
    }
    if (this.replyScenario === 'terminal_snapshot') {
      const next = copyTask(current);
      next.savedMessages = current.savedMessages.concat(this.replies);
      this.latest = next;
      this.messages = this.messages.concat(this.replies);
      this.finish('task_snapshot');
    } else if (this.step === 0) {
      const progress = this.event('task_progress', current);
      progress.phase = 'searching';
      this.emit(progress);
    } else if (this.step <= this.replies.length) {
      const message = this.replies[this.step - 1];
      // Replace snapshots rather than mutating a previously returned server fact.
      const next = copyTask(current);
      next.revision++;
      next.savedMessages = current.savedMessages.concat([message]);
      this.latest = next;
      this.messages.push(message);
      const saved = this.event('message_saved', next);
      saved.message = message;
      saved.taskRevision = next.revision;
      this.emit(saved);
      if (this.replyScenario === 'duplicate_events') {
        this.emit(saved);
      }
    } else {
      this.finish('task_finished');
    }
    this.step++;
  }

  private finish(kind: 'task_snapshot' | 'task_finished'): void {
    const current = this.latest;
    if (current === null) {
      return;
    }
    const failed = this.replyScenario === 'partial_failure';
    const terminal = copyTask(current);
    terminal.revision++;
    terminal.status = failed ? 'failed' : 'completed';
    terminal.canRetry = failed;
    if (failed) {
      terminal.error = { code: 'model_timeout', message: '后续生成未完成，已保存的内容仍可阅读。' };
    } else if (this.replyScenario === 'clarification') {
      terminal.outcome = 'needs_clarification';
    } else if (this.replyScenario === 'no_evidence') {
      terminal.outcome = 'no_evidence';
    } else {
      terminal.outcome = 'reply';
    }
    this.latest = terminal;
    this.emit(this.event(kind, terminal));
  }

  emit(event: ChatEvent): void {
    for (const observer of this.observers.slice()) {
      observer.onEvent(event);
    }
  }

  failConnection(): void {
    for (const observer of this.observers.slice()) {
      observer.onError(new ChatServiceError('network', 'disconnected', '连接已断开，请重试。'));
    }
  }

  private invalidateLatest(): void {
    if (this.latest !== null) {
      const previous = copyTask(this.latest);
      if (previous.canRetry) {
        previous.canRetry = false;
        previous.revision++;
      }
      this.tasks.set(previous.taskId, previous);
      this.latest = previous;
    }
  }

  private maybeLoseResponse(): void {
    if (this.loseNextResponse) {
      this.loseNextResponse = false;
      throw new ChatServiceError('network', 'disconnected', '响应丢失。');
    }
  }

  async stop(taskId: string, requestId: string): Promise<TaskSnapshot> {
    const replay = this.requests.get(requestId);
    if (replay !== undefined) {
      if (replay.kind !== 'stop' || replay.task.taskId !== taskId) {
        throw new ChatServiceError('rejected', 'request_conflict', '请求身份不一致。');
      }
      return this.getTask(taskId);
    }
    this.stopCount++;
    const task = copyTask(await this.getTask(taskId));
    if (isActiveTask(task)) {
      task.status = 'stopping';
      task.revision++;
      this.latest = task;
    }
    this.requests.set(requestId, { requestId: requestId, kind: 'stop', task: task });
    if (this.stopCompletesFirst) {
      this.finish('task_finished');
    }
    this.maybeLoseResponse();
    return task;
  }

  async retry(taskId: string, requestId: string): Promise<TaskSnapshot> {
    const replay = this.requests.get(requestId);
    if (replay !== undefined) {
      if (replay.kind !== 'retry' || this.bodies.get(requestId) !== taskId) {
        throw new ChatServiceError('rejected', 'request_conflict', '请求身份不一致。');
      }
      return this.getTask(replay.task.taskId);
    }
    const successor = this.successors.get(taskId);
    if (successor !== undefined) {
      throw new ChatServiceError('rejected', 'retry_not_allowed', '该任务已有后续重试。',
        { existingTaskId: successor });
    }
    const original = await this.getTask(taskId);
    if (!original.canRetry || (this.latest !== null && this.latest.taskId !== taskId) ||
      isActiveTask(this.latest)) {
      throw new ChatServiceError('rejected', 'retry_not_allowed', '该任务已不可重试，请查看当前任务。');
    }
    this.retryCount++;
    this.invalidateLatest();
    const task = copyTask(original);
    task.taskId = 'demo-retry-' + this.retryCount.toString();
    task.requestId = requestId;
    task.status = 'running';
    task.canRetry = false;
    task.revision = 1;
    task.error = null;
    this.latest = task;
    this.tasks.set(task.taskId, task);
    this.requests.set(requestId, { requestId: requestId, kind: 'retry', task: task });
    this.bodies.set(requestId, taskId);
    this.successors.set(taskId, task.taskId);
    this.replies = [];
    this.step = 1;
    this.maybeLoseResponse();
    return task;
  }
}
