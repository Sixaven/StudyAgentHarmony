import { ChatService } from '../contracts/ChatService';
import { FakeChatService, FakeScenario } from '../demo/FakeChatService';
import { ChatViewModel } from '../state/ChatViewModel';

// Only this composition root selects the service. Components never construct clients.
export function createChatViewModel(scenario: FakeScenario = 'ready'): ChatViewModel {
  const service: ChatService = new FakeChatService(scenario);
  return new ChatViewModel(service);
}
