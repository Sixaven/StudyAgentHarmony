import { inputError } from './InputText';
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
  @Trace hasUnconfirmed: boolean = false;
  @Trace controlBusy: boolean = false;

  get canSend(): boolean {
    const idle = this.phase === 'ready' || this.phase === 'failed';
    return this.initialized && !this.initialLoadFailed && !this.hasUnconfirmed &&
      !this.controlBusy && idle && !isActiveTask(this.task) &&
      this.pending.length === 0 && inputError(this.draft) === '';
  }

  get canStop(): boolean {
    return !this.controlBusy && !this.hasUnconfirmed && this.phase === 'processing' && isActiveTask(this.task);
  }

  get canRetryTask(): boolean {
    return !this.controlBusy && !this.hasUnconfirmed && !this.initialLoadFailed &&
      (this.phase === 'ready' || this.phase === 'failed') && this.task !== null &&
      this.task.canRetry && !isActiveTask(this.task);
  }

  get canRetry(): boolean {
    return !this.controlBusy && (this.canRetryLoad || this.hasUnconfirmed ||
      this.phase === 'checking' || this.canRetryTask);
  }

  get canRetryLoad(): boolean {
    return this.initialLoadFailed && this.phase === 'failed';
  }
}
