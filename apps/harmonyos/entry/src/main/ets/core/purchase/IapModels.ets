// 华为 IAP 商品定义与 purchaseData 载荷解析（对齐 iOS Core/Purchase 的 StoreKit 层）。
// AGC 后台配置的商品 ID 必须与此处常量一致：年度自动续期订阅 + 终身买断（非消耗型）。
//
// purchaseData 是一个 JSON 字符串，内含若干段 JWS（= base64url(header).base64url(payload).sig）。
// 各接口给的键名并不统一，实测/文档出现过这些形态，本文件全部兼容：
//   createPurchase   → { jwsPurchaseOrder, jwsSubscriptionStatus }
//   queryPurchases   → { jwsPurchaseOrder, jwsSubGroupStatus }（订阅商品可能只给状态段）
// 订阅状态段解出 SubGroupStatusPayload，其 lastSubscriptionStatus **可能是对象也可能是数组**
// （一个订阅组可含多个商品），两种都要吃；订单三件套在 lastSubscriptionStatus.lastPurchaseOrder。
//
// 注意：这里只解 payload 供端侧判权益，**不验签**——华为要求把 purchaseData 送应用服务器用
// 华为公钥验签后再发货。鸿蒙版当前无自有权益服务端，先按端侧判定；后续接服务端时，把验签
// 挂在 EntitlementStore 发放权益之前即可（解析结构不用改）。
import { util } from '@kit.ArkTS';

export class IapProducts {
  /// 自动续期订阅（年）
  static readonly YEARLY: string = 'ltd.zhe.orange_cloud.pro.yearly';
  /// 非消耗型（终身买断）
  static readonly LIFETIME: string = 'ltd.zhe.orange_cloud.pro.lifetime';
}

/// 订阅生效中
export const SUBSCRIPTION_ACTIVE: number = 1;
/// 拿不到状态段（非消耗型商品，或状态结构不认识）——不等于失效，由调用方按数据来源决定
export const SUBSCRIPTION_UNKNOWN: number = -1;

interface PurchaseDataEnvelope {
  jwsPurchaseOrder?: string;
  jwsSubscriptionStatus?: string;
  jwsSubGroupStatus?: string;
}

/// jwsPurchaseOrder 解出的订单载荷（只声明本模块用到的字段）
interface PurchaseOrderPayload {
  productId?: string;
  purchaseToken?: string;
  purchaseOrderId?: string;
}

interface LastSubscriptionStatus {
  status?: number;
  lastPurchaseOrder?: PurchaseOrderPayload;
}

/// 订阅组状态载荷的两种形态（同一段 JSON 分别按对象 / 数组读一次，见 statusEntries）
interface SubGroupStatusObject {
  lastSubscriptionStatus?: LastSubscriptionStatus;
}

interface SubGroupStatusArray {
  lastSubscriptionStatus?: LastSubscriptionStatus[];
}

/// 一笔购买的归一化结果：权益判断 + finishPurchase 三件套
export interface ParsedPurchase {
  productId: string;
  /// SUBSCRIPTION_ACTIVE / 其它状态码 / SUBSCRIPTION_UNKNOWN
  status: number;
  purchaseToken: string;
  purchaseOrderId: string;
  isSubscription: boolean;
}

/// 该笔是否应当发放权益：订阅看状态码；状态未知（非消耗型 / 结构不认识）交由调用方保证来源可信
/// —— owns() 只喂 CURRENT_ENTITLEMENT 的结果，那本身就是「当前有权益」的过滤结果。
export function isEntitled(purchase: ParsedPurchase): boolean {
  return purchase.status === SUBSCRIPTION_ACTIVE || purchase.status === SUBSCRIPTION_UNKNOWN;
}

/// base64url → 字节 → UTF-8 文本（JWS 各段无 padding，先补齐再按标准 base64 解）
function decodeSegment(segment: string): string {
  let normalized = segment.replace(/-/g, '+').replace(/_/g, '/');
  const remainder = normalized.length % 4;
  if (remainder === 2) {
    normalized += '==';
  } else if (remainder === 3) {
    normalized += '=';
  }
  const bytes = new util.Base64Helper().decodeSync(normalized, util.Type.BASIC);
  return util.TextDecoder.create('utf-8').decodeToString(bytes);
}

/// 取 JWS 的 payload 段文本（不验签，见文件头说明）；结构不对返回空串
function jwsPayload(jws: string): string {
  const parts = jws.split('.');
  if (parts.length < 2) {
    return '';
  }
  return decodeSegment(parts[1]);
}

/// 订阅状态段 → 条目列表（对象形态给 1 条，数组形态给 N 条）
function statusEntries(payloadText: string): LastSubscriptionStatus[] {
  const out: LastSubscriptionStatus[] = [];
  const asArray = JSON.parse(payloadText) as SubGroupStatusArray;
  const many = asArray.lastSubscriptionStatus;
  if (many !== undefined && Array.isArray(many)) {
    for (const item of many) {
      out.push(item);
    }
    return out;
  }
  const asObject = JSON.parse(payloadText) as SubGroupStatusObject;
  const one = asObject.lastSubscriptionStatus;
  if (one !== undefined) {
    out.push(one);
  }
  return out;
}

