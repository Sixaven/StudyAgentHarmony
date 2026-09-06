import { ChatEvent, isActiveTask } from '../contracts/ChatTask';
import { protocolError } from '../transport/ApiError';
import { parseJson, text, task, message, integer } from '../transport/ResponseValidation';
import { SseFrame } from './SseDecoder';

export function chatEvent(frame: SseFrame): ChatEvent | null {
  if (!['task_snapshot', 'task_progress', 'message_saved', 'task_finished'].includes(frame.event)) {
    return null;
  }
  const raw = parseJson(frame.data);
  const result: ChatEvent = {
    id: frame.id, event: frame.event as ('task_snapshot' | 'task_progress' | 'message_saved' | 'task_finished'),
    chatId: text(raw['chatId'], true), taskId: text(raw['taskId'], true),
    requestId: text(raw['requestId'], true)
  };
  if (frame.event === 'task_snapshot' || frame.event === 'task_finished') {
    const snapshot = task(raw['task']);
    if (snapshot.taskId !== result.taskId || snapshot.requestId !== result.requestId ||
      snapshot.chatId !== result.chatId ||
      (frame.event === 'task_finished' && isActiveTask(snapshot))) {
      throw protocolError();
    }
    result.task = snapshot;
  } else if (frame.event === 'message_saved') {
    result.message = message(raw['message']);
    result.taskRevision = integer(raw['taskRevision']);
    if (result.message.chatId !== result.chatId) {
      throw protocolError();
    }
  } else {
    const phase = text(raw['phase'], true);
    result.phase = 'processing';
    if (phase === 'searching' || phase === 'saving') {
      result.phase = phase;
    }
  }
  return result;
}
