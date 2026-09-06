import { describe, it, expect } from '@ohos/hypium';
import { FakeChatService } from '../../../main/ets/chat/demo/FakeChatService';
import { createModel } from './RecoverySupport';
import { MemoryPendingRequestStore } from '../../../main/ets/chat/recovery/PendingRequestStore';

export default function stopFlowTest() {
  describe('StopFlow', () => {
    it('waitsForTerminalAfter202AndBlocksDuplicateStop', 0, async () => {
      const service = new FakeChatService('empty');
      service.autoAdvance = false;
      const model = createModel(service);
      await model.load();
      model.setDraft('问题');
      await model.requestSend();
      service.advance();
      service.advance();
      model.setDraft('保留的草稿');
      const stopping = model.requestStop();
      await model.requestStop();
      await stopping;
      expect(service.stopCount).assertEqual(1);
      expect(model.state.phase).assertEqual('stopping');
      expect(model.state.canSend).assertFalse();
      expect(model.state.messages.length).assertEqual(2);
      service.advance();
      expect(model.state.task?.status).assertEqual('cancelled');
      expect(model.state.canSend).assertTrue();
      expect(model.state.draft).assertEqual('保留的草稿');
      model.dispose();
    });

    it('keepsCompletionWhenTerminalArrivesBeforeStopResponse', 0, async () => {
      const service = new FakeChatService('empty');
      service.autoAdvance = false;
      service.stopCompletesFirst = true;
      const model = createModel(service);
      await model.load();
      model.setDraft('问题');
      await model.requestSend();
      await model.requestStop();
      expect(model.state.task?.status).assertEqual('completed');
      expect(model.state.phase).assertEqual('ready');
      model.dispose();
    });

    it('queriesLostStopUsingIndependentRequestId', 0, async () => {
      const service = new FakeChatService('empty');
      service.autoAdvance = false;
      const store = new MemoryPendingRequestStore();
      const model = createModel(service, store);
      await model.load();
      model.setDraft('问题');
      await model.requestSend();
      const sendId = model.state.task?.requestId;
      service.loseNextResponse = true;
      await model.requestStop();
      expect(store.read()?.kind).assertEqual('stop');
      expect(store.read()?.requestId === sendId).assertFalse();
      expect(model.state.phase).assertEqual('checking');
      service.advance();
      expect(model.state.canRetry).assertTrue();
      await model.requestRetry();
      expect(service.stopCount).assertEqual(1);
      expect(store.read() === null).assertTrue();
      expect(model.state.phase).assertEqual('ready');
      expect(model.state.task?.status).assertEqual('cancelled');
      model.dispose();
    });

    it('doesNotStopWhenSendIdentityIsUnknown', 0, async () => {
      const service = new FakeChatService('empty');
      service.autoAdvance = false;
      service.loseNextResponse = true;
      const model = createModel(service);
      await model.load();
      model.setDraft('问题');
      await model.requestSend();
      await model.requestStop();
      expect(service.stopCount).assertEqual(0);
      expect(model.state.canStop).assertFalse();
      await model.requestRetry();
      expect(model.state.canStop).assertTrue();
      model.dispose();
    });
  });
}
