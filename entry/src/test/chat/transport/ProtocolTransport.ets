import { ChatMessage } from '../../../main/ets/chat/contracts/ChatMessage';
import { TaskSnapshot } from '../../../main/ets/chat/contracts/ChatTask';
import { ChatTransport, HttpReply, ByteObserver } from '../../../main/ets/chat/transport/RcpTransport';
import { ChatServiceError, ChatSubscription } from '../../../main/ets/chat/contracts/ChatService';
import { networkError } from '../../../main/ets/chat/transport/ApiError';

export class ProtocolTransport implements ChatTransport {
  reply: HttpReply = { status: 200, body: '{}' };
  failure: boolean = false;
  methods: string[] = [];
  paths: string[] = [];
  bodies: string[] = [];
  observers: ByteObserver[] = [];
  disposed: boolean[] = [];

  async request(method: 'GET' | 'POST', path: string, body?: string): Promise<HttpReply> {
    this.methods.push(method);
    this.paths.push(path);
    this.bodies.push(body ?? '');
    if (this.failure) {
      throw networkError();
    }
    return this.reply;
  }

  stream(path: string, observer: ByteObserver): ChatSubscription {
    this.paths.push(path);
    const index = this.observers.length;
    this.observers.push(observer);
    this.disposed.push(false);
    return { dispose: () => { this.disposed[index] = true; } };
  }
}

// Independent encoder for byte-by-byte decoder/connection tests.
export function utf8(value: string): Uint8Array {
  const bytes: number[] = [];
  for (let index = 0; index < value.length; index++) {
    const code = value.codePointAt(index) ?? 0;
    if (code > 0xffff) {
      index++;
    }
    if (code < 0x80) {
      bytes.push(code);
    } else if (code < 0x800) {
      bytes.push(0xc0 + (code >> 6), 0x80 + (code & 63));
    } else if (code < 0x10000) {
      bytes.push(0xe0 + (code >> 12), 0x80 + ((code >> 6) & 63), 0x80 + (code & 63));
    } else {
      bytes.push(0xf0 + (code >> 18), 0x80 + ((code >> 12) & 63),
        0x80 + ((code >> 6) & 63), 0x80 + (code & 63));
    }
  }
  return new Uint8Array(bytes);
}

export interface SsePayload {
  chatId: string;
  taskId: string;
  requestId: string;
  task?: TaskSnapshot;
  message?: ChatMessage;
  taskRevision?: number;
  phase?: string;
}

export function frame(id: number, event: string, data: SsePayload): Uint8Array {
  return utf8('id: ' + id + '\nevent: ' + event + '\ndata: ' + JSON.stringify(data) + '\n\n');
}
