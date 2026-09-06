import { rcp } from '@kit.RemoteCommunicationKit';
import { util } from '@kit.ArkTS';
import { ChatConfiguration, apiBaseUrl } from '../bootstrap/ChatConfig';
import { ChatSubscription, ChatServiceError } from '../contracts/ChatService';
import { networkError, protocolError, transportError } from './ApiError';

export interface HttpReply {
  status: number;
  body: string;
}
export interface ByteObserver {
  onData: (data: Uint8Array) => void;
  onEnd: () => void;
  onError: (error: ChatServiceError) => void;
}
export interface ChatTransport {
  close?: () => void;
  request(method: 'GET' | 'POST', path: string, body?: string): Promise<HttpReply>;
  stream(path: string, observer: ByteObserver): ChatSubscription;
}

// Each operation owns one session: dispose/cancel cannot affect a different request.
// No redirect replay, application POST retry, or server-side stop is performed here.
export class RcpTransport implements ChatTransport {
  private sessions: rcp.Session[] = [];
  private streamClosers: Map<rcp.Session, () => void> = new Map();
  private baseUrl: string;
  private config: ChatConfiguration;

  constructor(config: ChatConfiguration) {
    this.baseUrl = apiBaseUrl(config);
    this.config = config;
  }

  private createSession(): rcp.Session {
    try {
      const session = rcp.createSession();
      this.sessions.push(session);
      return session;
    } catch {
      throw networkError();
    }
  }

  private release(session: rcp.Session): void {
    const index = this.sessions.indexOf(session);
    if (index >= 0) {
      this.sessions.splice(index, 1);
      this.streamClosers.delete(session);
      session.close();
    }
  }

  // The application owner can cancel outstanding reads/writes and streams.
  // A cancelled write remains unknown; this never invokes the task stop API.
  close(): void {
    const sessions = this.sessions.slice();
    for (let index = 0; index < sessions.length; index++) {
      const closeStream = this.streamClosers.get(sessions[index]);
      if (closeStream !== undefined) {
        closeStream();
      } else {
        sessions[index].cancel();
        this.release(sessions[index]);
      }
    }
  }

  async request(method: 'GET' | 'POST', path: string, body?: string): Promise<HttpReply> {
    const session = this.createSession();
    let size = 0;
    let content = '';
    const decoder = util.TextDecoder.create('utf-8', { fatal: true });
    let bodyError: ChatServiceError | null = null;
    const request = new rcp.Request(this.baseUrl + path, method,
      { 'Content-Type': 'application/json', 'Accept': 'application/json' }, body);
    request.configuration = {
      transfer: { autoRedirect: false, timeout: {
        connectMs: this.config.requestTimeoutMs, transferMs: this.config.requestTimeoutMs
      } },
      tracing: { httpEventsHandler: { onDataReceive: (incoming: ArrayBuffer) => {
        try {
          size += incoming.byteLength;
          if (size > 8 * 1024 * 1024) {
            throw protocolError();
          }
          content += decoder.decodeToString(new Uint8Array(incoming), { stream: true });
        } catch {
          bodyError = protocolError();
          session.cancel(request);
        }
      } } }
    };
    try {
      const response = await session.fetch(request);
      if (bodyError !== null) {
        throw protocolError();
      }
      content += decoder.decodeToString(new Uint8Array(0));
      return { status: response.statusCode, body: content };
    } catch (error) {
      if (bodyError !== null) {
        throw protocolError();
      }
      throw transportError(error as Error);
    } finally {
      this.release(session);
    }
  }

  stream(path: string, observer: ByteObserver): ChatSubscription {
    const session = this.createSession();
    let disposed = false;
    let status = 0;
    let eventStream = false;
    const request = new rcp.Request(this.baseUrl + path, 'GET', { 'Accept': 'text/event-stream' });
    const close = () => {
      if (!disposed) {
        disposed = true;
        session.cancel(request);
        this.release(session);
      }
    };
    this.streamClosers.set(session, close);
    const fail = (error: ChatServiceError) => {
      if (!disposed) {
        close();
        observer.onError(error);
      }
    };
    request.configuration = {
      transfer: { autoRedirect: false, timeout: {
        connectMs: this.config.requestTimeoutMs, transferMs: 0,
        inactivityMs: this.config.streamIdleTimeoutMs
      } },
      tracing: { httpEventsHandler: {
        onStatusCodeReceive: (code: number) => {
          status = code;
          if (status !== 200) {
            fail(protocolError());
          }
        },
        onHeaderReceive: (headers: rcp.ResponseHeaders) => {
          const type = headers['content-type'];
          eventStream = typeof type === 'string' &&
            type.toLowerCase().split(';')[0].trim() === 'text/event-stream';
          if (!eventStream) {
            fail(protocolError());
          }
        },
        onDataReceive: (incoming: ArrayBuffer) => {
          if (!disposed) {
            if (status !== 200 || !eventStream) {
              fail(protocolError());
              return;
            }
            observer.onData(new Uint8Array(incoming));
          }
        }
      } }
    };
    session.fetch(request).then(() => {
      if (!disposed) {
        close();
        observer.onEnd();
      }
    }).catch(() => { fail(networkError()); });
    return { dispose: close };
  }
}
