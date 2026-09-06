export interface InlinePart {
  text: string;
  kind: 'plain' | 'bold' | 'italic' | 'code' | 'link';
  url: string;
}

export interface MarkdownBlock {
  kind: 'paragraph' | 'heading' | 'list' | 'code';
  text: string;
  level: number;
  language: string;
  parts: InlinePart[];
}

// This deliberately bounded subset leaves unsupported syntax visible as text.
// HTML, images and source markers have no executable interpretation.
export function parseInline(text: string): InlinePart[] {
  const parts: InlinePart[] = [];
  const tokens = /(`[^`\n]+`|\*\*[^*\n]+\*\*|__[^_\n]+__|\*[^*\n]+\*|_[^_\n]+_|\[[^\]\n]+\]\([^\s()]+\))/g;
  let offset = 0;
  let match = tokens.exec(text);
  while (match !== null) {
    if (match.index > offset) {
      parts.push({ text: text.slice(offset, match.index), kind: 'plain', url: '' });
    }
    const token = match[0];
    if (token.startsWith('`')) {
      parts.push({ text: token.slice(1, -1), kind: 'code', url: '' });
    } else if (token.startsWith('**') || token.startsWith('__')) {
      parts.push({ text: token.slice(2, -2), kind: 'bold', url: '' });
    } else if (token.startsWith('[') && (match.index === 0 || text[match.index - 1] !== '!')) {
      const separator = token.indexOf('](');
      parts.push({ text: token.slice(1, separator), kind: 'link', url: token.slice(separator + 2, -1) });
    } else if (token.startsWith('*') || token.startsWith('_')) {
      parts.push({ text: token.slice(1, -1), kind: 'italic', url: '' });
    } else {
      parts.push({ text: token, kind: 'plain', url: '' });
    }
    offset = match.index + token.length;
    match = tokens.exec(text);
  }
  if (offset < text.length) {
    parts.push({ text: text.slice(offset), kind: 'plain', url: '' });
  }
  return parts;
}

export function parseMarkdown(content: string): MarkdownBlock[] {
  const blocks: MarkdownBlock[] = [];
  const lines = content.replace(/\r\n/g, '\n').split('\n');
  let index = 0;
  while (index < lines.length) {
    const line = lines[index];
    const fence = /^ {0,3}(`{3,}|~{3,})(.*)$/.exec(line);
    if (fence !== null) {
      let end = index + 1;
      while (end < lines.length) {
        const closing = lines[end].trim();
        if (closing.length >= fence[1].length &&
          closing.split(fence[1][0]).join('') === '') {
          break;
        }
        end++;
      }
      if (end < lines.length) {
        blocks.push({ kind: 'code', text: lines.slice(index + 1, end).join('\n'),
          level: 0, language: fence[2].trim(), parts: [] });
        index = end + 1;
      } else {
        const remaining = lines.slice(index).join('\n');
        blocks.push({ kind: 'paragraph', text: remaining, level: 0, language: '',
          parts: [{ text: remaining, kind: 'plain', url: '' }] });
        break;
      }
    } else if (line.trim() === '') {
      index++;
    } else {
      const heading = /^ {0,3}(#{1,6})\s+(.+)$/.exec(line);
      const list = /^(\s*)([-+*]|\d+[.)])\s+(.+)$/.exec(line);
      if (heading !== null) {
        blocks.push({ kind: 'heading', text: heading[2], level: heading[1].length,
          language: '', parts: parseInline(heading[2]) });
        index++;
      } else if (list !== null) {
        // Retain the original marker and indentation, including nested lists.
        blocks.push({ kind: 'list', text: line, level: 0, language: '', parts: parseInline(line) });
        index++;
      } else {
        const start = index++;
        while (index < lines.length && lines[index].trim() !== '' &&
          !/^ {0,3}(`{3,}|~{3,}|#{1,6}\s)/.test(lines[index]) &&
          !/^\s*([-+*]|\d+[.)])\s/.test(lines[index])) {
          index++;
        }
        const paragraph = lines.slice(start, index).join('\n');
        blocks.push({ kind: 'paragraph', text: paragraph, level: 0, language: '', parts: parseInline(paragraph) });
      }
    }
  }
  return blocks;
}
