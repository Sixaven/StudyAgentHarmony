import { MessagePage } from '../contracts/ChatMessage';
import { AcceptedMessage, ChatObserver, ChatService, ChatServiceError, ChatSnapshot,
  ChatSubscription, RequestResult, SendRequest } from '../contracts/ChatService';
import { ChatEvent, TaskSnapshot } from '../contracts/ChatTask';
import { initialChat, olderPage, partialFailure, sampleTask } from './ChatFixtures';

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

// Explicit controls keep timing deterministic. Network replay/stop races can be added
// here in later milestones without putting learning rules in the client.
export class FakeChatService implements ChatService {
  scenario: FakeScenario;
  private observers: ChatObserver[] = [];

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
    return snapshot;
  }

  async loadOlder(cursor: string): Promise<MessagePage> {
    if (cursor !== 'demo-older') {
      throw new ChatServiceError('rejected', 'invalid_input', '无法加载更早的消息。');
    }
    return olderPage();
  }

  async send(request: SendRequest): Promise<AcceptedMessage> {
    throw new ChatServiceError('rejected', 'demo_not_implemented', '当前为界面预览，发送交互将在下一阶段接入。');
  }

  async findRequest(requestId: string): Promise<RequestResult> {
    throw new ChatServiceError('rejected', 'not_found', '尚无对应请求。');
  }

  async getTask(taskId: string): Promise<TaskSnapshot> {
    const snapshot = await this.loadChat();
    const task = snapshot.activeTask ?? snapshot.latestTask;
    if (task === null || task.taskId !== taskId) {
      throw new ChatServiceError('rejected', 'not_found', '未找到对应任务。');
    }
    return task;
  }

  subscribe(taskId: string, observer: ChatObserver): ChatSubscription {
    this.observers.push(observer);
    return new FakeSubscription(() => {
      this.observers = this.observers.filter((item: ChatObserver) => item !== observer);
    });
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

  async stop(taskId: string, requestId: string): Promise<TaskSnapshot> {
    throw new ChatServiceError('rejected', 'demo_not_implemented', '停止交互尚未接入。');
  }

  async retry(taskId: string, requestId: string): Promise<TaskSnapshot> {
    throw new ChatServiceError('rejected', 'retry_not_allowed', '当前预览不支持任务重试。');
  }
}
