import { ChatMessage, MessagePage } from './ChatMessage';
import { ChatEvent, ServiceError, TaskSnapshot } from './ChatTask';

export interface ChatSnapshot {
  chatId: string;
  messages: ChatMessage[];
  olderCursor: string | null;
  activeTask: TaskSnapshot | null;
  latestTask: TaskSnapshot | null;
}

export interface SendRequest {
  requestId: string;
  text: string;
}

export interface AcceptedMessage {
  userMessage: ChatMessage;
  task: TaskSnapshot;
}

export interface RequestResult {
  requestId: string;
  kind: 'send' | 'retry' | 'stop';
  task: TaskSnapshot;
}

// A rejected HTTP operation and an accepted task that later failed are different results.
// Transport errors mean acceptance is unknown and require requestId reconciliation.
export class ChatServiceError extends Error {
  kind: 'rejected' | 'network';
  detail: ServiceError;

  constructor(kind: 'rejected' | 'network', code: string, message: string) {
    super(message);
    this.kind = kind;
    this.detail = { code: code, message: message };
  }
}

export interface ChatSubscription {
  dispose(): void;
}

export interface ChatObserver {
  onEvent(event: ChatEvent): void;
  onError(error: ChatServiceError): void;
}

export interface ChatService {
  loadChat(): Promise<ChatSnapshot>;
  loadOlder(cursor: string): Promise<MessagePage>;
  send(request: SendRequest): Promise<AcceptedMessage>;
  findRequest(requestId: string): Promise<RequestResult>;
  getTask(taskId: string): Promise<TaskSnapshot>;
  subscribe(taskId: string, observer: ChatObserver): ChatSubscription;
  stop(taskId: string, requestId: string): Promise<TaskSnapshot>;
  retry(taskId: string, requestId: string): Promise<TaskSnapshot>;
}
