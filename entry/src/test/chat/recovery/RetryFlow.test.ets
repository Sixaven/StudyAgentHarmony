import { describe, it, expect } from '@ohos/hypium';
import { FakeChatService } from '../../../main/ets/chat/demo/FakeChatService';
import { createModel } from './RecoverySupport';
import { MemoryPendingRequestStore } from '../../../main/ets/chat/recovery/PendingRequestStore';
import { ChatServiceError, RequestResult } from '../../../main/ets/chat/contracts/ChatService';

class UnavailableLookup extends FakeChatService {
  async findRequest(requestId: string): Promise<RequestResult> {
    throw new ChatServiceError('network', 'unavailable', '查询不可用');
  }
}

export default function retryFlowTest() {
  describe('RetryFlow', () => {
    it('queriesAcceptedSendWithoutAddingAnotherUserBubble', 0, async () => {
      const service = new FakeChatService('empty');
      service.autoAdvance = false;
      service.loseNextResponse = true;
      const store = new MemoryPendingRequestStore();
      const model = createModel(service, store);
      await model.load();
      model.setDraft('  原文😀  ');
      await model.requestSend();
      const requestId = store.read()?.requestId;
      await model.requestRetry();
      expect(service.sendCount).assertEqual(1);
      expect(model.state.messages.length).assertEqual(1);
      expect(model.state.messages[0].requestId).assertEqual(requestId);
      expect(model.state.pending.length).assertEqual(0);
      model.dispose();
    });

    it('replaysOnlyAbsentRequestWithOriginalIdAndBody', 0, async () => {
      const service = new FakeChatService('empty');
      service.autoAdvance = false;
      const store = new MemoryPendingRequestStore();
      store.save({ kind: 'send', requestId: 'original-id', text: '  原文😀  ', taskId: '' });
      const model = createModel(service, store);
      await model.load();
      expect(service.sendCount).assertEqual(0);
      await model.requestRetry();
      expect(model.state.task?.requestId).assertEqual('original-id');
      expect(model.state.messages[0].content).assertEqual('  原文😀  ');
      expect(service.sendCount).assertEqual(1);
      model.dispose();
    });

    it('doesNotReplayWhenLookupIsUnavailable', 0, async () => {
      const service = new UnavailableLookup('empty');
      const store = new MemoryPendingRequestStore();
      store.save({ kind: 'send', requestId: 'original-id', text: '原文', taskId: '' });
      const model = createModel(service, store);
      await model.load();
      await model.requestRetry();
      expect(service.sendCount).assertEqual(0);
      expect(store.read()?.requestId).assertEqual('original-id');
      expect(model.state.canSend).assertFalse();
    });

    it('businessRetryUsesNewIdAndRetainsOriginalMessages', 0, async () => {
      const service = new FakeChatService('empty');
      service.autoAdvance = false;
      service.replyScenario = 'partial_failure';
      const model = createModel(service);
      await model.load();
      model.setDraft('问题');
      await model.requestSend();
      service.advance();
      service.advance();
      service.advance();
      const original = model.state.task;
      expect(model.state.canRetryTask).assertTrue();
      const retrying = model.requestRetry();
      await model.requestRetry();
      await retrying;
      expect(service.retryCount).assertEqual(1);
      expect(service.sendCount).assertEqual(1);
      expect(model.state.messages.length).assertEqual(2);
      expect(model.state.task?.requestId === original?.requestId).assertFalse();
      expect(model.state.canRetryTask).assertFalse();
      const old = await service.getTask(original!.taskId);
      expect(old.canRetry).assertFalse();
      expect(old.revision > original!.revision).assertTrue();
      model.dispose();
    });

    it('refreshesAfterOldRetryIsRejectedWithoutRerouting', 0, async () => {
      const service = new FakeChatService('empty');
      service.autoAdvance = false;
      service.replyScenario = 'partial_failure';
      const model = createModel(service);
      await model.load();
      model.setDraft('问题');
      await model.requestSend();
      service.advance();
      service.advance();
      service.advance();
      const successor = await service.send({ requestId: 'other-device', text: '新意图' });
      await model.requestRetry();
      expect(service.retryCount).assertEqual(0);
      expect(model.state.task?.taskId).assertEqual(successor.task.taskId);
      expect(model.state.notice).assertContain('不可重试');
      expect(model.state.canRetryTask).assertFalse();
      model.dispose();
    });

    it('replaysOneSuccessorAndRejectsADifferentRetryRequest', 0, async () => {
      const service = new FakeChatService('empty');
      service.autoAdvance = false;
      service.replyScenario = 'partial_failure';
      const original = await service.send({ requestId: 'send', text: '问题' });
      service.advance();
      service.advance();
      service.advance();
      const retry = await service.retry(original.task.taskId, 'retry');
      const replay = await service.retry(original.task.taskId, 'retry');
      expect(replay.taskId).assertEqual(retry.taskId);
      let rejected = false;
      try {
        await service.retry(original.task.taskId, 'different-retry');
      } catch (error) {
        if (error instanceof ChatServiceError) {
          rejected = error.detail.code === 'retry_not_allowed' &&
            error.detail.details?.existingTaskId === retry.taskId;
        }
      }
      expect(rejected).assertTrue();
      expect(service.retryCount).assertEqual(1);
    });

    it('lostRetryResponseRecoversTheSameSuccessor' , 0, async () => {
      const service = new FakeChatService('empty');
      service.autoAdvance = false;
      service.replyScenario = 'partial_failure';
      const model = createModel(service);
      await model.load();
      model.setDraft('问题');
      await model.requestSend();
      service.advance();
      service.advance();
      service.advance();
      service.loseNextResponse = true;
      await model.requestRetry();
      expect(model.state.phase).assertEqual('checking');
      await model.requestRetry();
      expect(service.retryCount).assertEqual(1);
      expect(model.state.task?.taskId).assertEqual('demo-retry-1');
      model.dispose();
    });
  });
}
