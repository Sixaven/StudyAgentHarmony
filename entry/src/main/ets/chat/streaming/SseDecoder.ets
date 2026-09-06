import { protocolError } from '../transport/ApiError';

export interface SseFrame {
  id: string;
  event: string;
  data: string;
}

// Decode bytes incrementally, rejecting malformed/truncated UTF-8 rather than
// replacing bytes inside message IDs or saved content.
export class SseDecoder {
  private remaining: number = 0;
  private codePoint: number = 0;
  private minimum: number = 0;
  private first: boolean = true;
  private afterCr: boolean = false;
  private line: string = '';
  private data: string[] = [];
  private event: string = '';
  private id: string = '';
  private frameSize: number = 0;
  private limit: number;

  constructor(limit: number = 1024 * 1024) {
    this.limit = limit;
  }

  push(bytes: Uint8Array, receive: (frame: SseFrame) => void): void {
    for (let index = 0; index < bytes.length; index++) {
      const byte = bytes[index];
      if (this.remaining > 0) {
        if (byte < 0x80 || byte > 0xbf) {
          throw protocolError();
        }
        this.codePoint = this.codePoint * 64 + byte - 0x80;
        this.remaining--;
        if (this.remaining === 0) {
          if (this.codePoint < this.minimum || this.codePoint > 0x10ffff ||
            (this.codePoint >= 0xd800 && this.codePoint <= 0xdfff)) {
            throw protocolError();
          }
          this.character(String.fromCodePoint(this.codePoint), receive);
        }
      } else if (byte < 0x80) {
        this.character(String.fromCharCode(byte), receive);
      } else if (byte >= 0xc2 && byte <= 0xdf) {
        this.remaining = 1;
        this.codePoint = byte - 0xc0;
        this.minimum = 0x80;
      } else if (byte >= 0xe0 && byte <= 0xef) {
        this.remaining = 2;
        this.codePoint = byte - 0xe0;
        this.minimum = 0x800;
      } else if (byte >= 0xf0 && byte <= 0xf4) {
        this.remaining = 3;
        this.codePoint = byte - 0xf0;
        this.minimum = 0x10000;
      } else {
        throw protocolError();
      }
    }
  }

  finish(): void {
    if (this.remaining !== 0 || this.line.length !== 0 || this.data.length !== 0 ||
      this.id.length !== 0 || this.event.length !== 0) {
      throw protocolError();
    }
    // A clean EOF is still not a task terminal event; the subscriber reconciles.
  }

  private character(value: string, receive: (frame: SseFrame) => void): void {
    if (this.first) {
      this.first = false;
      if (value === '\uFEFF') {
        return;
      }
    }
    if (this.afterCr && value === '\n') {
      this.afterCr = false;
      return;
    }
    this.afterCr = value === '\r';
    if (value === '\r' || value === '\n') {
      this.completeLine(receive);
      return;
    }
    this.line += value;
    if (this.line.length + this.frameSize > this.limit) {
      throw protocolError();
    }
  }

  private completeLine(receive: (frame: SseFrame) => void): void {
    const line = this.line;
    this.line = '';
    if (line.length === 0) {
      const frame: SseFrame = { id: this.id, event: this.event, data: this.data.join('\n') };
      const hasData = this.data.length > 0;
      this.id = '';
      this.event = '';
      this.data = [];
      this.frameSize = 0;
      if (hasData) {
        receive(frame);
      }
      return;
    }
    if (line.startsWith(':')) {
      return;
    }
    this.frameSize += line.length + 1;
    if (this.frameSize > this.limit) {
      throw protocolError();
    }
    const separator = line.indexOf(':');
    const field = separator < 0 ? line : line.substring(0, separator);
    let value = separator < 0 ? '' : line.substring(separator + 1);
    if (value.startsWith(' ')) {
      value = value.substring(1);
    }
    if (field === 'data') {
      this.data.push(value);
    } else if (field === 'event') {
      this.event = value;
    } else if (field === 'id' && !value.includes('\u0000')) {
      this.id = value;
    }
  }
}
