import { describe, it, expect } from '@ohos/hypium';
import { Driver, ON } from '@ohos.UiTest';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { ChatApi } from '../../../main/ets/chat/transport/ChatApi';
import { RcpTransport } from '../../../main/ets/chat/transport/RcpTransport';
import { chatConfiguration } from '../../../main/ets/chat/bootstrap/ChatConfig';

export default function chatFlowTest() {
  describe('ChatFlow', () => {
    const parameters = abilityDelegatorRegistry.getArguments().parameters;
    const realRequested = parameters['-s chatReal'] === 'true';
    // Real-mode UI checks require explicit opt-in and a separately started server.
    if (chatConfiguration.mode === 'fake' || realRequested) {
      it('sendsThroughThePageAndPreservesAnEditableDraft', 0, async () => {
        const delegator = abilityDelegatorRegistry.getAbilityDelegator();
        await delegator.startAbility({ bundleName: 'com.example.studyagent', abilityName: 'EntryAbility' });
        const driver = Driver.create();
        await driver.delayMs(1500);
        const input = await driver.findComponent(ON.id('chat-draft'));
        await input.inputText(realRequested ? '学习 Agent' : '页面交互检查');
        const send = await driver.findComponent(ON.id('chat-send'));
        expect(await send.isEnabled()).assertTrue();
        await send.click();
        await input.inputText('保留的新草稿');
        await driver.delayMs(6000);
        const restored = await driver.findComponent(ON.id('chat-draft'));
        expect(await restored.getText()).assertEqual('保留的新草稿');
        await driver.assertComponentExist(ON.id('chat-send'));
      });
      if (realRequested) {
        it('clarifiesFollowsUpAndEvaluatesUsingSavedServerMessages', 0, async () => {
          const driver = Driver.create();
          const api = new ChatApi(new RcpTransport(chatConfiguration));
          try {
            const texts = ['不明确的输入', '追问：Runtime 是什么？', '回答：Runtime 执行工具。'];
            for (const text of texts) {
              const before = await api.loadChat();
              const input = await driver.findComponent(ON.id('chat-draft'));
              await input.inputText(text);
              await (await driver.findComponent(ON.id('chat-send'))).click();
              await driver.delayMs(7000);
              const after = await api.loadChat();
              expect(after.activeTask === null).assertTrue();
              expect(after.latestTask?.taskId === before.latestTask?.taskId).assertFalse();
              expect(after.latestTask?.savedMessages.some(message =>
                message.role === 'user' && message.content === text)).assertTrue();
              expect(after.latestTask?.savedMessages.some(message =>
                message.role === 'assistant')).assertTrue();
              if (text.startsWith('追问')) {
                await (await driver.findComponent(ON.text('查看来源 · 1'))).click();
                await driver.assertComponentExist(ON.text('消息来源'));
                await driver.pressBack();
              }
            }
          } finally {
            api.close();
          }
        });
      }
    }
  });
}
