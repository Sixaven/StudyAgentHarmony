import { codePointCount, MAX_INPUT_CODE_POINTS } from '../state/InputText';

@ComponentV2
export struct Composer {
  @Param draft: string = '';
  @Param canSend: boolean = false;
  @Param stopping: boolean = false;
  @Param canStop: boolean = false;
  @Event onDraftChange: (text: string) => void = () => {};
  @Event onSend: () => void = () => {};
  @Event onStop: () => void = () => {};

  build() {
    Column({ space: 2 }) {
      Row({ space: 10 }) {
        TextArea({ text: this.draft, placeholder: $r('app.string.chat_placeholder') })
          .id('chat-draft').layoutWeight(1)
          .fontSize(16).fontColor($r('app.color.chat_text'))
          .placeholderColor($r('app.color.chat_secondary'))
          .backgroundColor(Color.Transparent)
          .constraintSize({ minHeight: 48, maxHeight: 132 })
          .onChange((text: string) => this.onDraftChange(text))
        if (this.canStop || this.stopping) {
          Button(this.stopping ? '停止中' : $r('app.string.chat_stop'))
            .enabled(this.canStop)
            .id('chat-stop').height(44).fontSize(14)
            .backgroundColor($r('app.color.chat_accent'))
            .fontColor($r('app.color.chat_on_accent'))
            .onClick(() => this.onStop())
        } else {
          Button($r('app.string.chat_send'))
            .id('chat-send').height(44).fontSize(14)
            .enabled(this.canSend)
            .backgroundColor($r('app.color.chat_accent'))
            .fontColor($r('app.color.chat_on_accent'))
            .onClick(() => this.onSend())
        }
      }
      .alignItems(VerticalAlign.Bottom)
      .padding(8).borderRadius(22)
      .backgroundColor($r('app.color.chat_surface'))
      .border({ width: 1, color: $r('app.color.chat_border') })
      .margin({ left: 18, right: 18, top: 8 })
      Text(codePointCount(this.draft).toString() + ' / 2000' +
        (codePointCount(this.draft) > MAX_INPUT_CODE_POINTS ? ' · 请缩短后发送' : ''))
        .fontSize(12).fontColor($r('app.color.chat_secondary'))
        .width('100%').textAlign(TextAlign.End).padding({ right: 26, bottom: 8 })
    }.width('100%')
  }
}
