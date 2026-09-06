import { ChatServiceError } from '../contracts/ChatService';

export function protocolError(): ChatServiceError {
  return new ChatServiceError('network', 'protocol_error', '服务响应无法确认，请重试核对。');
}

export function networkError(): ChatServiceError {
  return new ChatServiceError('network', 'network_error', '连接失败或超时，操作结果尚未确认。');
}

// Invalid success/error bodies cannot prove that a write was rejected.
export function transportError(error: Error): ChatServiceError {
  if (error instanceof ChatServiceError) {
    return error;
  }
  return networkError();
}
