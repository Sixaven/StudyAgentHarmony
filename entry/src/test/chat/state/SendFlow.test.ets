import { describe, it, expect } from '@ohos/hypium';
import { FakeChatService } from '../../../main/ets/chat/demo/FakeChatService';
import { ReplyScenario } from '../../../main/ets/chat/demo/FakeReplies';
import { ChatViewModel } from '../../../main/ets/chat/state/ChatViewModel';
import { codePointCount } from '../../../main/ets/chat/state/InputText';
import { AcceptedMessage, ChatServiceError, SendRequest, ChatObserver,
  ChatSubscription } from '../../../main/ets/chat/contracts/ChatService';
import { ChatEvent } from '../../../main/ets/chat/contracts/ChatTask';

class DelayedService extends FakeChatService {
  private accept: ((value: AcceptedMessage) => void) | null = null;
  private rejectSend: ((reason: ChatServiceError) => void) | null = null;
  private captured: SendRequest | null = null;

  async send(request: SendRequest): Promise<AcceptedMessage> {
    this.captured = request;
    return new Promise<AcceptedMessage>((resolve, reject) => {
      this.accept = resolve;
      this.rejectSend = reject;
    });
  }

  async release(): Promise<void> {
    if (this.captured !== null && this.accept !== null) {
      this.accept(await super.send(this.captured));
    }
  }

  fail(kind: 'rejected' | 'network'): void {
    if (this.rejectSend !== null) {
      this.rejectSend(new ChatServiceError(kind, 'unavailable', '未完成发送'));
    }
  }
}

class AlreadyCompletedService extends FakeChatService {
  async send(request: SendRequest): Promise<AcceptedMessage> {
    const accepted = await super.send(request);
    this.advance();
    return { userMessage: accepted.userMessage, task: await this.getTask(accepted.task.taskId) };
  }
}

class TerminalSubscriptionService extends FakeChatService {
  released: boolean = false;

  subscribe(taskId: string, observer: ChatObserver): ChatSubscription {
    const subscription = super.subscribe(taskId, observer);
    this.advance();
    return { dispose: () => {
      this.released = true;
      subscription.dispose();
    } };
  }
}

