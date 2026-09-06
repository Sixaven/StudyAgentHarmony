import { ChatServiceError } from '../../../main/ets/chat/contracts/ChatService';
import { describe, it, expect } from '@ohos/hypium';
import { sampleMessage, sampleTask, olderPage, initialChat, partialFailure } from '../../../main/ets/chat/demo/ChatFixtures';
import { FakeChatService } from '../../../main/ets/chat/demo/FakeChatService';
import { ChatViewModel } from '../../../main/ets/chat/state/ChatViewModel';
import { mergeMessages, remainingPending } from '../../../main/ets/chat/state/MessageCollection';
import { PendingMessage } from '../../../main/ets/chat/contracts/ChatMessage';

export default function chatStateTest() {
  describe('ChatState', () => {
    it('preservesSuccessorIdWhenConvertingRejectedError', 0, () => {
      const error = ChatServiceError.fromServiceError({
        code: 'retry_not_allowed', message: '已有后继任务。',
        details: { existingTaskId: 'successor-task' }
      });
      expect(error.kind).assertEqual('rejected');
      expect(error.detail.code).assertEqual('retry_not_allowed');
      expect(error.detail.details?.existingTaskId).assertEqual('successor-task');
      expect(error.message).assertEqual('已有后继任务。');
    });

    it('doesNotInventDetailsForOtherRejectionsOrNetworkErrors', 0, () => {
      const error = ChatServiceError.fromServiceError({
        code: 'retry_not_allowed', message: '当前任务不可重试。'
      });
      expect(error.detail.details === undefined).assertTrue();
      const network = new ChatServiceError('network', 'unavailable', '连接失败。');
      expect(network.kind).assertEqual('network');
      expect(network.detail.details === undefined).assertTrue();
    });

    it('mergesOverlappingPagesByIdentityInSequenceOrder', 0, () => {
      const merged = mergeMessages(initialChat().messages, olderPage().messages);
      expect(merged.length).assertEqual(3);
      expect(merged[0].sequence).assertEqual(1);
      expect(merged[2].sequence).assertEqual(3);
      expect(merged[0].origin).assertEqual('legacy');
      expect(merged[0].requestId === null).assertTrue();
    });

    it('preservesDifferentIdsWithSameContentAndOriginalOwnership', 0, () => {
      const first = sampleMessage('a', 2, '相同正文', 'user', 'original');
      const second = sampleMessage('b', 1, '相同正文');
      const replay = sampleMessage('a', 2, '被错误改写', 'user', 'retry');
      const merged = mergeMessages([first], [second, replay]);
      expect(merged.length).assertEqual(2);
      expect(merged[1].requestId).assertEqual('original');
      expect(merged[1].content).assertEqual('相同正文');
    });

    it('onlySavedUserMessageAcknowledgesPendingRequest', 0, () => {
      const pending: PendingMessage[] = [{ requestId: 'request', text: '草稿' }];
      const assistant = sampleMessage('a', 2, '回复', 'assistant', 'request');
      expect(remainingPending(pending, [assistant]).length).assertEqual(1);
      const user = sampleMessage('u', 1, '草稿', 'user', 'request');
      expect(remainingPending(pending, [assistant, user]).length).assertEqual(0);
    });

    it('retriesInitialLoadWithoutLosingDraftOrAllowingPrematureSend', 0, async () => {
      const service = new FakeChatService('loading_error');
      const model = new ChatViewModel(service);
      model.setDraft('正在写的新问题');
      await model.load();
      expect(model.state.canRetryLoad).assertTrue();
      expect(model.state.canSend).assertFalse();
      service.scenario = 'ready';
      await model.load();
      expect(model.state.phase).assertEqual('ready');
      expect(model.state.draft).assertEqual('正在写的新问题');
      expect(model.state.canSend).assertTrue();
    });

    it('holdsSendWhileActiveTaskNeedsReconciliation', 0, async () => {
      const model = new ChatViewModel(new FakeChatService('running'));
      await model.load();
      model.setDraft('下一条草稿');
      expect(model.state.phase).assertEqual('processing');
      model.dispose();
      expect(model.state.canSend).assertFalse();
      expect(model.state.draft).assertEqual('下一条草稿');
    });

    it('ignoresOldRevisionsAndKeepsSavedPartialResults', 0, () => {
      const model = new ChatViewModel(new FakeChatService());
      model.setDraft('保留草稿');
      model.applyTask(partialFailure());
      model.applyTask(sampleTask('running', 1));
      expect(model.state.phase).assertEqual('failed');
      expect(model.state.messages.length).assertEqual(1);
      expect(model.state.draft).assertEqual('保留草稿');
    });

    it('paginationKeepsDraftAndDeduplicatesAcrossReloads', 0, async () => {
      const model = new ChatViewModel(new FakeChatService());
      await model.load();
      model.setDraft('我的草稿');
      await model.loadOlder();
      await model.load();
      expect(model.state.messages.length).assertEqual(3);
      expect(model.state.messages[0].sequence).assertEqual(1);
      expect(model.state.draft).assertEqual('我的草稿');
    });

    it('disposalDiscardsInFlightInitialLoad', 0, async () => {
      const model = new ChatViewModel(new FakeChatService());
      const loading = model.load();
      model.dispose();
      await loading;
      expect(model.state.initialized).assertFalse();
      expect(model.state.messages.length).assertEqual(0);
    });
  });
}
