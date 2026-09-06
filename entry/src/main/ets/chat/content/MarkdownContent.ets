import { CodeBlock } from './CodeBlock';
import { InlinePart, MarkdownBlock, parseMarkdown } from './MarkdownParser';
import { openSourceLink } from '../sources/SourceLink';
import { common } from '@kit.AbilityKit';

@ComponentV2
export struct MarkdownContent {
  @Param content: string = '';
  @Local blocks: MarkdownBlock[] = [];
  @Event onLinkError: (message: string) => void = () => {};

  aboutToAppear(): void {
    this.blocks = parseMarkdown(this.content);
  }

  @Monitor('content')
  onContentChanged(): void {
    this.blocks = parseMarkdown(this.content);
  }

  private openLink(url: string): void {
    if (url !== '') {
      openSourceLink(url, this.getUIContext().getHostContext() as common.UIAbilityContext,
        this.onLinkError);
    }
  }

  build() {
    Column({ space: 12 }) {
      ForEach(this.blocks, (block: MarkdownBlock) => {
        if (block.kind === 'code') {
          CodeBlock({ code: block.text, language: block.language })
        } else {
          Text() {
            ForEach(block.parts, (part: InlinePart) => {
              Span(part.text)
                .fontWeight(part.kind === 'bold' || block.kind === 'heading' ? FontWeight.Medium : FontWeight.Normal)
                .fontStyle(part.kind === 'italic' ? FontStyle.Italic : FontStyle.Normal)
                .fontFamily(part.kind === 'code' ? 'monospace' : 'HarmonyOS Sans')
                .fontColor(part.kind === 'link' ? $r('app.color.chat_accent') : $r('app.color.chat_text'))
                .decoration({ type: part.kind === 'link' ? TextDecorationType.Underline : TextDecorationType.None })
                .onClick(() => this.openLink(part.url))
            }, (_part: InlinePart, index: number) => index.toString())
          }.fontSize(block.kind === 'heading' ? 22 - Math.min(block.level, 4) : 16)
            .lineHeight(27).width('100%').copyOption(CopyOptions.LocalDevice)
        }
      }, (_block: MarkdownBlock, index: number) => index.toString())
    }.alignItems(HorizontalAlign.Start).width('100%')
  }
}
