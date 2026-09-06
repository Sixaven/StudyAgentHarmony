import chatFlowTest from './ChatFlow.test';
import abilityTest from './Ability.test';

export default function testsuite() {
  abilityTest();
  chatFlowTest();
}