function toParsed(order: PurchaseOrderPayload, status: number, isSubscription: boolean): ParsedPurchase | null {
  const productId = order.productId ?? '';
  if (productId === '') {
    return null;
  }
  const parsed: ParsedPurchase = {
    productId: productId,
    status: status,
    purchaseToken: order.purchaseToken ?? '',
    purchaseOrderId: order.purchaseOrderId ?? '',
    isSubscription: isSubscription,
  };
  return parsed;
}

/// 解析一条 purchaseData（createPurchase 的返回值 / queryPurchases 列表项）。
/// 一条 purchaseData 可能含多笔（订阅组数组形态），故返回列表；解不出返回空列表。
export function parsePurchaseData(purchaseData: string): ParsedPurchase[] {
  const results: ParsedPurchase[] = [];
  try {
    const envelope = JSON.parse(purchaseData) as PurchaseDataEnvelope;
    // 状态段两个键名都可能出现，取到哪个用哪个
    const jwsStatus = envelope.jwsSubscriptionStatus ?? envelope.jwsSubGroupStatus ?? '';
    if (jwsStatus !== '') {
      const text = jwsPayload(jwsStatus);
      if (text !== '') {
        for (const entry of statusEntries(text)) {
          const order = entry.lastPurchaseOrder;
          if (order === undefined) {
            continue;
          }
          const parsed = toParsed(order, entry.status ?? SUBSCRIPTION_UNKNOWN, true);
          if (parsed !== null) {
            results.push(parsed);
          }
        }
      }
    }
    // 订单段：非消耗型的唯一来源；订阅若状态段没解出条目也回落到它
    const jwsOrder = envelope.jwsPurchaseOrder ?? '';
    if (results.length === 0 && jwsOrder !== '') {
      pushFromOrderPayload(jwsPayload(jwsOrder), jwsStatus !== '', results);
    }
  } catch (e) {
    // 不是 JSON 信封，落到下面的裸 JWS 兜底
  }
  // 兜底：整串本身就是一段裸 JWS（queryPurchases 的条目未必包信封，
  // 与 createPurchase 的返回结构不一致）。按订单载荷和订阅组状态载荷各试一次。
  if (results.length === 0) {
    try {
      const text = jwsPayload(purchaseData);
      if (text !== '') {
        for (const entry of statusEntries(text)) {
          const order = entry.lastPurchaseOrder;
          if (order !== undefined) {
            const parsed = toParsed(order, entry.status ?? SUBSCRIPTION_UNKNOWN, true);
            if (parsed !== null) {
              results.push(parsed);
            }
          }
        }
        if (results.length === 0) {
          pushFromOrderPayload(text, false, results);
        }
      }
    } catch (e) {
      // 两种形态都不是，交给调用方兜底
    }
  }
  return results;
}

/// 把一段订单载荷 JSON 文本解成条目追加进 out
function pushFromOrderPayload(payloadText: string, isSubscription: boolean, out: ParsedPurchase[]): void {
  if (payloadText === '') {
    return;
  }
  const order = JSON.parse(payloadText) as PurchaseOrderPayload;
  const parsed = toParsed(order, SUBSCRIPTION_UNKNOWN, isSubscription);
  if (parsed !== null) {
    out.push(parsed);
  }
}

/// 诊断用：把 purchaseData 的结构摘成一行日志（不含签名与敏感值），
/// 便于真机上核对键名与状态码——线上解析失败时才打，正常路径不打。
export function describePurchaseData(purchaseData: string): string {
  try {
    const envelope = JSON.parse(purchaseData) as PurchaseDataEnvelope;
    const keys = Object.keys(envelope as Object).join(',');
    if (keys === '') {
      return '空对象';
    }
    const jwsStatus = envelope.jwsSubscriptionStatus ?? envelope.jwsSubGroupStatus ?? '';
    let statusInfo = 'none';
    if (jwsStatus !== '') {
      const text = jwsPayload(jwsStatus);
      const entries = statusEntries(text);
      const codes: string[] = [];
      for (const entry of entries) {
        codes.push(`${entry.status ?? SUBSCRIPTION_UNKNOWN}`);
      }
      statusInfo = `topKeys=${Object.keys(JSON.parse(text) as Object).join(',')} n=${entries.length} status=[${codes.join(' ')}]`;
    }
    return `envelope=[${keys}] ${statusInfo}`;
  } catch (e) {
    // 不是 JSON：多半是裸 JWS，把 payload 顶层键名摘出来（这正是要确认的形态）
    try {
      const text = jwsPayload(purchaseData);
      if (text === '') {
        return `非 JSON 且非 JWS（前 24 字符: ${purchaseData.substring(0, 24)}）`;
      }
      return `裸JWS payloadKeys=[${Object.keys(JSON.parse(text) as Object).join(',')}]`;
    } catch (inner) {
      return `无法解析（前 24 字符: ${purchaseData.substring(0, 24)}）`;
    }
  }
}
