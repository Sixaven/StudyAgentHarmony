import { ChatMessage } from '../contracts/ChatMessage';
import { ChatService } from '../contracts/ChatService';
import { isActiveTask, TaskSnapshot } from '../contracts/ChatTask';
import { ChatState } from './ChatState';
import { mergeMessages, remainingPending } from './MessageCollection';

export class ChatViewModel {
  readonly state: ChatState = new ChatState();
  private service: ChatService;
  private loadGeneration: number = 0;

  constructor(service: ChatService) {
    this.service = service;
  }

  async load(): Promise<void> {
    const generation = ++this.loadGeneration;
    this.state.phase = 'loading';
    this.state.initialLoadFailed = false;
    this.state.notice = '';
    try {
      const snapshot = await this.service.loadChat();
      if (generation !== this.loadGeneration) {
        return;
      }
      this.merge(snapshot.messages);
      this.state.olderCursor = snapshot.olderCursor;
      this.state.task = null;
      if (snapshot.latestTask !== null) {
        this.merge(snapshot.latestTask.savedMessages);
      }
      this.applyTask(snapshot.activeTask ?? snapshot.latestTask);
      this.state.initialized = true;
      // M1 can display an active snapshot, but does not yet observe its lifecycle.
      if (isActiveTask(this.state.task)) {
        this.state.phase = 'checking';
      }
    } catch {
      if (generation !== this.loadGeneration) {
        return;
      }
      this.state.phase = 'failed';
      this.state.initialLoadFailed = true;
    }
  }

  dispose(): void {
    this.loadGeneration++;
  }

  setDraft(text: string): void {
    this.state.draft = text;
  }

  merge(messages: ChatMessage[]): void {
    this.state.messages = mergeMessages(this.state.messages, messages);
    this.state.pending = remainingPending(this.state.pending, this.state.messages);
  }

  applyTask(task: TaskSnapshot | null): void {
    if (task === null) {
      this.state.task = null;
      this.state.phase = 'ready';
      return;
    }
    const current = this.state.task;
    if (current !== null && current.taskId === task.taskId && current.revision >= task.revision) {
      return;
    }
    this.merge(task.savedMessages);
    this.state.task = task;
    if (task.status === 'running') {
      this.state.phase = 'processing';
    } else if (task.status === 'stopping') {
      this.state.phase = 'stopping';
    } else if (task.status === 'failed') {
      this.state.phase = 'failed';
    } else {
      this.state.phase = 'ready';
    }
  }

  async loadOlder(): Promise<void> {
    const cursor = this.state.olderCursor;
    if (cursor === null || this.state.loadingOlder) {
      return;
    }
    this.state.loadingOlder = true;
    try {
      const page = await this.service.loadOlder(cursor);
      this.merge(page.messages);
      this.state.olderCursor = page.olderCursor;
    } catch {
      this.state.notice = '更早的消息暂时无法加载，请重试。';
    } finally {
      this.state.loadingOlder = false;
    }
  }

  requestSend(): void {
    if (this.state.canSend) {
      this.state.notice = '当前为界面预览，发送交互将在下一阶段接入。';
    }
  }

  requestStop(): void {
    this.state.notice = '停止交互尚未接入。';
  }
}
