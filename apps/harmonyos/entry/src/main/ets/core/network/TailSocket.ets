// Workers tail 实时日志 WebSocket（对齐 Android TailSocket）。
// 预签名 wss:// + 子协议 trace-v1；连接无需 Bearer；帧是 camelCase JSON。
import { webSocket } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { TailTraceItem } from '../../models/WorkerModels';

const DOMAIN = 0x0002;
const TAG = 'TailSocket';

export type TailItemHandler = (item: TailTraceItem) => void;
export type TailStateHandler = (connected: boolean, error: string) => void;

export class TailSocket {
  private ws: webSocket.WebSocket | null = null;
  private url: string;

  constructor(url: string) {
    this.url = url;
  }

  connect(onItem: TailItemHandler, onState: TailStateHandler): void {
    const ws = webSocket.createWebSocket();
    this.ws = ws;

    ws.on('open', () => {
      onState(true, '');
    });

    ws.on('message', (err: Error, data: string | ArrayBuffer) => {
      if (err) {
        return;
      }
      let text = '';
      if (typeof data === 'string') {
        text = data;
      } else {
        const bytes = new Uint8Array(data);
        for (let i = 0; i < bytes.length; i++) {
          text += String.fromCharCode(bytes[i]);
        }
      }
      try {
        const item = JSON.parse(text) as TailTraceItem;
        onItem(item);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'bad frame');
      }
    });

    ws.on('close', () => {
      onState(false, '');
    });

    ws.on('error', (err: Error) => {
      onState(false, err.message ?? '连接中断');
    });

    // 子协议 trace-v1 必须走 WebSocketRequestOptions.protocol 字段——
    // 经 header 手写 Sec-WebSocket-Protocol 会被 @ohos.net.webSocket 忽略，
    // 握手缺子协议协商 → Cloudflare tail 端点升级后立即关闭（连接中断）。
    const options: webSocket.WebSocketRequestOptions = {
      protocol: 'trace-v1',
    };
    ws.connect(this.url, options, (err) => {
      if (err) {
        onState(false, '无法建立连接');
      }
    });
  }

  close(): void {
    const ws = this.ws;
    if (ws) {
      ws.close((err) => {
      });
      this.ws = null;
    }
  }
}
