import { common } from '@kit.AbilityKit';
import { ChatService } from '../contracts/ChatService';
import { FakeChatService, FakeScenario } from '../demo/FakeChatService';
import { ChatViewModel } from '../state/ChatViewModel';
import { chatConfiguration, ChatConfiguration } from './ChatConfig';
import { ChatApi } from '../transport/ChatApi';
import { RcpTransport } from '../transport/RcpTransport';
import { PendingRequestStore, MemoryPendingRequestStore } from '../recovery/PendingRequestStore';
import { DevicePendingRequestStore } from '../recovery/DevicePendingRequestStore';

let model: ChatViewModel | null = null;
let transport: RcpTransport | null = null;
let attached = false;
let foreground = false;
let observing = false;

export function createChatViewModel(scenario: FakeScenario = 'ready',
  config: ChatConfiguration = chatConfiguration,
  store: PendingRequestStore = new MemoryPendingRequestStore()): ChatViewModel {
  let service: ChatService;
  if (config.mode === 'real') {
    transport = new RcpTransport(config);
    service = new ChatApi(transport);
  } else {
    service = new FakeChatService(scenario);
  }
  return new ChatViewModel(service, store);
}

export function initializeChat(context: common.UIAbilityContext): void {
  if (model !== null) {
    return;
  }
  let store: PendingRequestStore = new MemoryPendingRequestStore();
  if (chatConfiguration.mode === 'real') {
    store = new DevicePendingRequestStore(context, chatConfiguration.baseUrl);
  }
  model = createChatViewModel('ready', chatConfiguration, store);
}

export function getChatViewModel(): ChatViewModel {
  if (model === null) {
    throw new Error('聊天依赖尚未初始化。');
  }
  return model;
}

function updateObservation(): void {
  const visible = attached && foreground;
  if (visible === observing) {
    return;
  }
  observing = visible;
  if (visible) {
    model?.load();
  } else {
    model?.dispose();
  }
}

export function attachChatPage(): void {
  attached = true;
  updateObservation();
}

export function detachChatPage(): void {
  attached = false;
  updateObservation();
}

export function setChatForeground(value: boolean): void {
  foreground = value;
  updateObservation();
}

export function destroyChat(): void {
  model?.dispose();
  transport?.close();
  model = null;
  transport = null;
  attached = false;
  foreground = false;
  observing = false;
}
