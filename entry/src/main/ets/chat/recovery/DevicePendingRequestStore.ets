import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { PendingOperation, PendingRequestStore } from './PendingRequestStore';

export class DevicePendingRequestStore implements PendingRequestStore {
  private context: common.UIAbilityContext;
  private key: string;
  private storage: preferences.Preferences | null = null;

  constructor(context: common.UIAbilityContext, endpoint: string) {
    this.context = context;
    // Never replay an operation to a different configured server.
    this.key = endpoint;
  }

  private getStorage(): preferences.Preferences {
    if (this.storage === null) {
      try {
        this.storage = preferences.getPreferencesSync(this.context, { name: 'chat_pending_operations' });
      } catch {
        throw new Error('设备存储暂不可用。');
      }
    }
    return this.storage;
  }

  read(): PendingOperation | null {
    try {
      const value = this.getStorage().getSync(this.key, '');
      if (value === '') {
        return null;
      }
      if (typeof value !== 'string') {
        throw new Error('未确认请求记录无法读取。');
      }
      const operation = JSON.parse(value) as PendingOperation;
      if (operation === null || typeof operation !== 'object' ||
        !['send', 'retry', 'stop'].includes(operation.kind) ||
        typeof operation.requestId !== 'string' || operation.requestId.length === 0 ||
        typeof operation.text !== 'string' || typeof operation.taskId !== 'string' ||
        (operation.kind !== 'send' && operation.taskId.length === 0)) {
        throw new Error('未确认请求记录不完整。');
      }
      return operation;
    } catch {
      throw new Error('无法读取未确认请求，暂不能发送。');
    }
  }

  save(operation: PendingOperation): void {
    try {
      const storage = this.getStorage();
      storage.putSync(this.key, JSON.stringify(operation));
      // Failure propagates to the ViewModel before it can issue HTTP.
      storage.flushSync();
    } catch {
      throw new Error('无法持久保存未确认请求。');
    }
  }

  clear(): void {
    try {
      const storage = this.getStorage();
      storage.deleteSync(this.key);
      storage.flushSync();
    } catch {
      throw new Error('无法清理已确认请求。');
    }
  }
}
