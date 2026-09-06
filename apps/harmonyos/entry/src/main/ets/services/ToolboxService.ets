// 免登录网络工具箱（对齐 Android ToolboxRepository）。
// 全部走公开端点，不用 CF Token：DoH / ipwho.is / cdn-cgi/trace / RDAP / 纯计算。
// 注意：SSL 证书链检查需底层 TLS 访问，HarmonyOS http 栈不暴露，故 SSL 工具退化为 HTTPS 可达性 + 响应头探测。
import { http } from '@kit.NetworkKit';

export interface ToolField {
  label: string;
  value: string;
}

interface DohAnswer {
  name?: string;
  type?: number;
  TTL?: number;
  data?: string;
}

interface DohResponse {
  Answer?: DohAnswer[];
  Status?: number;
}

interface GeoIpResponse {
  ip?: string;
  success?: boolean;
  country?: string;
  region?: string;
  city?: string;
  latitude?: number;
  longitude?: number;
  connection?: GeoIpConnection;
}

interface GeoIpConnection {
  isp?: string;
  org?: string;
  asn?: number;
}

function dnsTypeName(type: number): string {
  const map: Record<number, string> = {
    1: 'A', 2: 'NS', 5: 'CNAME', 6: 'SOA', 15: 'MX', 16: 'TXT', 28: 'AAAA', 33: 'SRV', 257: 'CAA',
  };
  return map[type] ?? `TYPE${type}`;
}

function normalizeHost(input: string): string {
  let s = input.trim();
  s = s.replace('https://', '').replace('http://', '');
  const slash = s.indexOf('/');
  if (slash >= 0) {
    s = s.substring(0, slash);
  }
  return s.trim();
}

export class ToolboxService {
  private async getText(url: string, headers?: Record<string, string>): Promise<string> {
    const session = http.createHttp();
    try {
      const response = await session.request(url, {
        method: http.RequestMethod.GET,
        header: (headers ?? {}) as Record<string, string>,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 30000,
      });
      if (response.responseCode < 200 || response.responseCode >= 400) {
        throw new Error(`HTTP ${response.responseCode}`);
      }
      return response.result as string;
    } finally {
      session.destroy();
    }
  }

  /// DNS 查询（DoH JSON，cloudflare-dns.com）
  async dnsLookup(name: string, type: string): Promise<ToolField[]> {
    const host = normalizeHost(name);
    const text = await this.getText(
      `https://cloudflare-dns.com/dns-query?name=${encodeURIComponent(host)}&type=${encodeURIComponent(type)}`,
      { 'accept': 'application/dns-json' });
    const parsed = JSON.parse(text) as DohResponse;
    const answers = parsed.Answer ?? [];
    if (answers.length === 0) {
      return [{ label: '结果', value: '无记录' }];
    }
    return answers.map((a: DohAnswer): ToolField => ({
      label: `${dnsTypeName(a.type ?? 0)} · TTL ${a.TTL ?? 0}`,
      value: a.data ?? '',
    }));
  }

  /// IP 归属地（ipwho.is）；ip 空 = 查本机
  async geoIp(ip: string): Promise<ToolField[]> {
    const target = ip.trim();
    const url = target === '' ? 'https://ipwho.is/' : `https://ipwho.is/${encodeURIComponent(target)}`;
    const text = await this.getText(url);
    const parsed = JSON.parse(text) as GeoIpResponse;
    if (parsed.success === false) {
      return [{ label: '错误', value: '无法查询该 IP' }];
    }
    const fields: ToolField[] = [
      { label: 'IP', value: parsed.ip ?? '' },
      { label: '国家/地区', value: parsed.country ?? '' },
      { label: '城市', value: `${parsed.region ?? ''} ${parsed.city ?? ''}`.trim() },
    ];
    if (parsed.connection) {
      fields.push({ label: 'ISP', value: parsed.connection.isp ?? '' });
      fields.push({ label: 'ASN', value: `AS${parsed.connection.asn ?? ''} ${parsed.connection.org ?? ''}` });
    }
    if (parsed.latitude !== undefined) {
      fields.push({ label: '经纬度', value: `${parsed.latitude}, ${parsed.longitude}` });
    }
    return fields;
  }

  /// Cloudflare Trace（/cdn-cgi/trace，key=value 文本）
  async cfTrace(host: string): Promise<ToolField[]> {
    const h = normalizeHost(host) === '' ? 'cloudflare.com' : normalizeHost(host);
    const text = await this.getText(`https://${h}/cdn-cgi/trace`);
    const fields: ToolField[] = [];
    for (const line of text.split('\n')) {
      const eq = line.indexOf('=');
      if (eq > 0) {
        fields.push({ label: line.substring(0, eq), value: line.substring(eq + 1) });
      }
    }
    return fields;
  }

