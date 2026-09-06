import { MarkdownContent } from '../content/MarkdownContent';
import { ChatMessage, Citation } from '../contracts/ChatMessage';

@ComponentV2
export struct MessageItem {
  @Param @Require message: ChatMessage;
  @Param pending: boolean = false;
  @Event onSources: (citations: Citation[]) => void = () => {};
  @Event onLinkError: (message: string) => void = () => {};

  build() {
    Row() {
      if (this.message.role === 'user') {
        Blank().width(32)
      }
      Column({ space: 6 }) {
        if (this.message.role === 'assistant') {
          Text($r('app.string.chat_assistant'))
            .fontSize(12).fontColor($r('app.color.chat_accent'))
        }
        if (this.message.role === 'assistant' && this.message.format === 'markdown') {
          MarkdownContent({ content: this.message.content, onLinkError: this.onLinkError })
        } else {
          Text(this.message.content)
            .fontSize(16).lineHeight(26)
            .fontColor($r('app.color.chat_text'))
            .copyOption(CopyOptions.LocalDevice)
            .width('100%')
        }
        if (this.message.citations.length > 0) {
          Button('查看来源 · ' + this.message.citations.length.toString())
            .height(44).fontSize(13).backgroundColor(Color.Transparent)
            .fontColor($r('app.color.chat_accent'))
            .onClick(() => this.onSources(this.message.citations))
        }
        if (this.pending) {
          Text($r('app.string.chat_unconfirmed'))
            .fontSize(12).fontColor($r('app.color.chat_secondary'))
        }
      }
      .alignItems(HorizontalAlign.Start)
      .padding(this.message.role === 'user' ? 16 : 0)
      .backgroundColor(this.message.role === 'user' ?
        $r('app.color.chat_bubble') : Color.Transparent)
      .borderRadius(18)
      .layoutWeight(1)
    }.width('100%')
  }
}
