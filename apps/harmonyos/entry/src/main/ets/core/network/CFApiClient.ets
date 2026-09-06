// Cloudflare API 客户端（对齐 iOS CFAPIClient / Android CfApiClient）。
// 统一解析 { result, success, errors } 信封；Token 由 AuthManager 注入。
// 特殊形态：getRaw（KV value / Snippet 正文是裸字节非信封）、putMultipart（KV 写值）、graphql（分析）。
import { http } from '@kit.NetworkKit';
import { rcp } from '@kit.RemoteCommunicationKit';
import { CFError, CFListEnvelope, CFObjectEnvelope } from '../../models/Models';
import { authManager } from '../auth/AuthManager';

const BASE_URL = 'https://api.cloudflare.com/client/v4';

export class ApiError extends Error {
  code: number;

  constructor(message: string, code?: number) {
    super(message);
    this.code = code ?? 0;
  }
}

function firstErrorMessage(errors?: CFError[]): string {
  if (errors && errors.length > 0) {
    return errors[0].message;
  }
  return '未知错误';
}

function envelopeError(errors?: CFError[]): ApiError {
  const code = (errors && errors.length > 0) ? errors[0].code : 0;
  return new ApiError(firstErrorMessage(errors), code);
}

/// multipart 文本 part（KV 写值、Snippet 上传）
export interface MultipartPart {
  name: string;
  data: string;
  contentType?: string;
  filename?: string;
}

interface RawResponse {
  code: number;
  body: string;
}

/// 手工拼 multipart 报文（@kit http 的 multiFormDataList 对 PUT 支持不稳，自拼 boundary 最可控）。
/// http 与 rcp 两条发送路径共用。
function buildMultipartBody(boundary: string, parts: MultipartPart[]): string {
  const segments: string[] = [];
  for (const part of parts) {
    let head = `--${boundary}\r\nContent-Disposition: form-data; name="${part.name}"`;
    if (part.filename) {
      head = `${head}; filename="${part.filename}"`;
    }
    head = `${head}\r\n`;
    if (part.contentType) {
      head = `${head}Content-Type: ${part.contentType}\r\n`;
    }
    segments.push(`${head}\r\n${part.data}\r\n`);
  }
  segments.push(`--${boundary}--\r\n`);
  return segments.join('');
}

/// 站外主机的错误消息：优先取 CF 信封 errors[0].message，其次 error/message 字段，最后 HTTP 码
function externalErrorMessage(code: number, body: string): string {
  try {
    const envelope = JSON.parse(body) as ExternalErrorBody;
    const first = envelope.errors?.[0]?.message;
    if (first !== undefined && first !== '') {
      return first;
    }
    const single = envelope.error ?? envelope.message;
    if (single !== undefined && single !== '') {
      return single;
    }
  } catch (e) {
    // 非 JSON 响应，落到 HTTP 码
  }
  return `HTTP ${code}`;
}

interface ExternalErrorBody {
  errors?: CFError[];
  error?: string;
  message?: string;
}

export class CFApiClient {
  /// GET 列表型端点，返回信封内 result 数组
  async getList<T>(path: string, query?: Record<string, string>): Promise<T[]> {
    const envelope = await this.getListEnvelope<T>(path, query);
    return envelope.result ?? [];
  }

  /// GET 列表型端点，返回完整信封（含 result_info 分页游标）
  async getListEnvelope<T>(path: string, query?: Record<string, string>): Promise<CFListEnvelope<T>> {
    const text = await this.requestText(http.RequestMethod.GET, path, query);
    const envelope = JSON.parse(text) as CFListEnvelope<T>;
    if (!envelope.success) {
      throw envelopeError(envelope.errors);
    }
    return envelope;
  }

  /// GET 单对象型端点
  async getObject<T>(path: string, query?: Record<string, string>): Promise<T> {
    const text = await this.requestText(http.RequestMethod.GET, path, query);
    return this.parseObject<T>(text);
  }

