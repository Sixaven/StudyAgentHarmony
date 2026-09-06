export const MAX_INPUT_CODE_POINTS: number = 2000;

export function codePointCount(text: string): number {
  let count = 0;
  for (let index = 0; index < text.length; index++) {
    const point = text.codePointAt(index);
    if (point !== undefined && point > 0xFFFF) {
      index++;
    }
    count++;
  }
  return count;
}

export function inputError(text: string): string {
  if (typeof text !== 'string' || text.trim().length === 0) {
    return '请输入想了解的内容。';
  }
  if (codePointCount(text) > MAX_INPUT_CODE_POINTS) {
    return '内容超过 2000 个字符，请缩短后发送。';
  }
  return '';
}
