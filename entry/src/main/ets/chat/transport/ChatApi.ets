import { MessagePage } from '../contracts/ChatMessage';
import { TaskSnapshot, isActiveTask } from '../contracts/ChatTask';
import { AcceptedMessage, ChatObserver, ChatService, ChatServiceError, ChatSnapshot,
  ChatSubscription, RequestResult, SendRequest } from '../contracts/ChatService';
import { ChatTransport } from './RcpTransport';
import { protocolError } from './ApiError';
import { parseJson, object, text, nullableText, choice, messages, message, task, serviceError } from './ResponseValidation';
import { TaskSubscription } from '../streaming/TaskSubscription';

interface ControlRequest {
  requestId: string;
}

export class ChatApi implements ChatService {
  private transport: ChatTransport;

  constructor(transport: ChatTransport) {
    this.transport = transport;
  }

  close(): void {
    this.transport.close?.();
  }

  private async data(method: 'GET' | 'POST', path: string, body?: string,
    requestId?: string): Promise<Object> {
    const response = await this.transport.request(method, path, body);
    const envelope = parseJson(response.body);
    if (response.status !== 200 && response.status !== 202) {
      if (![400, 404, 409, 503].includes(response.status) || envelope['data'] !== undefined) {
        throw protocolError();
      }
      if (requestId !== undefined && text(envelope['requestId'], true) !== requestId) {
        throw protocolError();
      }
      throw ChatServiceError.fromServiceError(serviceError(envelope['error']));
    }
    if ((method === 'GET' && response.status !== 200) ||
      envelope['data'] === undefined || envelope['error'] !== undefined) {
      throw protocolError();
    }
    return envelope['data'];
  }

  async loadChat(): Promise<ChatSnapshot> {
    const raw = object(await this.data('GET', '/chat'));
    const chatId = text(raw['chatId'], true);
    const active = raw['activeTask'] === null ? null : task(raw['activeTask']);
    const latest = raw['latestTask'] === null ? null : task(raw['latestTask']);
    if ((active !== null && (!isActiveTask(active) || active.chatId !== chatId)) ||
      (latest !== null && latest.chatId !== chatId)) {
      throw protocolError();
    }
    return { chatId: chatId, messages: messages(raw['messages'], chatId),
      olderCursor: nullableText(raw['olderCursor']), activeTask: active, latestTask: latest };
  }

  async loadOlder(cursor: string): Promise<MessagePage> {
    const raw = object(await this.data('GET',
      '/chat/messages?before=' + encodeURIComponent(cursor) + '&limit=50'));
    return { messages: messages(raw['messages']), olderCursor: nullableText(raw['olderCursor']) };
  }

  async send(request: SendRequest): Promise<AcceptedMessage> {
    const raw = object(await this.data('POST', '/chat/messages', JSON.stringify(request), request.requestId));
    const saved = message(raw['userMessage']);
    const accepted = task(raw['task']);
    if (accepted.requestId !== request.requestId || saved.requestId !== request.requestId ||
      saved.taskId !== accepted.taskId || saved.chatId !== accepted.chatId ||
      saved.messageId !== accepted.userMessageId || saved.role !== 'user' ||
      saved.content !== request.text) {
      throw protocolError();
    }
    return { userMessage: saved, task: accepted };
  }

  async findRequest(requestId: string): Promise<RequestResult> {
    const raw = object(await this.data('GET', '/chat/requests/' + encodeURIComponent(requestId)));
    const id = text(raw['requestId'], true);
    const kind = choice(raw['kind'], ['send', 'retry', 'stop']) as ('send' | 'retry' | 'stop');
    const snapshot = task(raw['task']);
    if (id !== requestId || (kind !== 'stop' && snapshot.requestId !== id)) {
      throw protocolError();
    }
    return { requestId: id, kind: kind, task: snapshot };
  }

  async getTask(taskId: string): Promise<TaskSnapshot> {
    const snapshot = task(await this.data('GET', '/tasks/' + encodeURIComponent(taskId)));
    if (snapshot.taskId !== taskId) {
      throw protocolError();
    }
    return snapshot;
  }

  subscribe(taskId: string, observer: ChatObserver): ChatSubscription {
    const subscription = new TaskSubscription(this.transport, taskId, observer);
    subscription.start();
    return subscription;
  }

  async stop(taskId: string, requestId: string): Promise<TaskSnapshot> {
    const body: ControlRequest = { requestId: requestId };
    const snapshot = task(await this.data('POST', '/tasks/' + encodeURIComponent(taskId) + '/stop',
      JSON.stringify(body), requestId));
    if (snapshot.taskId !== taskId) {
      throw protocolError();
    }
    return snapshot;
  }

  async retry(taskId: string, requestId: string): Promise<TaskSnapshot> {
    const body: ControlRequest = { requestId: requestId };
    const snapshot = task(await this.data('POST', '/tasks/' + encodeURIComponent(taskId) + '/retry',
      JSON.stringify(body), requestId));
    if (snapshot.requestId !== requestId || snapshot.taskId === taskId) {
      throw protocolError();
    }
    return snapshot;
  }
}
