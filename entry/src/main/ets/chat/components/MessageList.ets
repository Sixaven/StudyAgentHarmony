import { ChatMessage, Citation, PendingMessage } from '../contracts/ChatMessage';
import { MessageItem } from './MessageItem';

@ComponentV2
export struct MessageList {
  @Param @Require messages: ChatMessage[];
  @Param @Require pending: PendingMessage[];
  @Event onSources: (citations: Citation[]) => void = () => {};
  @Event onLinkError: (message: string) => void = () => {};
  @Param hasOlder: boolean = false;
  @Param loadingOlder: boolean = false;
  @Event onLoadOlder: () => void = () => {};
  @Local following: boolean = true;
  private scroller: Scroller = new Scroller();
  private lastMessageId: string = '';
  private pendingCount: number = 0;

  @Monitor('messages', 'pending')
  onMessagesChanged(): void {
    const latest = this.messages[this.messages.length - 1];
    const latestId = latest === undefined ? '' : latest.messageId;
    const appended = latestId !== this.lastMessageId || this.pending.length > this.pendingCount;
    this.lastMessageId = latestId;
    this.pendingCount = this.pending.length;
    if (appended && this.following) {
      setTimeout(() => {
        if (this.following) {
          this.scroller.scrollEdge(Edge.Bottom);
        }
      }, 0);
    }
  }

  private pendingMessage(item: PendingMessage): ChatMessage {
    return {
      messageId: 'pending-' + item.requestId, chatId: '', sequence: 0, role: 'user',
      format: 'plain', content: item.text, createdAt: '', requestId: item.requestId,
      taskId: null, origin: 'interactive', draftId: null, citations: []
    };
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      List({ space: 26, scroller: this.scroller }) {
        if (this.hasOlder) {
          ListItem() {
            Button($r('app.string.chat_older'))
              .type(ButtonType.Normal).backgroundColor(Color.Transparent)
              .fontColor($r('app.color.chat_secondary')).fontSize(13)
              .width('100%').height(44)
              .enabled(!this.loadingOlder)
              .onClick(() => this.onLoadOlder())
          }
        }
        if (this.messages.length === 0 && this.pending.length === 0) {
          ListItem() {
            Text($r('app.string.chat_empty')).fontSize(16).lineHeight(26)
              .fontColor($r('app.color.chat_secondary')).padding({ top: 32 })
          }
        }
        ForEach(this.messages, (message: ChatMessage) => {
          ListItem() {
            MessageItem({ message: message, onSources: this.onSources, onLinkError: this.onLinkError })
          }
        }, (message: ChatMessage) => message.messageId)
        ForEach(this.pending, (item: PendingMessage) => {
          ListItem() {
            MessageItem({ message: this.pendingMessage(item), pending: true })
          }
        }, (item: PendingMessage) => 'pending-' + item.requestId)
      }
      .width('100%').height('100%')
      .padding({ left: 22, right: 22, top: 20, bottom: 20 })
      .maintainVisibleContentPosition(true)
      .onDidScroll(() => {
        this.following = this.scroller.isAtEnd();
      })
      if (!this.following) {
        Button($r('app.string.chat_latest'))
          .fontSize(13).height(44).margin(16)
          .backgroundColor($r('app.color.chat_accent'))
          .fontColor($r('app.color.chat_on_accent'))
          .onClick(() => {
            this.following = true;
            this.scroller.scrollEdge(Edge.Bottom);
          })
      }
    }.width('100%').height('100%')
  }
}