export default function sendFlowTest() {
  describe('SendFlow', () => {
    it('countsUnicodeCodePointsAndRejectsEmptyOrLongInput', 0, async () => {
      const service = new FakeChatService('empty');
      service.autoAdvance = false;
      const model = new ChatViewModel(service);
      await model.load();
      expect(codePointCount('中文😀')).assertEqual(3);
      model.setDraft(' \n\t');
      await model.requestSend();
      model.setDraft('😀'.repeat(2001));
      expect(model.state.canSend).assertFalse();
      await model.requestSend();
      expect(service.sendCount).assertEqual(0);
      model.setDraft('😀'.repeat(2000));
      expect(model.state.canSend).assertTrue();
      await model.requestSend();
      expect(service.sendCount).assertEqual(1);
      model.dispose();
    });

    it('sendsOriginalTextOnceAndKeepsDraftWrittenBeforeAcceptance', 0, async () => {
      const service = new DelayedService('empty');
      service.autoAdvance = false;
      const model = new ChatViewModel(service);
      await model.load();
      model.setDraft('  中文😀\n');
      const sending = model.requestSend();
      expect(model.state.phase).assertEqual('sending');
      expect(model.state.pending[0].text).assertEqual('  中文😀\n');
      model.setDraft('下一条草稿');
      await model.requestSend();
      await service.release();
      await sending;
      expect(service.sendCount).assertEqual(1);
      expect(model.state.pending.length).assertEqual(0);
      expect(model.state.messages[0].content).assertEqual('  中文😀\n');
      expect(model.state.draft).assertEqual('下一条草稿');
      expect(model.state.canSend).assertFalse();
      model.dispose();
    });

    it('restoresRejectedTextOnlyWhenNoLaterDraftEditOccurred', 0, async () => {
      const service = new DelayedService('empty');
      const model = new ChatViewModel(service);
      await model.load();
      model.setDraft('原文');
      const first = model.requestSend();
      service.fail('rejected');
      await first;
      expect(model.state.draft).assertEqual('原文');
      expect(model.state.messages.length).assertEqual(0);
      expect(model.state.pending.length).assertEqual(0);
      const second = model.requestSend();
      model.setDraft('新的问题');
      service.fail('rejected');
      await second;
      expect(model.state.draft).assertEqual('新的问题');
      const third = model.requestSend();
      model.setDraft('');
      service.fail('rejected');
      await third;
      expect(model.state.draft).assertEqual('');
    });

    it('holdsUnknownAcceptanceWithoutCreatingAnotherSend', 0, async () => {
      const service = new DelayedService('empty');
      const model = new ChatViewModel(service);
      await model.load();
      model.setDraft('我的问题');
      const sending = model.requestSend();
      model.setDraft('下一个问题');
      service.fail('network');
      await sending;
      expect(model.state.phase).assertEqual('checking');
      expect(model.state.pending.length).assertEqual(1);
      expect(model.state.canSend).assertFalse();
    });

    it('showsSavedMessagesBeforeTerminalAndPreservesPartialFailure', 0, async () => {
      const service = new FakeChatService('empty');
      service.autoAdvance = false;
      service.replyScenario = 'partial_failure';
      const model = new ChatViewModel(service);
      await model.load();
      model.setDraft('问题');
      await model.requestSend();
      service.advance();
      expect(model.state.messages.length).assertEqual(1);
      service.advance();
      expect(model.state.messages.length).assertEqual(2);
      expect(model.state.phase).assertEqual('processing');
      model.setDraft('未发送的草稿');
      service.advance();
      expect(model.state.phase).assertEqual('failed');
      expect(model.state.messages.length).assertEqual(2);
      expect(model.state.draft).assertEqual('未发送的草稿');
      model.dispose();
    });

    it('rendersClarificationAndNoEvidenceAsAcceptedSavedReplies', 0, async () => {
      const scenarios: ReplyScenario[] = ['clarification', 'no_evidence'];
      for (const scenario of scenarios) {
        const service = new FakeChatService('empty');
        service.autoAdvance = false;
        service.replyScenario = scenario;
        const model = new ChatViewModel(service);
        await model.load();
        model.setDraft('问题');
        await model.requestSend();
        service.advance();
        service.advance();
        service.advance();
        expect(model.state.phase).assertEqual('ready');
        expect(model.state.messages.length).assertEqual(2);
        expect(model.state.messages[1].citations.length).assertEqual(0);
        expect(model.state.task?.outcome).assertEqual(scenario === 'clarification' ? 'needs_clarification' : 'no_evidence');
        model.dispose();
      }
    });

    it('showsLessonThenQuestionAndDeduplicatesSavedReplays', 0, async () => {
      const scenarios: ReplyScenario[] = ['lesson_question', 'duplicate_events'];
      for (const scenario of scenarios) {
        const service = new FakeChatService('empty');
        service.autoAdvance = false;
        service.replyScenario = scenario;
        const model = new ChatViewModel(service);
        await model.load();
        model.setDraft('问题');
        await model.requestSend();
        service.advance();
        service.advance();
        expect(model.state.messages.length).assertEqual(2);
        service.advance();
        service.advance();
        expect(model.state.messages.length).assertEqual(scenario === 'lesson_question' ? 3 : 2);
        expect(model.state.phase).assertEqual('ready');
        model.dispose();
      }
    });

    it('finishesFromSynchronousTerminalSnapshotAndDisposesObserver', 0, async () => {
      const service = new TerminalSubscriptionService('empty');
      service.autoAdvance = false;
      service.replyScenario = 'terminal_snapshot';
      const model = new ChatViewModel(service);
      await model.load();
      model.setDraft('问题');
      await model.requestSend();
      expect(model.state.phase).assertEqual('ready');
      expect(model.state.messages.length).assertEqual(2);
      expect(service.released).assertTrue();
      service.failConnection();
      expect(model.state.phase).assertEqual('ready');
    });

    it('acceptsAlreadyTerminalSendResponseWithoutWaitingForEvents', 0, async () => {
      const service = new AlreadyCompletedService('empty');
      service.autoAdvance = false;
      service.replyScenario = 'terminal_snapshot';
      const model = new ChatViewModel(service);
      await model.load();
      model.setDraft('问题');
      await model.requestSend();
      expect(model.state.phase).assertEqual('ready');
      expect(model.state.messages.length).assertEqual(2);
      expect(model.state.pending.length).assertEqual(0);
      model.dispose();
    });

    it('ignoresLateAcceptanceAfterDisposal', 0, async () => {
      const service = new DelayedService('empty');
      service.autoAdvance = false;
      const model = new ChatViewModel(service);
      await model.load();
      model.setDraft('问题');
      const sending = model.requestSend();
      model.dispose();
      await service.release();
      await sending;
      expect(model.state.messages.length).assertEqual(0);
    });

    it('holdsSendWhenObservationBreaksAndIgnoresOtherTaskEvents', 0, async () => {
      const service = new FakeChatService('empty');
      service.autoAdvance = false;
      const model = new ChatViewModel(service);
      await model.load();
      model.setDraft('问题');
      await model.requestSend();
      const unrelated: ChatEvent = { id: 'other', event: 'task_progress', chatId: 'demo-chat',
        taskId: 'another-task', requestId: 'another-request', phase: 'saving' };
      service.emit(unrelated);
      expect(model.state.notice).assertEqual('');
      service.failConnection();
      model.setDraft('草稿');
      expect(model.state.phase).assertEqual('checking');
      expect(model.state.canSend).assertFalse();
      service.advance();
      service.advance();
      expect(model.state.messages.length).assertEqual(1);
      model.dispose();
    });
  });
}
