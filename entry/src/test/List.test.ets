import sendFlowTest from './chat/state/SendFlow.test';
import markdownTest from './chat/content/Markdown.test';
import localUnitTest from './LocalUnit.test';
import chatStateTest from './chat/state/ChatState.test';

export default function testsuite() {
  localUnitTest();
  chatStateTest();
  sendFlowTest();
  markdownTest();
}
