import { ChatService } from '../contracts/ChatService';
import { FakeChatService, FakeScenario } from '../demo/FakeChatService';
import { ChatViewModel } from '../state/ChatViewModel';
import { chatConfiguration, ChatConfiguration } from './ChatConfig';
import { ChatApi } from '../transport/ChatApi';
import { RcpTransport } from '../transport/RcpTransport';

// Only this composition root selects the service. Never fall back after a real error.
export function createChatViewModel(scenario: FakeScenario = 'ready',
  config: ChatConfiguration = chatConfiguration): ChatViewModel {
  let service: ChatService;
  if (config.mode === 'real') {
    service = new ChatApi(new RcpTransport(config));
  } else {
    service = new FakeChatService(scenario);
  }
  return new ChatViewModel(service);
}
