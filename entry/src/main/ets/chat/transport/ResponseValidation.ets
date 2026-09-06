import { ChatMessage, Citation, CitationLocation } from '../contracts/ChatMessage';
import { TaskSnapshot, ServiceError, TaskStatus } from '../contracts/ChatTask';
import { protocolError } from './ApiError';

// JSON enters as Object, never as an already trusted DTO.
export function object(value: Object | null | undefined): Record<string, Object> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw protocolError();
  }
  return value as Record<string, Object>;
}

export function text(value: Object | null | undefined, nonempty: boolean = false): string {
  if (typeof value !== 'string' || (nonempty && value.length === 0)) {
    throw protocolError();
  }
  return value as string;
}

export function nullableText(value: Object | null | undefined): string | null {
  if (value === null) {
    return null;
  }
  return text(value, true);
}

export function integer(value: Object | null | undefined): number {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || (value as number) < 0) {
    throw protocolError();
  }
  return value as number;
}

export function array(value: Object | null | undefined): Object[] {
  if (!Array.isArray(value)) {
    throw protocolError();
  }
  return value as Object[];
}

export function choice(value: Object | null | undefined, choices: string[]): string {
  const result = text(value);
  if (!choices.includes(result)) {
    throw protocolError();
  }
  return result;
}

export function parseJson(raw: string): Record<string, Object> {
  try {
    return object(JSON.parse(raw) as Object);
  } catch {
    throw protocolError();
  }
}

export function serviceError(value: Object): ServiceError {
  const raw = object(value);
  const result: ServiceError = { code: text(raw['code'], true), message: text(raw['message'], true) };
  if (raw['details'] !== undefined) {
    const details = object(raw['details']);
    result.details = {};
    if (details['existingTaskId'] !== undefined) {
      result.details.existingTaskId = text(details['existingTaskId'], true);
    }
  }
  return result;
}

function timestamp(value: Object): string {
  const result = text(value, true);
  if (!/^\d{4}-\d{2}-\d{2}T.*Z$/.test(result) || !Number.isFinite(Date.parse(result))) {
    throw protocolError();
  }
  return result;
}

function citation(value: Object): Citation {
  const raw = object(value);
  const position = object(raw['location']);
  const location: CitationLocation = {
    sectionPath: array(position['sectionPath']).map((part: Object) => text(part)),
    start: integer(position['start']), end: integer(position['end'])
  };
  if (location.end < location.start) {
    throw protocolError();
  }
  if (position['anchor'] !== undefined) {
    location.anchor = text(position['anchor']);
  }
  return {
    citationId: text(raw['citationId'], true), label: text(raw['label']), title: text(raw['title']),
    originalUrl: text(raw['originalUrl'], true),
    sourceType: choice(raw['sourceType'],
      ['official_release', 'official_documentation', 'official_blog', 'paper_abstract']) as ('official_release' | 'official_documentation' | 'official_blog' | 'paper_abstract'),
    publishedAt: raw['publishedAt'] === null ? null : timestamp(raw['publishedAt']),
    text: text(raw['text']), documentVersionId: text(raw['documentVersionId'], true),
    chunkId: text(raw['chunkId'], true), location: location
  };
}

export function message(value: Object): ChatMessage {
  const raw = object(value);
  if (raw['draftId'] !== null) {
    throw protocolError();
  }
  const result: ChatMessage = {
    messageId: text(raw['messageId'], true), chatId: text(raw['chatId'], true),
    sequence: integer(raw['sequence']),
    role: choice(raw['role'], ['user', 'assistant']) as ('user' | 'assistant'),
    format: choice(raw['format'], ['plain', 'markdown']) as ('plain' | 'markdown'),
    content: text(raw['content']), createdAt: timestamp(raw['createdAt']),
    requestId: nullableText(raw['requestId']), taskId: nullableText(raw['taskId']),
    origin: choice(raw['origin'], ['interactive', 'legacy', 'local']) as ('interactive' | 'legacy' | 'local'),
    draftId: null, citations: array(raw['citations']).map((item: Object) => citation(item))
  };
  if (result.origin === 'interactive' && (result.requestId === null || result.taskId === null)) {
    throw protocolError();
  }
  return result;
}

export function messages(value: Object, chatId?: string): ChatMessage[] {
  const result = array(value).map((item: Object) => message(item));
  if (chatId !== undefined && result.some((item: ChatMessage) => item.chatId !== chatId)) {
    throw protocolError();
  }
  return result;
}

export function task(value: Object): TaskSnapshot {
  const raw = object(value);
  const chatId = text(raw['chatId'], true);
  if (typeof raw['canRetry'] !== 'boolean' || array(raw['previews']).length !== 0) {
    throw protocolError();
  }
  const status = choice(raw['status'], ['running', 'stopping', 'completed', 'failed', 'cancelled']) as TaskStatus;
  const result: TaskSnapshot = {
    chatId: chatId, taskId: text(raw['taskId'], true), requestId: text(raw['requestId'], true),
    userMessageId: text(raw['userMessageId'], true), revision: integer(raw['revision']),
    status: status,
    outcome: raw['outcome'] === null ? null :
      choice(raw['outcome'], ['reply', 'display', 'needs_clarification', 'no_evidence']) as ('reply' | 'display' | 'needs_clarification' | 'no_evidence' | null),
    runtimeReason: nullableText(raw['runtimeReason']), reason: nullableText(raw['reason']),
    error: raw['error'] === null ? null : serviceError(raw['error']),
    savedMessages: messages(raw['savedMessages'], chatId), previews: [],
    canRetry: raw['canRetry'] as boolean
  };
  if (result.canRetry && status !== 'failed' && status !== 'cancelled') {
    throw protocolError();
  }
  return result;
}