  /// HTTP 探测：状态码 + 关键响应头
  async httpProbe(rawUrl: string): Promise<ToolField[]> {
    let u = rawUrl.trim();
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = `https://${u}`;
    }
    const session = http.createHttp();
    try {
      const response = await session.request(u, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 30000,
      });
      const headers = response.header as Record<string, string>;
      const fields: ToolField[] = [
        { label: '状态码', value: `${response.responseCode}` },
      ];
      const interesting: string[] = ['server', 'content-type', 'cf-ray', 'cf-cache-status', 'content-length'];
      for (const key of interesting) {
        const value = headers[key];
        if (value !== undefined) {
          fields.push({ label: key, value: `${value}` });
        }
      }
      return fields;
    } finally {
      session.destroy();
    }
  }

  /// whois（RDAP）：先查 IANA bootstrap 找 RDAP base，再查域名
  async whois(domain: string): Promise<ToolField[]> {
    const host = normalizeHost(domain);
    const dot = host.lastIndexOf('.');
    const tld = dot >= 0 ? host.substring(dot + 1) : host;
    let base = '';
    try {
      const bootstrapText = await this.getText('https://data.iana.org/rdap/dns.json');
      interface Bootstrap {
        services?: string[][][];
      }
      const bootstrap = JSON.parse(bootstrapText) as Bootstrap;
      const services = bootstrap.services ?? [];
      for (const svc of services) {
        const tlds = svc[0];
        const urls = svc[1];
        if (tlds.includes(tld) && urls.length > 0) {
          base = urls[0];
          break;
        }
      }
    } catch (e) {
    }
    if (base === '') {
      base = 'https://rdap.org/';
    }
    const rdapUrl = base.endsWith('/') ? `${base}domain/${host}` : `${base}/domain/${host}`;
    const text = await this.getText(rdapUrl);
    interface RdapEvent {
      eventAction?: string;
      eventDate?: string;
    }
    interface RdapDomain {
      ldhName?: string;
      status?: string[];
      events?: RdapEvent[];
    }
    const rdap = JSON.parse(text) as RdapDomain;
    const fields: ToolField[] = [
      { label: '域名', value: rdap.ldhName ?? host },
      { label: '状态', value: (rdap.status ?? []).join('，') },
    ];
    for (const event of rdap.events ?? []) {
      fields.push({ label: event.eventAction ?? '', value: (event.eventDate ?? '').substring(0, 10) });
    }
    return fields;
  }

  /// SSL 探测（退化版）：HTTPS 可达性 + 响应头（HarmonyOS 不暴露证书链，仅报握手可达）
  async sslInspect(host: string): Promise<ToolField[]> {
    const h = normalizeHost(host);
    const session = http.createHttp();
    try {
      const response = await session.request(`https://${h}/`, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 30000,
      });
      const headers = response.header as Record<string, string>;
      return [
        { label: 'TLS 握手', value: '成功（证书受系统信任）' },
        { label: '状态码', value: `${response.responseCode}` },
        { label: 'Server', value: `${headers['server'] ?? '—'}` },
        { label: '说明', value: '完整证书链细节需在桌面工具查看' },
      ];
    } catch (e) {
      return [{ label: 'TLS 握手', value: `失败：${(e as Error).message ?? ''}` }];
    } finally {
      session.destroy();
    }
  }

  /// CIDR 计算（纯本地，仅 IPv4）
  computeCidr(input: string): ToolField[] {
    const trimmed = input.trim();
    const slash = trimmed.indexOf('/');
    if (slash < 0) {
      return [{ label: '错误', value: '请输入 CIDR，如 192.168.1.0/24' }];
    }
    const ipPart = trimmed.substring(0, slash);
    const prefix = Number.parseInt(trimmed.substring(slash + 1));
    const octets = ipPart.split('.').map((o: string) => Number.parseInt(o));
    if (octets.length !== 4 || octets.some((o: number) => Number.isNaN(o) || o < 0 || o > 255) ||
      Number.isNaN(prefix) || prefix < 0 || prefix > 32) {
      return [{ label: '错误', value: '无效的 IPv4 CIDR' }];
    }
    const ipNum = ((octets[0] * 256 + octets[1]) * 256 + octets[2]) * 256 + octets[3];
    const mask = prefix === 0 ? 0 : (0xFFFFFFFF << (32 - prefix)) >>> 0;
    const network = (ipNum & mask) >>> 0;
    const broadcast = (network | (~mask >>> 0)) >>> 0;
    const total = prefix >= 31 ? (prefix === 32 ? 1 : 2) : (broadcast - network + 1);
    const usable = prefix >= 31 ? total : total - 2;

    const toIp = (n: number): string =>
      `${(n >>> 24) & 255}.${(n >>> 16) & 255}.${(n >>> 8) & 255}.${n & 255}`;

    return [
      { label: '网络地址', value: toIp(network) },
      { label: '广播地址', value: toIp(broadcast) },
      { label: '子网掩码', value: toIp(mask) },
      { label: '首个可用', value: prefix >= 31 ? toIp(network) : toIp(network + 1) },
      { label: '末个可用', value: prefix >= 31 ? toIp(broadcast) : toIp(broadcast - 1) },
      { label: '地址总数', value: `${total}` },
      { label: '可用主机数', value: `${usable}` },
    ];
  }
}
