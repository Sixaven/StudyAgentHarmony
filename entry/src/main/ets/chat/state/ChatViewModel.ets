import { MemoryPendingRequestStore, PendingOperation, PendingRequestStore } from '../recovery/PendingRequestStore';
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
  private observedRevision: number = -1;
  private loadGeneration: number = 0;
  private operationGeneration: number = 0;
  private draftRevision: number = 0;
  private subscription: ChatSubscription | null = null;
  private observationGeneration: number = 0;

  private store: PendingRequestStore;
  private nextRequestId: () => string;

  constructor(service: ChatService, store: PendingRequestStore = new MemoryPendingRequestStore(),
    nextRequestId: () => string = () => util.generateRandomUUID(true)) {
    this.service = service;
    this.store = store;
    this.nextRequestId = nextRequestId;
  }

  async load(): Promise<void> {
    if (this.state.controlBusy) {
      return;
    }
    const generation = ++this.loadGeneration;
    this.releaseObservation();
    this.state.phase = 'loading';
    this.state.initialLoadFailed = false;
    this.state.notice = '';
    try {
      const pending = this.store.read();
      this.state.hasUnconfirmed = pending !== null;
      if (pending !== null) {
        if (pending.kind === 'send') {
          this.state.pending = [{ requestId: pending.requestId, text: pending.text }];
        }
        try {
          const result = await this.service.findRequest(pending.requestId);
          if (generation !== this.loadGeneration) {
            return;
          }
          if (result.kind !== pending.kind ||
            (pending.kind === 'stop' && result.task.taskId !== pending.taskId)) {
            throw new Error('请求核对结果不一致。');
          }
          this.merge(result.task.savedMessages);
          this.clearPending();
        } catch (error) {
          if (!(error instanceof ChatServiceError && error.kind === 'rejected' &&
            error.detail.code === 'not_found')) {
            throw new Error(String(error));
          }
          // Only an explicit user retry may replay a write absent from the server.
        }
      }
      const snapshot = await this.service.loadChat();
      if (generation !== this.loadGeneration) {
        return;
      }
      this.merge(snapshot.messages);
      this.state.olderCursor = snapshot.olderCursor;
      this.state.task = null;
      this.observedRevision = -1;
      if (snapshot.latestTask !== null) {
        this.merge(snapshot.latestTask.savedMessages);
      }
      this.applyTask(snapshot.activeTask ?? snapshot.latestTask);
      this.state.initialized = true;
      if (this.state.hasUnconfirmed) {
        this.state.phase = 'checking';
        this.state.notice = '上次请求尚未接受，点击重试继续核对并重发。';
      } else if (isActiveTask(this.state.task) && this.state.task !== null) {
        this.observe(this.state.task);
      }
    } catch {
      if (generation !== this.loadGeneration) {
        return;
      }
      this.state.phase = 'failed';
      this.state.initialLoadFailed = true;
      this.state.notice = '暂时无法确认服务端状态，请重试。';
    }
  }

  private clearPending(): void {
    this.store.clear();
    this.state.hasUnconfirmed = false;
  }

  dispose(): void {
    this.loadGeneration++;
    this.operationGeneration++;
    this.state.controlBusy = false;
    this.state.phase = 'checking';
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
      this.observedRevision = -1;
      this.state.phase = 'ready';
      return;
    }
    this.merge(task.savedMessages);
    const current = this.state.task;
    if (current !== null && current.taskId === task.taskId &&
      (current.revision >= task.revision || this.observedRevision > task.revision)) {
      return;
    }
    this.observedRevision = task.revision;
    this.state.task = task;
    this.state.notice = '';
    if (task.status === 'running') {
      this.state.phase = 'processing';
    } else if (task.status === 'stopping') {
      this.state.phase = 'stopping';
    } else if (task.status === 'failed') {
      this.state.phase = 'failed';
      this.state.notice = task.reason === 'server_restarted' ?
        '服务已重启，上次处理已结束，已保存的内容仍可阅读。' : (task.error?.message ?? '');
    } else {
      this.state.phase = 'ready';
      this.state.notice = task.status === 'cancelled' ? '已停止，已保存的内容仍可阅读。' : '';
    }
  }

  async loadOlder(): Promise<void> {
    const generation = this.loadGeneration;
    const cursor = this.state.olderCursor;
    if (cursor === null || this.state.loadingOlder) {
      return;
    }
    this.state.loadingOlder = true;
    try {
      const page = await this.service.loadOlder(cursor);
      if (generation !== this.loadGeneration) {
        return;
      }
      this.merge(page.messages);
      this.state.olderCursor = page.olderCursor;
    } catch {
      if (generation !== this.loadGeneration) {
        return;
      }
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
    const request: SendRequest = { requestId: this.nextRequestId(), text: this.state.draft };
    try {
      this.store.save({ kind: 'send', requestId: request.requestId, text: request.text, taskId: '' });
      this.state.hasUnconfirmed = true;
    } catch {
      this.state.hasUnconfirmed = true;
      this.state.phase = 'checking';
      this.state.notice = '无法保存待确认请求，尚未发送，请稍后重试。';
      return;
    }
    this.state.controlBusy = true;
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
      this.clearPending();
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
        try {
          this.clearPending();
        } catch {
          this.state.phase = 'checking';
          this.state.notice = '请求未接受，但本地记录尚未清理，请重试。';
          return;
        }
        this.state.pending = [];
        this.state.phase = 'ready';
        this.state.notice = error.detail.message;
        // A later edit, including deliberately clearing a draft, always wins.
        if (sentDraftRevision === this.draftRevision) {
          this.state.draft = request.text;
        }
        if (error.detail.code === 'busy' || error.detail.code === 'request_conflict') {
          this.state.controlBusy = false;
          await this.load();
          if (generation === this.operationGeneration) {
            this.state.notice = error.detail.message;
          }
        }
      } else {
        this.state.phase = 'checking';
        this.state.notice = '连接已断开，发送结果尚未确认。';
      }
    } finally {
      if (generation === this.operationGeneration) {
        this.state.controlBusy = false;
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
          if (event.taskRevision !== undefined) {
            this.observedRevision = Math.max(this.observedRevision, event.taskRevision);
          }
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

  async requestStop(): Promise<void> {
    const task = this.state.task;
    if (!this.state.canStop || task === null) {
      return;
    }
    await this.startControl('stop', task.taskId);
  }

  async requestRetry(): Promise<void> {
    if (this.state.controlBusy) {
      return;
    }
    if (this.state.canRetryLoad) {
      await this.load();
      return;
    }
    if (this.state.hasUnconfirmed || this.state.phase === 'checking') {
      await this.reconcile();
    } else if (this.state.canRetryTask && this.state.task !== null) {
      await this.startControl('retry', this.state.task.taskId);
    }
  }

  private async startControl(kind: 'stop' | 'retry', taskId: string): Promise<void> {
    const operation: PendingOperation = {
      kind: kind, requestId: this.nextRequestId(), taskId: taskId, text: ''
    };
    try {
      this.store.save(operation);
      this.state.hasUnconfirmed = true;
    } catch {
      this.state.hasUnconfirmed = true;
      this.state.phase = 'checking';
      this.state.notice = '无法保存待确认请求，操作尚未发出，请稍后重试。';
      return;
    }
    const generation = ++this.operationGeneration;
    this.state.controlBusy = true;
    this.state.phase = kind === 'stop' ? 'stopping' : 'sending';
    try {
      await this.replay(operation, generation);
    } catch (error) {
      await this.handleControlError(error, generation);
    } finally {
      if (generation === this.operationGeneration) {
        this.state.controlBusy = false;
      }
    }
  }

  private async replay(operation: PendingOperation, generation: number): Promise<void> {
    let task: TaskSnapshot;
    if (operation.kind === 'send') {
      const accepted = await this.service.send({ requestId: operation.requestId, text: operation.text });
      task = accepted.task;
      if (generation === this.operationGeneration) {
        this.merge([accepted.userMessage]);
      }
    } else if (operation.kind === 'stop') {
      task = await this.service.stop(operation.taskId, operation.requestId);
    } else {
      task = await this.service.retry(operation.taskId, operation.requestId);
    }
    if (generation !== this.operationGeneration) {
      return;
    }
    this.clearPending();
    this.applyTask(task);
    // A newer terminal event may have won the race with the HTTP response.
    if (isActiveTask(this.state.task) && this.state.task !== null) {
      this.observe(this.state.task);
    }
  }

  private async handleControlError(error: Error, generation: number): Promise<void> {
    if (generation !== this.operationGeneration) {
      return;
    }
    if (error instanceof ChatServiceError && error.kind === 'rejected') {
      try {
        this.clearPending();
        this.state.pending = [];
      } catch {
        this.state.phase = 'checking';
        this.state.notice = '本地记录尚未清理，请重试。';
        return;
      }
      this.state.controlBusy = false;
      await this.load();
      if (generation === this.operationGeneration) {
        this.state.notice = error.detail.message;
      }
    } else {
      this.state.phase = 'checking';
      this.state.notice = '连接已断开，点击重试确认上次操作结果。';
    }
  }

  private async reconcile(): Promise<void> {
    const generation = ++this.operationGeneration;
    this.state.controlBusy = true;
    try {
      const operation = this.store.read();
      if (operation !== null) {
        let missing = false;
        try {
          const result = await this.service.findRequest(operation.requestId);
          if (generation !== this.operationGeneration) {
            return;
          }
          if (result.kind !== operation.kind ||
            (operation.kind === 'stop' && result.task.taskId !== operation.taskId)) {
            throw new Error('请求核对结果不一致。');
          }
          this.merge(result.task.savedMessages);
          this.clearPending();
        } catch (error) {
          if (error instanceof ChatServiceError && error.kind === 'rejected' &&
            error.detail.code === 'not_found') {
            missing = true;
          } else {
            throw new Error(String(error));
          }
        }
        if (generation !== this.operationGeneration) {
          return;
        }
        if (missing) {
          try {
            await this.replay(operation, generation);
          } catch (error) {
            await this.handleControlError(error, generation);
            return;
          }
        }
      }
      if (generation === this.operationGeneration) {
        this.state.controlBusy = false;
        await this.load();
      }
    } catch (error) {
      // A failed lookup is not proof of non-acceptance and never permits another POST.
      if (generation === this.operationGeneration) {
        this.state.phase = 'checking';
        this.state.notice = '暂时无法确认上次结果，请稍后重试。';
      }
    } finally {
      if (generation === this.operationGeneration) {
        this.state.controlBusy = false;
      }
    }
  }
}
