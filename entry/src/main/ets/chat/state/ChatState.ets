import { ChatMessage, PendingMessage } from '../contracts/ChatMessage';
import { isActiveTask, TaskSnapshot } from '../contracts/ChatTask';

export type RequestPhase = 'loading' | 'ready' | 'sending' | 'processing' | 'stopping' | 'checking' | 'failed';

@ObservedV2
export class ChatState {
  @Trace messages: ChatMessage[] = [];
  @Trace pending: PendingMessage[] = [];
  @Trace draft: string = '';
  @Trace phase: RequestPhase = 'loading';
  @Trace task: TaskSnapshot | null = null;
  @Trace olderCursor: string | null = null;
  @Trace initialLoadFailed: boolean = false;
  @Trace initialized: boolean = false;
  @Trace loadingOlder: boolean = false;
  @Trace notice: string = '';

  get canSend(): boolean {
    const idle = this.phase === 'ready' || this.phase === 'failed';
    return this.initialized && idle && !isActiveTask(this.task) &&
      this.pending.length === 0 && this.draft.trim().length > 0;
  }

  get canStop(): boolean {
    return this.phase === 'processing' && isActiveTask(this.task);
  }

  get canRetryLoad(): boolean {
    return this.initialLoadFailed && this.phase === 'failed';
  }
}
