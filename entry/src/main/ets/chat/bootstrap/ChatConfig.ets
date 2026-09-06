export interface ChatConfiguration {
  mode: 'fake' | 'real';
  baseUrl: string;
  requestTimeoutMs: number;
  streamIdleTimeoutMs: number;
}

// Set the address reachable FROM THE DEVICE, including /api/v1.
// Empty by default: no assumption that device localhost is the development computer.
export const chatConfiguration: ChatConfiguration = {
  mode: 'fake',
  baseUrl: '',
  requestTimeoutMs: 15000,
  streamIdleTimeoutMs: 90000
};

export function apiBaseUrl(config: ChatConfiguration): string {
  if (!/^https?:\/\/[^\s/?#@]+(?::\d+)?(?:\/[^\s?#]*)?$/.test(config.baseUrl) ||
    !Number.isFinite(config.requestTimeoutMs) || config.requestTimeoutMs <= 0 ||
    !Number.isFinite(config.streamIdleTimeoutMs) || config.streamIdleTimeoutMs <= 0) {
    throw new Error('请配置设备可访问的 API 地址和正数超时。');
  }
  return config.baseUrl.replace(/\/+$/, '');
}
