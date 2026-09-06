import { KeyboardAvoidMode } from '@kit.ArkUI';
import { createChatViewModel } from '../chat/bootstrap/ChatDependencies';
import { ChatViewModel } from '../chat/state/ChatViewModel';
import { ChatState } from '../chat/state/ChatState';
import { MessageList } from '../chat/components/MessageList';
import { Composer } from '../chat/components/Composer';
import { RequestStatus } from '../chat/components/RequestStatus';

@Entry
@ComponentV2
struct Index {
  private viewModel: ChatViewModel = createChatViewModel();
  @Local chat: ChatState = this.viewModel.state;

  aboutToAppear(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    this.viewModel.load();
  }

  aboutToDisappear(): void {
    this.viewModel.dispose();
  }

  build() {
    Column() {
      Row() {
        Column({ space: 3 }) {
          Text($r('app.string.chat_title')).fontSize(23).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.chat_text'))
          Text($r('app.string.chat_subtitle')).fontSize(12)
            .fontColor($r('app.color.chat_secondary'))
        }.alignItems(HorizontalAlign.Start)
        Blank()
        Text($r('app.string.chat_demo')).fontSize(11)
          .fontColor($r('app.color.chat_accent'))
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .backgroundColor($r('app.color.chat_bubble')).borderRadius(12)
      }.padding({ left: 22, right: 22, top: 16, bottom: 16 }).width('100%')
      Divider().color($r('app.color.chat_border'))
      Column() {
        MessageList({
          messages: this.chat.messages, pending: this.chat.pending,
          hasOlder: this.chat.olderCursor !== null, loadingOlder: this.chat.loadingOlder,
          onLoadOlder: () => { this.viewModel.loadOlder(); }
        })
      }.layoutWeight(1).width('100%')
      RequestStatus({
        phase: this.chat.phase, notice: this.chat.notice,
        canRetryLoad: this.chat.canRetryLoad,
        onRetry: () => { this.viewModel.load(); }
      })
      Composer({
        draft: this.chat.draft, canSend: this.chat.canSend, canStop: this.chat.canStop,
        onDraftChange: (text: string) => this.viewModel.setDraft(text),
        onSend: () => this.viewModel.requestSend(),
        onStop: () => this.viewModel.requestStop()
      })
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.chat_background'))
  }
}