  /// GET 裸响应体（KV value、Snippet 正文等非信封端点）；404 时抛 ApiError(code 404)
  async getRaw(path: string, query?: Record<string, string>): Promise<string> {
    return await this.requestText(http.RequestMethod.GET, path, query);
  }

  /// POST 创建（JSON 请求体），返回信封内单对象
  postObject<T>(path: string, body: object): Promise<T> {
    return this.sendObject<T>(http.RequestMethod.POST, path, body);
  }

  /// PUT 全量更新（JSON 请求体），返回信封内单对象
  putObject<T>(path: string, body: object): Promise<T> {
    return this.sendObject<T>(http.RequestMethod.PUT, path, body);
  }

  /// PATCH 局部更新（JSON 请求体），返回信封内单对象。
  /// @kit http 的 RequestMethod 枚举没有 PATCH，走 rcp（Remote Communication Kit）。
  async patchObject<T>(path: string, body: object): Promise<T> {
    const token = await authManager.ensureAccessToken();
    const session = rcp.createSession();
    try {
      const headers: rcp.RequestHeaders = {
        'authorization': `Bearer ${token}`,
        'content-type': 'application/json',
      };
      const request = new rcp.Request(`${BASE_URL}${path}`, 'PATCH', headers, JSON.stringify(body));
      const response = await session.fetch(request);
      const text = response.toString() ?? '';
      return this.parseObject<T>(this.unwrap({ code: response.statusCode, body: text }));
    } finally {
      session.close();
    }
  }

  /// POST 返回列表信封（如 D1 query、rulesets 部分端点）
  async postForList<T>(path: string, body: object): Promise<T[]> {
    const text = await this.requestText(http.RequestMethod.POST, path, undefined, JSON.stringify(body));
    const envelope = JSON.parse(text) as CFListEnvelope<T>;
    if (!envelope.success) {
      throw envelopeError(envelope.errors);
    }
    return envelope.result ?? [];
  }

  /// DELETE（可带 JSON 体，如 KV 批删），只校验信封 success
  async delete(path: string, body?: object): Promise<void> {
    const text = await this.requestText(http.RequestMethod.DELETE, path, undefined,
      body === undefined ? undefined : JSON.stringify(body));
    const envelope = JSON.parse(text) as CFObjectEnvelope<object>;
    if (!envelope.success) {
      throw envelopeError(envelope.errors);
    }
  }

  /// PUT 裸文本体（KV 简单写值不带 metadata 时仍推荐 multipart，此方法留给 R2 等）
  async putRaw(path: string, bodyText: string, contentType: string): Promise<void> {
    const text = await this.requestText(http.RequestMethod.PUT, path, undefined, bodyText, contentType);
    const envelope = JSON.parse(text) as CFObjectEnvelope<object>;
    if (!envelope.success) {
      throw envelopeError(envelope.errors);
    }
  }

