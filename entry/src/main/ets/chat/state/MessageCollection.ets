import { ChatMessage, PendingMessage } from '../contracts/ChatMessage';

export function mergeMessages(current: ChatMessage[], incoming: ChatMessage[]): ChatMessage[] {
  const byId = new Map<string, ChatMessage>();
  for (const message of current) {
    byId.set(message.messageId, message);
  }
  for (const message of incoming) {
    // Formal messages are immutable. Replays must not rewrite initial ownership.
    if (!byId.has(message.messageId)) {
      byId.set(message.messageId, message);
    }
  }
  return Array.from(byId.values()).sort((left: ChatMessage, right: ChatMessage) => {
    return left.sequence - right.sequence;
  });
}

export function remainingPending(pending: PendingMessage[], messages: ChatMessage[]): PendingMessage[] {
  return pending.filter((item: PendingMessage) => {
    return !messages.some((message: ChatMessage) => {
      return message.role === 'user' && message.requestId === item.requestId;
    });
  });
}
