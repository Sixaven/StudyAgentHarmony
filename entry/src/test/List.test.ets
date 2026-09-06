import stopFlowTest from './chat/recovery/StopFlow.test';
import retryFlowTest from './chat/recovery/RetryFlow.test';
import recoveryFlowTest from './chat/recovery/RecoveryFlow.test';
import chatApiTest from './chat/transport/ChatApi.test';
import sseDecoderTest from './chat/transport/SseDecoder.test';
import taskEventsTest from './chat/state/TaskEvents.test';
import sendFlowTest from './chat/state/SendFlow.test';
import markdownTest from './chat/content/Markdown.test';
import localUnitTest from './LocalUnit.test';
import chatStateTest from './chat/state/ChatState.test';

export default function testsuite() {
  localUnitTest();
  chatStateTest();
  sendFlowTest();
  markdownTest();
  chatApiTest();
  sseDecoderTest();
  taskEventsTest();
  stopFlowTest();
  retryFlowTest();
  recoveryFlowTest();
}