  /// PUT 二进制体（R2 文件上传，extraData 传 ArrayBuffer）
  async putBytes(path: string, buffer: ArrayBuffer, contentType: string): Promise<void> {
    const token = await authManager.ensureAccessToken();
    const session = http.createHttp();
    try {
      const response = await session.request(`${BASE_URL}${path}`, {
        method: http.RequestMethod.PUT,
        header: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': contentType,
        } as Record<string, string>,
        extraData: buffer,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 120000,
      });
      const body = this.unwrap({ code: response.responseCode, body: response.result as string });
      const envelope = JSON.parse(body) as CFObjectEnvelope<object>;
      if (!envelope.success) {
        throw envelopeError(envelope.errors);
      }
    } finally {
      session.destroy();
    }
  }

  /// multipart/form-data PUT（KV 写值：value + metadata 两个 part 必填）
  async putMultipart(path: string, parts: MultipartPart[]): Promise<void> {
    const text = await this.requestMultipart(http.RequestMethod.PUT, path, parts);
    const envelope = JSON.parse(text) as CFObjectEnvelope<object>;
    if (!envelope.success) {
      throw envelopeError(envelope.errors);
    }
  }

  /// multipart/form-data POST/PUT 返回单对象（Snippet 上传：metadata + JS 模块 part）
  async putMultipartObject<T>(path: string, parts: MultipartPart[]): Promise<T> {
    const text = await this.requestMultipart(http.RequestMethod.PUT, path, parts);
    return this.parseObject<T>(text);
  }

  /// 用**外部 Bearer**（不是 OAuth access token）发 JSON POST，返回原始响应体。
  /// Pages 直接上传的三个资源端点（check-missing / upload / upsert-hashes）走
  /// upload-token 换来的短期 JWT，不能用账号 token。
  async bearerPostJson(path: string, bearer: string, body: object): Promise<string> {
    const session = http.createHttp();
    try {
      const response = await session.request(`${BASE_URL}${path}`, {
        method: http.RequestMethod.POST,
        header: {
          'Authorization': `Bearer ${bearer}`,
          'Content-Type': 'application/json',
        } as Record<string, string>,
        extraData: JSON.stringify(body),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 120000,
      });
      return this.unwrap({ code: response.responseCode, body: response.result as string });
    } finally {
      session.destroy();
    }
  }

  /// 用账号 OAuth token 往**站外主机**发 JSON POST，返回原始响应体。
  /// R2 SQL 的查询端点在独立主机 api.sql.cloudflarestorage.com（不是 client/v4），
  /// 故这里收完整绝对 URL；该主机对 OAuth token 的接受度官方未明说，401/403 由调用方给指引。
  async postExternalJson(url: string, body: object): Promise<string> {
    const token = await authManager.ensureAccessToken();
    const session = http.createHttp();
    try {
      const response = await session.request(url, {
        method: http.RequestMethod.POST,
        header: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json',
        } as Record<string, string>,
        extraData: JSON.stringify(body),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 120000,
      });
      const code = response.responseCode;
      const text = response.result as string;
      if (code < 200 || code >= 300) {
        throw new ApiError(externalErrorMessage(code, text), code);
      }
      return text;
    } finally {
      session.destroy();
    }
  }

  /// multipart/form-data POST 返回单对象（Pages 建部署：一个 manifest 字段）
  async postMultipartObject<T>(path: string, parts: MultipartPart[]): Promise<T> {
    const text = await this.requestMultipart(http.RequestMethod.POST, path, parts);
    return this.parseObject<T>(text);
  }

  /// POST JSON 体、收二进制响应（Workers AI 文生图：多数模型直接回 PNG/JPEG 字节，
  /// 少数回 v4 信封 + base64，故这里只负责取原始字节，形态判断交给调用方）。
  async postForBytes(path: string, body: object): Promise<ArrayBuffer> {
    const token = await authManager.ensureAccessToken();
    const session = http.createHttp();
    try {
      const response = await session.request(`${BASE_URL}${path}`, {
        method: http.RequestMethod.POST,
        header: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json',
        } as Record<string, string>,
        extraData: JSON.stringify(body),
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 15000,
        readTimeout: 120000,
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new ApiError(`请求失败（HTTP ${response.responseCode}）`, response.responseCode);
      }
      return response.result as ArrayBuffer;
    } finally {
      session.destroy();
    }
  }

  /// multipart/form-data PATCH（Worker patch settings：一个名为 settings 的 JSON part）。
  /// 同 patchObject——@kit http 的 RequestMethod 没有 PATCH，走 rcp；
  /// multipart 报文自拼（与 requestMultipart 同一套 boundary 规则）。
  async patchMultipart(path: string, parts: MultipartPart[]): Promise<void> {
    const token = await authManager.ensureAccessToken();
    const boundary = `----OrangeCloud${Date.now().toString(16)}`;
    const body = buildMultipartBody(boundary, parts);
    const session = rcp.createSession();
    try {
      const headers: rcp.RequestHeaders = {
        'authorization': `Bearer ${token}`,
        'content-type': `multipart/form-data; boundary=${boundary}`,
      };
      const request = new rcp.Request(`${BASE_URL}${path}`, 'PATCH', headers, body);
      const response = await session.fetch(request);
      const text = this.unwrap({ code: response.statusCode, body: response.toString() ?? '' });
      const envelope = JSON.parse(text) as CFObjectEnvelope<object>;
      if (!envelope.success) {
        throw envelopeError(envelope.errors);
      }
    } finally {
      session.close();
    }
  }

  /// GraphQL Analytics（POST /graphql，响应不是 v4 信封而是 { data, errors }）
  async graphql(query: string, variables: object): Promise<string> {
    interface GraphQLBody {
      query: string;
      variables: object;
    }
    const body: GraphQLBody = { query: query, variables: variables };
    return await this.requestText(http.RequestMethod.POST, '/graphql', undefined, JSON.stringify(body));
  }

  private parseObject<T>(text: string): T {
    const envelope = JSON.parse(text) as CFObjectEnvelope<T>;
    if (!envelope.success || envelope.result === undefined) {
      throw envelopeError(envelope.errors);
    }
    return envelope.result;
  }

  private async sendObject<T>(method: http.RequestMethod, path: string, body: object): Promise<T> {
    const text = await this.requestText(method, path, undefined, JSON.stringify(body));
    return this.parseObject<T>(text);
  }

  private async requestText(method: http.RequestMethod, path: string, query?: Record<string, string>,
    bodyText?: string, contentType: string = 'application/json'): Promise<string> {
    const token = await authManager.ensureAccessToken();
    let requestURL = `${BASE_URL}${path}`;
    if (query) {
      const parts: string[] = [];
      for (const key of Object.keys(query)) {
        parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(query[key])}`);
      }
      if (parts.length > 0) {
        const joiner = requestURL.includes('?') ? '&' : '?';
        requestURL = `${requestURL}${joiner}${parts.join('&')}`;
      }
    }
    const session = http.createHttp();
    try {
      const response = await session.request(requestURL, {
        method: method,
        header: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': contentType,
        } as Record<string, string>,
        extraData: bodyText,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 60000,
      });
      return this.unwrap({ code: response.responseCode, body: response.result as string });
    } finally {
      session.destroy();
    }
  }

  /// 手工拼 multipart 报文（@kit http 的 multiFormDataList 对 PUT 支持不稳，自拼 boundary 最可控）
  private async requestMultipart(method: http.RequestMethod, path: string,
    parts: MultipartPart[]): Promise<string> {
    const token = await authManager.ensureAccessToken();
    const boundary = `----OrangeCloud${Date.now().toString(16)}`;
    const body = buildMultipartBody(boundary, parts);
    const session = http.createHttp();
    try {
      const response = await session.request(`${BASE_URL}${path}`, {
        method: method,
        header: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': `multipart/form-data; boundary=${boundary}`,
        } as Record<string, string>,
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 60000,
      });
      return this.unwrap({ code: response.responseCode, body: response.result as string });
    } finally {
      session.destroy();
    }
  }

  private unwrap(raw: RawResponse): string {
    if (raw.code === 401) {
      throw new ApiError('登录已过期，请重新登录', 401);
    }
    if (raw.code < 200 || raw.code >= 300) {
      // Cloudflare 错误响应也是信封格式，尽力取出 message
      try {
        const envelope = JSON.parse(raw.body) as CFListEnvelope<object>;
        throw envelopeError(envelope.errors);
      } catch (e) {
        if (e instanceof ApiError) {
          throw e;
        }
        throw new ApiError(`HTTP ${raw.code}`, raw.code);
      }
    }
    return raw.body;
  }
}

/// 全局共享实例（Service 注入用）
export const apiClient = new CFApiClient();
