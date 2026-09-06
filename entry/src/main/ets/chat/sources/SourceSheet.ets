import { common } from '@kit.AbilityKit';
import { Citation } from '../contracts/ChatMessage';
import { openSourceLink } from './SourceLink';

@ComponentV2
export struct SourceSheet {
  @Param citations: Citation[] = [];
  @Local expanded: string[] = [];
  @Local error: string = '';

  private sourceType(citation: Citation): string {
    if (citation.sourceType === 'official_release') {
      return '官方发布';
    }
    if (citation.sourceType === 'official_blog') {
      return '官方博客';
    }
    if (citation.sourceType === 'paper_abstract') {
      return '论文摘要';
    }
    return '官方文档';
  }

  private toggle(id: string): void {
    if (this.expanded.includes(id)) {
      this.expanded = this.expanded.filter((value: string) => value !== id);
    } else {
      this.expanded = this.expanded.concat([id]);
    }
  }

  build() {
    Column({ space: 12 }) {
      Text('消息来源').fontSize(21).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.chat_text')).width('100%')
      if (this.error !== '') {
        Text(this.error).fontSize(13).fontColor($r('app.color.chat_secondary')).width('100%')
      }
      List({ space: 16 }) {
        ForEach(this.citations, (citation: Citation) => {
          ListItem() {
            Column({ space: 8 }) {
              Text(citation.title).fontSize(17).fontColor($r('app.color.chat_text'))
              Text(this.sourceType(citation) + ' · 发布日期：' + (citation.publishedAt ?? '未知'))
                .fontSize(12).fontColor($r('app.color.chat_secondary'))
              Text(citation.originalUrl).fontSize(12).fontColor($r('app.color.chat_secondary'))
                .copyOption(CopyOptions.LocalDevice)
              if (citation.text !== '') {
                Button(this.expanded.includes(citation.citationId) ? '收起证据片段' : '展开证据片段')
                  .height(44).fontSize(13).backgroundColor(Color.Transparent)
                  .fontColor($r('app.color.chat_accent')).onClick(() => this.toggle(citation.citationId))
                if (this.expanded.includes(citation.citationId)) {
                  Text(citation.text).fontSize(14).lineHeight(23).fontColor($r('app.color.chat_text'))
                    .copyOption(CopyOptions.LocalDevice)
                }
              }
              Button('打开原文').height(44).fontSize(13)
                .backgroundColor($r('app.color.chat_bubble')).fontColor($r('app.color.chat_accent'))
                .onClick(() => {
                  this.error = '';
                  openSourceLink(citation.originalUrl,
                    this.getUIContext().getHostContext() as common.UIAbilityContext,
                    (message: string) => { this.error = message; });
                })
            }.alignItems(HorizontalAlign.Start).width('100%').padding(14)
              .border({ width: 1, color: $r('app.color.chat_border') }).borderRadius(14)
          }
        }, (citation: Citation) => citation.citationId)
      }.layoutWeight(1).width('100%')
    }.width('100%').height('100%').padding(22)
      .backgroundColor($r('app.color.chat_background'))
  }
}
