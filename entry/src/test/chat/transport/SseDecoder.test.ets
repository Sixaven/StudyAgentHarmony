import { describe, it, expect } from '@ohos/hypium';
import { SseDecoder, SseFrame } from '../../../main/ets/chat/streaming/SseDecoder';
import { chatEvent } from '../../../main/ets/chat/streaming/ChatEvents';
import { ProtocolTransport, utf8, frame, SsePayload } from './ProtocolTransport';
import { ChatApi } from '../../../main/ets/chat/transport/ChatApi';
import { ChatEvent } from '../../../main/ets/chat/contracts/ChatTask';
import { ChatServiceError } from '../../../main/ets/chat/contracts/ChatService';
import { sampleTask, sampleMessage } from '../../../main/ets/chat/demo/ChatFixtures';

export default function sseDecoderTest() {
  describe('SseDecoder', () => {
    it('decodesSplitChineseEmojiCrLfAndMultipleDataLines', 0, () => {
      const decoder = new SseDecoder();
      const frames: SseFrame[] = [];
      const bytes = utf8('\uFEFF: heartbeat\r\nid: 1\r\nevent: message_saved\r\ndata: 中文😀\r\ndata: 第二行\r\n\r\n');
      for (let index = 0; index < bytes.length; index++) {
        decoder.push(bytes.subarray(index, index + 1), (value: SseFrame) => { frames.push(value); });
      }
      decoder.finish();
      expect(frames.length).assertEqual(1);
      expect(frames[0].data).assertEqual('中文😀\n第二行');
      expect(frames[0].id).assertEqual('1');
    });

    it('handlesManyFramesAndCommentHeartbeatsInOneChunk', 0, () => {
      const frames: SseFrame[] = [];
      const decoder = new SseDecoder();
      decoder.push(utf8(': ping\n\nid: 1\nevent: x\ndata: {}\n\nid: 2\ndata: {}\n\n'),
        (value: SseFrame) => { frames.push(value); });
      expect(frames.length).assertEqual(2);
      expect(frames[1].id).assertEqual('2');
    });

    it('boundsIncompleteLinesAndAccumulatedData', 0, () => {
      const invalid = ['data: ' + 'x'.repeat(50), 'data: abcdef\ndata: abcdef\ndata: abcdef\n'];
      for (let index = 0; index < invalid.length; index++) {
        let failed = false;
        try {
          new SseDecoder(25).push(utf8(invalid[index]), () => {});
        } catch {
          failed = true;
        }
        expect(failed).assertTrue();
      }
    });

    it('rejectsMalformedAndTruncatedUtf8', 0, () => {
      const invalid: number[][] = [[0xc0, 0xaf], [0xed, 0xa0, 0x80], [0xf4, 0x90, 0x80, 0x80], [0xe4]];
      for (let index = 0; index < invalid.length; index++) {
        let failed = false;
        try {
          const decoder = new SseDecoder();
          decoder.push(new Uint8Array(invalid[index]), () => {});
          decoder.finish();
        } catch {
          failed = true;
        }
        expect(failed).assertTrue();
      }
    });

    it('ignoresUnknownEventsButRejectsMalformedKnownJson', 0, () => {
      expect(chatEvent({ id: '1', event: 'future_event', data: 'not json' })).assertNull();
      let failed = false;
      try {
        chatEvent({ id: '2', event: 'task_snapshot', data: '{' });
      } catch {
        failed = true;
      }
      expect(failed).assertTrue();
      const event = chatEvent({ id: '3', event: 'task_progress', data:
        '{"chatId":"c","taskId":"t","requestId":"r","phase":"future_phase"}' });
      expect(event?.phase).assertEqual('processing');
    });

    it('reportsEofWithoutTerminalAndReleasesOnlyObservation', 0, () => {
      const transport = new ProtocolTransport();
      const errors: string[] = [];
      const events: ChatEvent[] = [];
      const subscription = new ChatApi(transport).subscribe('demo-task', {
        onEvent: (event: ChatEvent) => { events.push(event); },
        onError: (error: ChatServiceError) => { errors.push(error.detail.code); }
      });
      transport.observers[0].onData(frame(1, 'task_snapshot', {
        chatId: 'demo-chat', taskId: 'demo-task', requestId: 'demo-request', task: sampleTask('running')
      }));
      transport.observers[0].onEnd();
      expect(errors.length).assertEqual(1);
      expect(events.length).assertEqual(1);
      expect(transport.disposed[0]).assertTrue();
      subscription.dispose();
      expect(transport.methods.length).assertEqual(0);
    });

    it('terminalInitialSnapshotClosesWithoutFinishedEventOrEofError', 0, () => {
      const transport = new ProtocolTransport();
      let errors = 0;
      let events = 0;
      new ChatApi(transport).subscribe('demo-task', {
        onEvent: () => { events++; }, onError: () => { errors++; }
      });
      transport.observers[0].onData(frame(19, 'task_snapshot', {
        chatId: 'demo-chat', taskId: 'demo-task', requestId: 'demo-request', task: sampleTask('failed', 5)
      }));
      transport.observers[0].onEnd();
      expect(events).assertEqual(1);
      expect(errors).assertEqual(0);
      expect(transport.disposed[0]).assertTrue();
    });

    it('deduplicatesConnectionIdsAndReconcilesGapWithFreshSnapshot', 0, () => {
      const transport = new ProtocolTransport();
      let errors = 0;
      const events: ChatEvent[] = [];
      const subscription = new ChatApi(transport).subscribe('demo-task', {
        onEvent: (event: ChatEvent) => { events.push(event); }, onError: () => { errors++; }
      });
      const data: SsePayload = { chatId: 'demo-chat', taskId: 'demo-task', requestId: 'demo-request',
        task: sampleTask('running') };
      transport.observers[0].onData(frame(10, 'task_snapshot', data));
      transport.observers[0].onData(frame(10, 'task_snapshot', data));
      transport.observers[0].onData(frame(12, 'task_snapshot', data));
      expect(transport.observers.length).assertEqual(2);
      expect(transport.disposed[0]).assertTrue();
      transport.observers[0].onEnd();
      transport.observers[0].onData(frame(13, 'task_finished', data));
      transport.observers[1].onData(frame(1, 'task_snapshot', data));
      expect(events.length).assertEqual(2);
      expect(errors).assertEqual(0);
      transport.observers[1].onData(frame(3, 'task_snapshot', data));
      expect(errors).assertEqual(1);
      expect(transport.observers.length).assertEqual(2);
      subscription.dispose();
    });

    it('preservesSavedRevisionAcrossGapReconnection', 0, () => {
      const transport = new ProtocolTransport();
      let errors = 0;
      new ChatApi(transport).subscribe('demo-task', {
        onEvent: () => {}, onError: () => { errors++; }
      });
      const payload: SsePayload = { chatId: 'demo-chat', taskId: 'demo-task',
        requestId: 'demo-request', task: sampleTask('running', 1) };
      transport.observers[0].onData(frame(1, 'task_snapshot', payload));
      transport.observers[0].onData(frame(2, 'message_saved', {
        chatId: 'demo-chat', taskId: 'demo-task', requestId: 'demo-request',
        taskRevision: 8, message: sampleMessage('saved', 2, '保存结果')
      }));
      transport.observers[0].onData(frame(4, 'task_snapshot', payload));
      payload.task = sampleTask('completed', 4);
      transport.observers[1].onData(frame(1, 'task_snapshot', payload));
      expect(transport.disposed[1]).assertFalse();
      payload.task = sampleTask('completed', 9);
      transport.observers[1].onData(frame(2, 'task_finished', payload));
      expect(transport.disposed[1]).assertTrue();
      expect(errors).assertEqual(0);
    });

    it('rejectsMissingInitialSnapshotAndWrongTaskIdentity', 0, () => {
      const transport = new ProtocolTransport();
      let errors = 0;
      const api = new ChatApi(transport);
      api.subscribe('demo-task', { onEvent: () => {}, onError: () => { errors++; } });
      transport.observers[0].onData(frame(1, 'task_progress', {
        chatId: 'demo-chat', taskId: 'demo-task', requestId: 'demo-request', phase: 'processing'
      }));
      api.subscribe('demo-task', { onEvent: () => {}, onError: () => { errors++; } });
      const wrong = sampleTask('running');
      wrong.taskId = 'wrong';
      transport.observers[1].onData(frame(1, 'task_snapshot', {
        chatId: 'demo-chat', taskId: 'wrong', requestId: 'demo-request', task: wrong
      }));
      expect(errors).assertEqual(2);
    });
  });
}
