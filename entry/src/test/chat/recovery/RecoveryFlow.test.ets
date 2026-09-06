import { ChatApi } from '../../../main/ets/chat/transport/ChatApi';
import { RcpTransport } from '../../../main/ets/chat/transport/RcpTransport';
import { describe, it, expect } from '@ohos/hypium';
import { FakeChatService } from '../../../main/ets/chat/demo/FakeChatService';
import { createModel } from './RecoverySupport';
import { MemoryPendingRequestStore, PendingOperation } from '../../../main/ets/chat/recovery/PendingRequestStore';
import { ChatSnapshot } from '../../../main/ets/chat/contracts/ChatService';
import { partialFailure } from '../../../main/ets/chat/demo/ChatFixtures';

class FailedStore extends MemoryPendingRequestStore {
  save(operation: PendingOperation): void {
    throw new Error('磁盘不可写');
  }
}

class RestartedService extends FakeChatService {
  async loadChat(): Promise<ChatSnapshot> {
    const snapshot = await super.loadChat();
    snapshot.latestTask = partialFailure();
    snapshot.latestTask.reason = 'server_restarted';
    snapshot.latestTask.canRetry = false;
    return snapshot;
  }
}

export default function recoveryFlowTest() {
  describe('RecoveryFlow', () => {
    it('showsInvalidRealConfigurationWithoutCrashingAbilityConstruction', 0, async () => {
      const api = new ChatApi(new RcpTransport({ mode: 'real', baseUrl: '',
        requestTimeoutMs: 15000, streamIdleTimeoutMs: 90000 }));
      const model = createModel(api);
      await model.load();
      expect(model.state.canRetryLoad).assertTrue();
      expect(model.state.canSend).assertFalse();
      api.close();
    });

    it('doesNotWriteNetworkWhenLocalJournalFails' , 0, async () => {
      const service = new FakeChatService('empty');
      const model = createModel(service, new FailedStore());
      await model.load();
      model.setDraft('原文');
      await model.requestSend();
      expect(service.sendCount).assertEqual(0);
      expect(model.state.draft).assertEqual('原文');
      expect(model.state.notice).assertContain('尚未发送');
    });

    it('reopensAfterLostAcceptanceAndResumesObservation', 0, async () => {
      const service = new FakeChatService('empty');
      service.autoAdvance = false;
      service.loseNextResponse = true;
      const store = new MemoryPendingRequestStore();
      const first = createModel(service, store);
      await first.load();
      first.setDraft('原文');
      await first.requestSend();
      first.dispose();
      const reopened = createModel(service, store);
      await reopened.load();
      expect(reopened.state.pending.length).assertEqual(0);
      expect(reopened.state.phase).assertEqual('processing');
      service.advance();
      service.advance();
      service.advance();
      expect(reopened.state.phase).assertEqual('ready');
      expect(service.sendCount).assertEqual(1);
      expect(store.read() === null).assertTrue();
      reopened.dispose();
    });

    it('backgroundReleasesObservationWithoutStoppingAndRestoresSavedResults', 0, async () => {
      const service = new FakeChatService('empty');
      service.autoAdvance = false;
      const model = createModel(service);
      await model.load();
      model.setDraft('问题');
      await model.requestSend();
      model.setDraft('新草稿');
      model.dispose();
      service.advance();
      service.advance();
      service.advance();
      expect(model.state.messages.length).assertEqual(1);
      expect(service.stopCount).assertEqual(0);
      await model.load();
      expect(model.state.messages.length).assertEqual(2);
      expect(model.state.phase).assertEqual('ready');
      expect(model.state.draft).assertEqual('新草稿');
      model.dispose();
    });

    it('keepsRestartReasonWithoutAutomaticallyRetryingBusiness', 0, async () => {
      const service = new RestartedService();
      const model = createModel(service);
      await model.load();
      expect(model.state.task?.reason).assertEqual('server_restarted');
      expect(model.state.notice).assertContain('服务已重启');
      expect(model.state.canRetryTask).assertFalse();
      expect(service.retryCount).assertEqual(0);
      expect(model.state.messages.length > 0).assertTrue();
    });

    it('paginatesAndPreservesLegacyMessagesOnRecovery', 0, async () => {
      const model = createModel(new FakeChatService());
      await model.load();
      await model.loadOlder();
      const count = model.state.messages.length;
      model.dispose();
      await model.load();
      expect(model.state.messages.length).assertEqual(count);
      expect(model.state.messages[0].origin).assertEqual('legacy');
      expect(model.state.messages[0].requestId === null).assertTrue();
      model.dispose();
    });
  });
}
