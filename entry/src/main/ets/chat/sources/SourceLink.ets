import { common } from '@kit.AbilityKit';
import { uri } from '@kit.ArkTS';

export function isAllowedSourceLink(value: string): boolean {
  if (!/^https?:\/\/[^\s]+$/i.test(value) || /[\u0000-\u0020\u007f]/.test(value)) {
    return false;
  }
  try {
    const parsed = new uri.URI(value);
    const scheme = parsed.scheme.toLowerCase();
    return parsed.host.length > 0 && (scheme === 'http' || scheme === 'https');
  } catch {
    return false;
  }
}

export async function openSourceLink(value: string, context: common.UIAbilityContext | undefined,
  onError: (message: string) => void): Promise<void> {
  if (!isAllowedSourceLink(value)) {
    onError('此链接无法打开，仅支持有效的 http/https 原文地址。');
    return;
  }
  try {
    if (context === undefined) {
      onError('暂时无法打开原文，请稍后重试。');
      return;
    }
    await context.openLink(value, { appLinkingOnly: false });
  } catch {
    onError('无法打开原文，请检查是否有可用浏览器后重试。');
  }
}
