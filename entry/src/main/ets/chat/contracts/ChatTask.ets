import { ChatMessage } from './ChatMessage';

export type TaskStatus = 'running' | 'stopping' | 'completed' | 'failed' | 'cancelled';
export type ProgressPhase = 'processing' | 'searching' | 'saving';

export interface ServiceError {
  code: string;
  message: string;
}

export interface ReplyPreview {
  draftId: string;
  text: string;
  revision: number;
}

export interface TaskSnapshot {
  chatId: string;
  taskId: string;
  requestId: string;
  userMessageId: string;
  revision: number;
  status: TaskStatus;
  outcome: 'reply' | 'display' | 'needs_clarification' | 'no_evidence' | null;
  runtimeReason: string | null;
  reason: string | null;
  error: ServiceError | null;
  savedMessages: ChatMessage[];
  previews: ReplyPreview[];
  canRetry: boolean;
}

export interface ChatEvent {
  id: string;
  event: 'task_snapshot' | 'task_progress' | 'message_saved' | 'task_finished';
  chatId: string;
  taskId: string;
  requestId: string;
  task?: TaskSnapshot;
  message?: ChatMessage;
  taskRevision?: number;
  phase?: ProgressPhase;
}

export function isActiveTask(task: TaskSnapshot | null): boolean {
  return task !== null && (task.status === 'running' || task.status === 'stopping');
}
