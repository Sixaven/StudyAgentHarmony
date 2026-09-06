import { ChatMessage } from '../contracts/ChatMessage';
import { util } from '@kit.ArkTS';
import { ChatService, ChatServiceError, ChatSubscription, SendRequest } from '../contracts/ChatService';
import { inputError } from './InputText';
import { ChatEvent, isActiveTask, TaskSnapshot } from '../contracts/ChatTask';
import { ChatState } from './ChatState';
import { mergeMessages, remainingPending } from './MessageCollection';

export class ChatViewModel {
  readonly state: ChatState = new ChatState();
  private service: ChatService;
  private loadGeneration: number = 0;
  private operationGeneration: number = 0;
  private draftRevision: number = 0;
  private subscription: ChatSubscription | null = null;
  private observationGeneration: number = 0;

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
      // Initial active-task recovery is implemented in M4; M2 observes newly accepted sends.
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
    this.operationGeneration++;
    this.releaseObservation();
  }

  setDraft(text: string): void {
    this.draftRevision++;
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
    this.merge(task.savedMessages);
    const current = this.state.task;
    if (current !== null && current.taskId === task.taskId && current.revision >= task.revision) {
      return;
    }
    this.state.task = task;
    this.state.notice = '';
    if (task.status === 'running') {
      this.state.phase = 'processing';
    } else if (task.status === 'stopping') {
      this.state.phase = 'stopping';
    } else if (task.status === 'failed') {
      this.state.phase = 'failed';
      this.state.notice = task.error?.message ?? '';
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

  async requestSend(): Promise<void> {
    const validation = inputError(this.state.draft);
    if (validation !== '') {
      this.state.notice = validation;
      return;
    }
    if (!this.state.canSend) {
      return;
    }
    const request: SendRequest = { requestId: util.generateRandomUUID(true), text: this.state.draft };
    const generation = ++this.operationGeneration;
    const sentDraftRevision = this.draftRevision;
    this.releaseObservation();
    this.state.pending = [{ requestId: request.requestId, text: request.text }];
    this.state.draft = '';
    this.state.phase = 'sending';
    this.state.notice = '';
    try {
      const accepted = await this.service.send(request);
      if (generation !== this.operationGeneration) {
        return;
      }
      this.merge([accepted.userMessage]);
      this.applyTask(accepted.task);
      if (isActiveTask(this.state.task)) {
        this.observe(accepted.task);
      }
    } catch (error) {
      if (generation !== this.operationGeneration) {
        return;
      }
      if (error instanceof ChatServiceError && error.kind === 'rejected') {
        this.state.pending = [];
        this.state.phase = 'ready';
        this.state.notice = error.detail.message;
        // A later edit, including deliberately clearing a draft, always wins.
        if (sentDraftRevision === this.draftRevision) {
          this.state.draft = request.text;
        }
      } else {
        this.state.phase = 'checking';
        this.state.notice = '连接已断开，发送结果尚未确认。';
      }
    }
  }

  private releaseObservation(): void {
    this.observationGeneration++;
    this.subscription?.dispose();
    this.subscription = null;
  }

  private observe(task: TaskSnapshot): void {
    this.releaseObservation();
    const generation = this.observationGeneration;
    const subscription = this.service.subscribe(task.taskId, {
      onEvent: (event: ChatEvent) => {
        if (generation !== this.observationGeneration || event.taskId !== task.taskId ||
          event.chatId !== task.chatId || event.requestId !== task.requestId) {
          return;
        }
        if (event.event === 'message_saved' && event.message !== undefined) {
          this.merge([event.message]);
        } else if (event.event === 'task_snapshot' || event.event === 'task_finished') {
          if (event.task !== undefined && event.task.taskId === task.taskId) {
            this.applyTask(event.task);
            if (!isActiveTask(this.state.task)) {
              this.releaseObservation();
            }
          }
        } else if (event.event === 'task_progress' && this.state.phase === 'processing') {
          if (event.phase === 'searching') {
            this.state.notice = '正在查找相关资料…';
          } else if (event.phase === 'saving') {
            this.state.notice = '正在保存回复…';
          } else {
            this.state.notice = '';
          }
        }
      },
      onError: () => {
        if (generation === this.observationGeneration && isActiveTask(this.state.task)) {
          this.state.phase = 'checking';
          this.state.notice = '连接已断开，已保存的内容仍可阅读。';
          this.releaseObservation();
        }
      }
    });
    // Some adapters deliver the initial (possibly terminal) snapshot synchronously.
    if (generation === this.observationGeneration) {
      this.subscription = subscription;
    } else {
      subscription.dispose();
    }
  }

  requestStop(): void {
    this.state.notice = '停止交互尚未接入。';
  }
}
