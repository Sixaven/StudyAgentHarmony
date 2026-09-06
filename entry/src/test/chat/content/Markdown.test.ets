import { describe, it, expect } from '@ohos/hypium';
import { parseMarkdown, parseInline } from '../../../main/ets/chat/content/MarkdownParser';
import { isAllowedSourceLink, openSourceLink } from '../../../main/ets/chat/sources/SourceLink';

export default function markdownTest() {
  describe('Markdown', () => {
    it('parsesNativeSubsetAndPreservesCodeIndentation', 0, () => {
      const blocks = parseMarkdown('# 标题\n\n正文 **重点** 与 *强调*\n\n1. 第一项\n- 第二项\n\n```ts\n  const n = 1;\n\n```');
      expect(blocks.length).assertEqual(5);
      expect(blocks[0].kind).assertEqual('heading');
      expect(blocks[1].parts[1].kind).assertEqual('bold');
      expect(blocks[2].text).assertEqual('1. 第一项');
      expect(blocks[4].text).assertEqual('  const n = 1;\n');
      expect(blocks[4].language).assertEqual('ts');
    });

    it('keepsUnsupportedAndUnclosedSyntaxReadable', 0, () => {
      const raw = '```ts\n<script>alert(1)</script>\n**未闭合';
      expect(parseMarkdown(raw)[0].text).assertEqual(raw);
      const html = '<script>alert(1)</script>';
      expect(parseInline(html)[0].text).assertEqual(html);
      const image = '![图](https://example.com/image.png)';
      expect(parseInline(image).map((part) => part.text).join('')).assertEqual(image);
      expect(parseMarkdown('| A | B |')[0].text).assertEqual('| A | B |');
    });

    it('keepsLongMessagesAndRecognizesLinksWithoutExecutingThem', 0, () => {
      const parts = parseInline('查看[原文](https://example.com/path) 和 `code`');
      expect(parts[1].url).assertEqual('https://example.com/path');
      expect(parts[3].kind).assertEqual('code');
      const long = '中文😀'.repeat(3000);
      expect(parseMarkdown(long)[0].text).assertEqual(long);
    });

    it('rejectsNonWebSchemesAndReportsOpenFailures', 0, async () => {
      expect(isAllowedSourceLink('javascript:alert(1)')).assertFalse();
      expect(isAllowedSourceLink('file:///data/local')).assertFalse();
      expect(isAllowedSourceLink('citation:123')).assertFalse();
      expect(isAllowedSourceLink('https:///')).assertFalse();
      expect(isAllowedSourceLink('https://example.com/\n')).assertFalse();
      let message = '';
      await openSourceLink('javascript:alert(1)', undefined, (value: string) => { message = value; });
      expect(message.length > 0).assertTrue();
    });
  });
}
