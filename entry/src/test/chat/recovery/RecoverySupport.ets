import { ChatService } from '../../../main/ets/chat/contracts/ChatService';
import { ChatViewModel } from '../../../main/ets/chat/state/ChatViewModel';
import { PendingRequestStore, MemoryPendingRequestStore } from '../../../main/ets/chat/recovery/PendingRequestStore';

let requestNumber = 0;

export function createModel(service: ChatService,
  store: PendingRequestStore = new MemoryPendingRequestStore()): ChatViewModel {
  return new ChatViewModel(service, store, () => {
    requestNumber++;
    return 'test-request-' + requestNumber.toString();
  });
}
