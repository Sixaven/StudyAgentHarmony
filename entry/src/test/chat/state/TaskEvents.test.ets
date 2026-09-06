import { describe, it, expect } from '@ohos/hypium';
import { ChatViewModel } from '../../../main/ets/chat/state/ChatViewModel';
import { FakeChatService } from '../../../main/ets/chat/demo/FakeChatService';
import { sampleTask, sampleMessage } from '../../../main/ets/chat/demo/ChatFixtures';

export default function taskEventsTest() {
  describe('TaskEvents', () => {
    it('mergesMessagesFromOlderSnapshotsWithoutRollingBackState', 0, () => {
      const model = new ChatViewModel(new FakeChatService());
      model.applyTask(sampleTask('stopping', 9));
      const older = sampleTask('running', 3);
      older.savedMessages = [sampleMessage('saved', 1, '已保存')];
      model.applyTask(older);
      model.applyTask(older);
      expect(model.state.task?.revision).assertEqual(9);
      expect(model.state.phase).assertEqual('stopping');
      expect(model.state.messages.length).assertEqual(1);
    });

    it('doesNotCompareRevisionsAcrossTasks', 0, () => {
      const model = new ChatViewModel(new FakeChatService());
      model.applyTask(sampleTask('completed', 99));
      const next = sampleTask('running', 1);
      next.taskId = 'next';
      model.applyTask(next);
      expect(model.state.task?.taskId).assertEqual('next');
      expect(model.state.phase).assertEqual('processing');
    });

    it('savedEventRevisionPreventsStaleTerminalFromUnlockingSend', 0, async () => {
      const service = new FakeChatService('empty');
      service.autoAdvance = false;
      const model = new ChatViewModel(service);
      await model.load();
      model.setDraft('学习');
      await model.requestSend();
      const current = model.state.task!;
      const saved = sampleMessage('new-saved', 10, '完整回复');
      service.emit({ id: '2', event: 'message_saved', chatId: current.chatId,
        taskId: current.taskId, requestId: current.requestId, taskRevision: 8, message: saved });
      const older = sampleTask('completed', 4);
      older.taskId = current.taskId;
      older.requestId = current.requestId;
      service.emit({ id: '3', event: 'task_snapshot', chatId: current.chatId,
        taskId: current.taskId, requestId: current.requestId, task: older });
      expect(model.state.phase).assertEqual('processing');
      expect(model.state.messages.some((item) => item.messageId === 'new-saved')).assertTrue();
      const failed = sampleTask('failed', 9);
      failed.taskId = current.taskId;
      failed.requestId = current.requestId;
      service.emit({ id: '4', event: 'task_finished', chatId: current.chatId,
        taskId: current.taskId, requestId: current.requestId, task: failed });
      expect(model.state.phase).assertEqual('failed');
      expect(model.state.messages.some((item) => item.messageId === 'new-saved')).assertTrue();
      model.dispose();
    });

    it('disconnectRetainsSavedMessagesAndBlocksNewSends', 0, async () => {
      const service = new FakeChatService('empty');
      service.autoAdvance = false;
      service.replyScenario = 'lesson_question';
      const model = new ChatViewModel(service);
      await model.load();
      model.setDraft('学习');
      await model.requestSend();
      service.advance();
      const count = model.state.messages.length;
      model.setDraft('下一条草稿');
      service.failConnection();
      expect(model.state.phase).assertEqual('checking');
      expect(model.state.canSend).assertFalse();
      expect(model.state.messages.length).assertEqual(count);
      expect(model.state.draft).assertEqual('下一条草稿');
      model.dispose();
    });
  });
}
