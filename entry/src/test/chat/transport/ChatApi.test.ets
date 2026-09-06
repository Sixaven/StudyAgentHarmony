import { ServiceError } from '../../../main/ets/chat/contracts/ChatTask';
import { describe, it, expect } from '@ohos/hypium';
import { ChatApi } from '../../../main/ets/chat/transport/ChatApi';
import { ChatServiceError, AcceptedMessage, RequestResult } from '../../../main/ets/chat/contracts/ChatService';
import { initialChat, sampleTask, sampleMessage } from '../../../main/ets/chat/demo/ChatFixtures';
import { ProtocolTransport } from './ProtocolTransport';
import { apiBaseUrl } from '../../../main/ets/chat/bootstrap/ChatConfig';

async function failureCode(action: () => Promise<Object>): Promise<string> {
  try {
    await action();
    return 'no_error';
  } catch (error) {
    if (error instanceof ChatServiceError) {
      return error.kind + ':' + error.detail.code;
    }
    return 'unexpected_error';
  }
}

export default function chatApiTest() {
  describe('ChatApi', () => {
    it('loadsNullableHistoryAndKeepsCitations', 0, async () => {
      const transport = new ProtocolTransport();
      const snapshot = initialChat();
      snapshot.messages[1].origin = 'legacy';
      transport.reply.body = JSON.stringify({ data: snapshot });
      const result = await new ChatApi(transport).loadChat();
      expect(result.messages[1].requestId).assertNull();
      expect(result.messages[1].citations[0].location.end).assertEqual(23);
      expect(transport.paths[0]).assertEqual('/chat');
    });

    it('returnsFailedTaskFromSuccessfulHttp', 0, async () => {
      const transport = new ProtocolTransport();
      transport.reply.body = JSON.stringify({ data: sampleTask('failed', 7) });
      const result = await new ChatApi(transport).getTask('demo-task');
      expect(result.status).assertEqual('failed');
      expect(result.canRetry).assertTrue();
    });

    it('acceptsTerminalSendAndPreservesOriginalText', 0, async () => {
      const transport = new ProtocolTransport();
      const saved = sampleMessage('demo-user', 1, ' 中文😀 ', 'user', 'demo-request');
      saved.taskId = 'demo-task';
      saved.origin = 'interactive';
      transport.reply = { status: 202, body: JSON.stringify({
        data: { userMessage: saved, task: sampleTask('completed', 4) } as AcceptedMessage
      }) };
      const result = await new ChatApi(transport).send({ requestId: 'demo-request', text: ' 中文😀 ' });
      expect(result.task.status).assertEqual('completed');
      expect(transport.bodies[0]).assertEqual('{"requestId":"demo-request","text":" 中文😀 "}');
    });

    it('preservesConfirmedConflictDetails', 0, async () => {
      const transport = new ProtocolTransport();
      transport.reply = { status: 409, body: JSON.stringify({
        requestId: 'retry-id',
        error: { code: 'retry_not_allowed', message: '已有后续任务',
          details: { existingTaskId: 'successor' } } as ServiceError
      }) };
      try {
        await new ChatApi(transport).retry('old', 'retry-id');
        expect(false).assertTrue();
      } catch (error) {
        expect(error instanceof ChatServiceError).assertTrue();
        const service = error as ChatServiceError;
        expect(service.kind).assertEqual('rejected');
        expect(service.detail.details?.existingTaskId).assertEqual('successor');
      }
    });

    it('acceptsBackendRejectionsWithoutOptionalRequestId', 0, async () => {
      const transport = new ProtocolTransport();
      const api = new ChatApi(transport);
      transport.reply = { status: 400,
        body: '{"error":{"code":"invalid_input","message":"输入无效"}}' };
      expect(await failureCode(() => api.send({ requestId: 'r', text: 'hi' })))
        .assertEqual('rejected:invalid_input');
      transport.reply = { status: 409,
        body: '{"error":{"code":"request_conflict","message":"请求冲突"}}' };
      expect(await failureCode(() => api.send({ requestId: 'r', text: 'hi' })))
        .assertEqual('rejected:request_conflict');
      transport.reply = { status: 404,
        body: '{"error":{"code":"not_found","message":"任务不存在"}}' };
      expect(await failureCode(() => api.stop('missing', 'r'))).assertEqual('rejected:not_found');
    });

    it('preservesBusyAndRetryDetailsWithoutRequestId', 0, async () => {
      const transport = new ProtocolTransport();
      const api = new ChatApi(transport);
      const codes = ['busy', 'retry_not_allowed'];
      for (let index = 0; index < codes.length; index++) {
        transport.reply = { status: 409, body: JSON.stringify({
          error: { code: codes[index], message: '已有任务',
            details: { existingTaskId: 'existing' } } as ServiceError
        }) };
        try {
          if (index === 0) {
            await api.send({ requestId: 'r', text: 'hi' });
          } else {
            await api.retry('old', 'r');
          }
          expect(false).assertTrue();
        } catch (error) {
          expect(error instanceof ChatServiceError).assertTrue();
          const failure = error as ChatServiceError;
          expect(failure.kind).assertEqual('rejected');
          expect(failure.detail.code).assertEqual(codes[index]);
          expect(failure.detail.details?.existingTaskId).assertEqual('existing');
        }
      }
    });

    it('validatesOptionalIdWhenPresentAndKeeps503WritesUnknown', 0, async () => {
      const transport = new ProtocolTransport();
      const api = new ChatApi(transport);
      for (const id of ['null', '123', '""', '"other"']) {
        transport.reply = { status: 409,
          body: '{"requestId":' + id + ',"error":{"code":"busy","message":"忙"}}' };
        expect(await failureCode(() => api.send({ requestId: 'r', text: 'hi' })))
          .assertEqual('network:protocol_error');
      }
      transport.reply = { status: 503,
        body: '{"error":{"code":"unavailable","message":"已接受结果暂不可读"}}' };
      expect(await failureCode(() => api.send({ requestId: 'r', text: 'hi' })))
        .assertEqual('network:unavailable');
      expect(await failureCode(() => api.stop('t', 'r'))).assertEqual('network:unavailable');
      expect(await failureCode(() => api.retry('t', 'r'))).assertEqual('network:unavailable');
    });

    it('doesNotTreatMalformedRejectionAsDefinitelyUnaccepted', 0, async () => {
      const transport = new ProtocolTransport();
      const api = new ChatApi(transport);
      transport.reply = { status: 503, body: '<html>proxy error</html>' };
      expect(await failureCode(() => api.send({ requestId: 'r', text: 'hi' })))
        .assertEqual('network:protocol_error');
      transport.reply.body = '{"requestId":"other","error":{"code":"unavailable","message":"失败"}}';
      expect(await failureCode(() => api.send({ requestId: 'r', text: 'hi' })))
        .assertEqual('network:protocol_error');
    });

    it('rejectsMalformedEnvelopeAndUnsafeRevision', 0, async () => {
      const transport = new ProtocolTransport();
      const api = new ChatApi(transport);
      const invalid: string[] = ['null', '[]', '{}', '{"data":null}', '{"data":{"revision":1}}'];
      for (let index = 0; index < invalid.length; index++) {
        transport.reply.body = invalid[index];
        expect(await failureCode(() => api.getTask('demo-task'))).assertEqual('network:protocol_error');
      }
      const snapshot = sampleTask('running');
      snapshot.revision = Number.MAX_SAFE_INTEGER + 1;
      transport.reply.body = JSON.stringify({ data: snapshot });
      expect(await failureCode(() => api.getTask('demo-task'))).assertEqual('network:protocol_error');
    });

    it('validatesRequiredMessageAndTaskFields', 0, async () => {
      const transport = new ProtocolTransport();
      const snapshot = initialChat();
      const body = JSON.stringify({ data: snapshot });
      const invalid = [
        body.replace('"role":"user"', '"role":"tool"'),
        body.replace('"draftId":null', '"draftId":"preview"'),
        body.replace('"sequence":2', '"sequence":1.5'),
        body.replace('"createdAt":"2026-09-06T00:00:00.000Z"', '"createdAt":"yesterday"'),
        body.replace('"origin":"interactive"', '"origin":"unknown"'),
        body.replace('"canRetry":false', '"canRetry":"false"')
      ];
      const api = new ChatApi(transport);
      for (let index = 0; index < invalid.length; index++) {
        transport.reply.body = invalid[index];
        expect(await failureCode(() => api.loadChat())).assertEqual('network:protocol_error');
      }
    });

    it('doesNotRetryUnknownPostAfterTimeoutOrDisconnect', 0, async () => {
      const transport = new ProtocolTransport();
      transport.failure = true;
      expect(await failureCode(() => new ChatApi(transport).send({ requestId: 'r', text: 'x' })))
        .assertEqual('network:network_error');
      expect(transport.paths.length).assertEqual(1);
    });

    it('encodesOpaqueCursorAndTaskId', 0, async () => {
      const transport = new ProtocolTransport();
      const api = new ChatApi(transport);
      transport.reply.body = '{"data":{"messages":[],"olderCursor":null}}';
      await api.loadOlder('a/b?&');
      expect(transport.paths[0]).assertEqual('/chat/messages?before=a%2Fb%3F%26&limit=50');
      const snapshot = sampleTask('completed');
      snapshot.taskId = 'a/b';
      transport.reply.body = JSON.stringify({ data: snapshot });
      await api.getTask('a/b');
      expect(transport.paths[1]).assertEqual('/tasks/a%2Fb');
    });

    it('validatesOperationIdentityAndStopQueryOriginalTask', 0, async () => {
      const transport = new ProtocolTransport();
      const api = new ChatApi(transport);
      transport.reply.body = JSON.stringify({
        data: { requestId: 'stop-id', kind: 'stop', task: sampleTask('stopping') } as RequestResult
      });
      expect((await api.findRequest('stop-id')).task.requestId).assertEqual('demo-request');
      transport.reply.body = JSON.stringify({ data: sampleTask('completed') });
      expect(await failureCode(() => api.getTask('other'))).assertEqual('network:protocol_error');
      expect(await failureCode(() => api.retry('demo-task', 'new-id'))).assertEqual('network:protocol_error');
      await api.stop('demo-task', 'stop-id');
      expect(transport.bodies[transport.bodies.length - 1]).assertEqual('{"requestId":"stop-id"}');
    });

    it('requiresExplicitReachableBaseUrl', 0, () => {
      let rejected = false;
      try {
        apiBaseUrl({ mode: 'real', baseUrl: '', requestTimeoutMs: 10, streamIdleTimeoutMs: 100 });
      } catch {
        rejected = true;
      }
      expect(rejected).assertTrue();
      expect(apiBaseUrl({ mode: 'real', baseUrl: 'http://192.0.2.1:8787/api/v1/',
        requestTimeoutMs: 10, streamIdleTimeoutMs: 100 })).assertEqual('http://192.0.2.1:8787/api/v1');
    });
  });
}
