import localUnitTest from './LocalUnit.test';
import chatStateTest from './chat/state/ChatState.test';

export default function testsuite() {
  localUnitTest();
  chatStateTest();
}
