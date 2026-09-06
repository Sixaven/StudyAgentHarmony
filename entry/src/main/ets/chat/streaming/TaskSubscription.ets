import { ChatObserver, ChatSubscription, ChatServiceError } from '../contracts/ChatService';
import { TaskSnapshot, isActiveTask } from '../contracts/ChatTask';
import { ChatTransport } from '../transport/RcpTransport';
import { protocolError, networkError, transportError } from '../transport/ApiError';
import { SseDecoder, SseFrame } from './SseDecoder';
import { chatEvent } from './ChatEvents';

export class TaskSubscription implements ChatSubscription {
  private generation: number = 0;
  private connection: ChatSubscription | null = null;
  private stopped: boolean = false;
  private gapRecovered: boolean = false;
  private highestRevision: number = -1;
  private identity: TaskSnapshot | null = null;
  private taskId: string;
  private transport: ChatTransport;
  private observer: ChatObserver;

  constructor(transport: ChatTransport, taskId: string, observer: ChatObserver) {
    this.transport = transport;
    this.taskId = taskId;
    this.observer = observer;
  }

  start(): void {
    this.connect();
  }

  dispose(): void {
    this.stopped = true;
    this.generation++;
    this.connection?.dispose();
    this.connection = null;
  }

  private fail(error: ChatServiceError): void {
    if (!this.stopped) {
      this.dispose();
      this.observer.onError(error);
    }
  }

  private connect(): void {
    const generation = ++this.generation;
    this.connection?.dispose();
    this.connection = null;
    const decoder = new SseDecoder();
    let lastId: number | null = null;
    let initial: TaskSnapshot | null = null;

    const connection = this.transport.stream('/tasks/' + encodeURIComponent(this.taskId) + '/events', {
      onData: (bytes: Uint8Array) => {
        if (this.stopped || generation !== this.generation) {
          return;
        }
        try {
          decoder.push(bytes, (frame: SseFrame) => {
            if (this.stopped || generation !== this.generation) {
              return;
            }
            if (!/^\d+$/.test(frame.id) || !Number.isSafeInteger(Number(frame.id))) {
              throw protocolError();
            }
            const id = Number(frame.id);
            if (lastId !== null && id <= lastId) {
              return;
            }
            if (lastId !== null && id !== lastId + 1) {
              // One fresh snapshot subscription repairs a gap. Repeated gaps are
              // surfaced instead of opening an unbounded reconnection loop.
              if (this.gapRecovered) {
                throw protocolError();
              }
              this.gapRecovered = true;
              this.connect();
              return;
            }
            lastId = id;
            const event = chatEvent(frame);
            if (event === null) {
              return;
            }
            if (event.taskId !== this.taskId) {
              throw protocolError();
            }
            if (initial === null) {
              if (event.event !== 'task_snapshot' || event.task === undefined) {
                throw protocolError();
              }
              initial = event.task;
            }
            if (this.identity === null) {
              this.identity = initial;
            }
            if (event.chatId !== this.identity.chatId || event.requestId !== this.identity.requestId) {
              throw protocolError();
            }
            if (event.taskRevision !== undefined) {
              this.highestRevision = Math.max(this.highestRevision, event.taskRevision);
            }
            if (event.task !== undefined) {
              this.highestRevision = Math.max(this.highestRevision, event.task.revision);
            }
            this.observer.onEvent(event);
            if (event.task !== undefined && !isActiveTask(event.task) && event.task.revision >= this.highestRevision) {
              this.dispose();
            }
          });
        } catch (error) {
          this.fail(transportError(error as Error));
        }
      },
      onEnd: () => {
        if (!this.stopped && generation === this.generation) {
          try {
            decoder.finish();
            this.fail(networkError());
          } catch {
            this.fail(protocolError());
          }
        }
      },
      onError: (error: ChatServiceError) => {
        if (generation === this.generation) {
          this.fail(error);
        }
      }
    });
    if (this.stopped || generation !== this.generation) {
      connection.dispose();
    } else {
      this.connection = connection;
    }
  }
}
