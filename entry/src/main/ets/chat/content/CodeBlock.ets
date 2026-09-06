@ComponentV2
export struct CodeBlock {
  @Param code: string = '';
  @Param language: string = '';
  @Local expanded: boolean = false;

  build() {
    Column({ space: 8 }) {
      Text(this.language || '代码').fontSize(12).fontColor($r('app.color.chat_secondary'))
      Scroll() {
        Text(this.expanded ? this.code : this.code.split('\n').slice(0, 8).join('\n'))
          .fontFamily('monospace').fontSize(14).lineHeight(23)
          .fontColor($r('app.color.chat_text')).copyOption(CopyOptions.LocalDevice)
          .padding({ bottom: 8 })
      }.scrollable(ScrollDirection.Horizontal).width('100%')
        .align(Alignment.TopStart).scrollBar(BarState.Auto)
      if (this.code.split('\n').length > 8) {
        Button(this.expanded ? '收起代码' : '展开代码')
          .height(44).fontSize(13).backgroundColor(Color.Transparent)
          .fontColor($r('app.color.chat_accent'))
          .onClick(() => { this.expanded = !this.expanded; })
      }
    }.alignItems(HorizontalAlign.Start).width('100%').padding(14)
      .backgroundColor($r('app.color.chat_bubble')).borderRadius(12)
  }
}
