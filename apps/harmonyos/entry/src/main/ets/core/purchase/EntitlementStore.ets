// Pro 权益（华为 IAP）：isPro = 年度订阅生效中 ∨ 持有终身买断（买断优先，两者并存不重复计费）。
// 对齐 iOS Core/Purchase/EntitlementStore：全局单例 @ObservedV2，启动 bootstrap 一次，
// 购买 / 恢复后 refresh；各处闸门只读 entitlement.isPro，不碰 IAP API。
//
// 发货确认（finishPurchase）是华为 IAP 的硬要求：发放权益后必须回执，否则订单挂在
// 「未发货」，可能被系统回滚。因此 bootstrap 与恢复购买都会补跑一遍 UNFINISHED 订单。
import { iap } from '@kit.IAPKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppPrefs } from '../system/AppPrefs';
import { GlobalContext } from '../system/GlobalContext';
import { describePurchaseData, IapProducts, isEntitled, ParsedPurchase, parsePurchaseData } from './IapModels';

const DOMAIN = 0x0001;
const TAG = 'Entitlement';
/// queryPurchases 分页兜底上限（本 App 只有两个商品，正常一页即完）
const MAX_PAGES = 5;
/// 是否向 IAP 服务确认发货。**必须为 true**：发放权益后不回执，订单永远停在「未交付」，
/// 生产环境会被回滚 / 退款。
///
/// 曾因真机沙盒实测「finish 之后 queryPurchases 六种组合全返回 0 条」而一度关闭，
/// 那是误判——官方 queryPurchases 文档写明：**「在沙盒场景下，已发货状态的非消耗型
/// 商品订单信息将不返回」**（实测订阅同样如此）。即沙盒确认发货后就查不到，是既定
/// 行为而非缺陷，生产环境不受此限制。关掉 finish 只是在迎合沙盒假象。
/// 沙盒下验证恢复购买的正确姿势见 loadCached 注释。
const FINISH_PURCHASE: boolean = true;
/// 本机已发放权益的落盘键（见 loadCached 的说明）
const KEY_LIFETIME = 'pro_lifetime_granted';
const KEY_SUBSCRIPTION = 'pro_subscription_granted';

/// 自编译全解锁（对齐 iOS 的 OPENSOURCE_UNLOCKED 编译条件）：
/// 官方构建保持 false；自行编译的开源版可改 true——不弹付费墙、不调用任何 IAP 接口。
const OPENSOURCE_UNLOCKED: boolean = false;

/// 购买结果，供 UI 决定提示文案
export type PurchaseOutcome = 'purchased' | 'canceled' | 'owned' | 'failed';

@ObservedV2
export class EntitlementStore {
  /// 唯一对外权益判据
  @Trace isPro: boolean = OPENSOURCE_UNLOCKED;
  @Trace hasLifetime: boolean = false;
  @Trace hasSubscription: boolean = false;
  /// 商品展示价（queryProducts 动态取，绝不硬编码价格）
  @Trace yearlyPrice: string = '';
  @Trace lifetimePrice: string = '';
  @Trace yearlyName: string = '';
  @Trace lifetimeName: string = '';
  @Trace isLoadingProducts: boolean = false;
  @Trace isPurchasing: boolean = false;
  @Trace isRestoring: boolean = false;
  /// IAP 环境不可用的原因（未登录华为账号 / 地区不支持 / 设备不支持）；非空时付费墙按钮置灰
  @Trace unavailable: string = '';
  /// 最近一次失败原因（购买 / 取价），成功即清空
  @Trace error: string = '';
  /// 最近一次查询购买记录的失败原因（带错误码）。恢复购买查不到时用它区分
  /// 「确实没买过」和「查询本身就失败了」——后者以前被静默吞掉，只显示一句没记录。
  @Trace queryFailure: string = '';

  private bootstrapped: boolean = false;

  private ctx(): common.UIAbilityContext {
    return GlobalContext.get();
  }

  /// 启动调用一次：环境检测 → 恢复权益 → 补发漏单。全程不抛，失败只置 unavailable。
  /// 环境检测失败（如尚未登录华为账号）不置 bootstrapped，下次进付费墙会重试。
  async bootstrap(): Promise<void> {
    if (OPENSOURCE_UNLOCKED || this.bootstrapped) {
      return;
    }
    try {
      await iap.queryEnvironmentStatus(GlobalContext.getBase());
      this.unavailable = '';
    } catch (e) {
      const err = e as BusinessError;
      this.unavailable = this.describe(err);
      // 带上原始错误码：1001860002 多半是签名 profile 未携带 IAP 服务能力
      //（AGC 开通应用内支付后必须重新生成签名 profile 再打包）
      hilog.warn(DOMAIN, TAG, 'IAP 环境不可用(%{public}d): %{public}s', err.code ?? -1, this.unavailable);
      return;
    }
    this.bootstrapped = true;
    try {
      const sandbox = await iap.isSandboxActivated(GlobalContext.getBase());
      hilog.info(DOMAIN, TAG, '沙盒环境=%{public}s', sandbox ? 'yes' : 'no');
    } catch (e) {
      hilog.info(DOMAIN, TAG, 'isSandboxActivated 不可用');
    }
    await this.refresh();
    await this.finishPending();
  }

  /// 读本机已发放记录。沙盒下已确认发货的订单不会从 queryPurchases 返回（官方行为，
  /// 见 FINISH_PURCHASE 注释），若只信查询结果，付过款的用户重启 App 就会掉回免费版。
  /// 故：发放过就落盘，启动先按落盘值点亮，再让查询「只增不减」。
  ///
  /// 沙盒下测恢复购买：卸载重装后本地记录已清空、queryPurchases 也查不到，此时**直接点
  /// 购买档位**即可免费恢复（华为不会重复扣款）——这是沙盒里唯一能走通的恢复路径。
  /// 跨设备 / 生产环境的 queryPurchases 恢复只能上架后用真实购买验证。
  ///
  /// TODO 生产环境确认 queryPurchases 可靠回读后，改回以查询结果为准（含失效即撤销），
  /// 届时 refresh 的「只增不减」也要一并去掉。
  async loadCached(): Promise<void> {
    if (OPENSOURCE_UNLOCKED) {
      return;
    }
    const lifetime = await AppPrefs.getString(KEY_LIFETIME, '');
    const subscription = await AppPrefs.getString(KEY_SUBSCRIPTION, '');
    if (lifetime === '1') {
      this.hasLifetime = true;
    }
    if (subscription === '1') {
      this.hasSubscription = true;
    }
    this.isPro = this.hasLifetime || this.hasSubscription;
  }

  /// 重新判定权益（购买后 / 恢复购买 / 回前台）
  async refresh(): Promise<void> {
    if (OPENSOURCE_UNLOCKED) {
      return;
    }
    this.queryFailure = '';
    const lifetime = await this.owns(iap.ProductType.NONCONSUMABLE, IapProducts.LIFETIME);
    const yearly = await this.owns(iap.ProductType.AUTORENEWABLE, IapProducts.YEARLY);
    // 只增不减：查询查到就发放；查不到**不撤销**已发放的权益。
    // 原因见 loadCached——沙盒下已发货订单不回读，若按查询结果覆写，付过款的用户会被
    // 打回免费版。副作用是退款 / 订阅过期暂不回收权益，随上面的 TODO 一起改。
    if (lifetime) {
      this.grantProduct(IapProducts.LIFETIME);
    }
    if (yearly) {
      this.grantProduct(IapProducts.YEARLY);
    }
  }

  /// 查当前有效权益里是否含指定商品，三级回落（每级都记日志，便于真机定位）：
  ///   ① CURRENT_ENTITLEMENT —— 正规路径，语义即「当前拥有权益的最新一笔」，状态未知也算数
  ///   ② UNFINISHED         —— 已付款但没确认发货的，同样是有效购买
  ///   ③ ALL                —— 历史全量兜底。订阅在这级**必须** status==1，否则过期订阅会被
  ///      当成有效；非消耗型没有状态段可判，这级放行——代价是被退款的买断也可能恢复，
  ///      两害相权取「付了钱的人能恢复」。
  private async owns(productType: iap.ProductType, productId: string): Promise<boolean> {
    if (await this.scan(productType, productId, iap.PurchaseQueryType.CURRENT_ENTITLEMENT, false)) {
      return true;
    }
    if (await this.scan(productType, productId, iap.PurchaseQueryType.UNFINISHED, false)) {
      return true;
    }
    const requireActive = productType === iap.ProductType.AUTORENEWABLE;
    return await this.scan(productType, productId, iap.PurchaseQueryType.ALL, requireActive);
  }

  /// 按 queryType 翻页扫描；requireActive=true 时只认 status==1
  private async scan(productType: iap.ProductType, productId: string,
    queryType: iap.PurchaseQueryType, requireActive: boolean): Promise<boolean> {
    let token: string | undefined = undefined;
    for (let page = 0; page < MAX_PAGES; page++) {
      try {
        // 首页不带 continuationToken（显式传 undefined 也是一个不必要的变量，直接不传）
        const param: iap.QueryPurchasesParameter = (token === undefined || token === '')
          ? { productType: productType, queryType: queryType }
          : { productType: productType, queryType: queryType, continuationToken: token };
        const result = await iap.queryPurchases(this.ctx(), param);
        hilog.info(DOMAIN, TAG, 'queryPurchases type=%{public}d query=%{public}d 返回 %{public}d 条',
          productType, queryType, result.purchaseDataList.length);
        for (const data of result.purchaseDataList) {
          const purchases = parsePurchaseData(data);
          // 每条都打结构摘要（不含签名与敏感值）：真机定位全靠这行
          hilog.info(DOMAIN, TAG, '条目 %{public}s → 解析 %{public}d 笔',
            describePurchaseData(data), purchases.length);
          if (purchases.length === 0) {
            continue;
          }
          for (const purchase of purchases) {
            if (purchase.productId !== productId) {
              continue;
            }
            const ok = requireActive ? purchase.status === 1 : isEntitled(purchase);
            hilog.info(DOMAIN, TAG, '命中商品 %{public}s status=%{public}d 判定=%{public}s',
              purchase.productId, purchase.status, ok ? 'yes' : 'no');
            if (ok) {
              return true;
            }
          }
        }
        token = result.continuationToken;
        if (token === undefined || token === '') {
          return false;
        }
      } catch (e) {
        const err = e as BusinessError;
        const code = err.code ?? -1;
        this.queryFailure = `查询购买记录失败（错误码 ${code}）`;
        hilog.warn(DOMAIN, TAG, 'queryPurchases 失败(%{public}d) type=%{public}d query=%{public}d',
          code, productType, queryType);
        return false;
      }
    }
    return false;
  }

  /// 取商品展示价（付费墙打开时调用；失败不阻断，按钮显示无价文案）
  async loadProducts(): Promise<void> {
    if (OPENSOURCE_UNLOCKED || this.isLoadingProducts) {
      return;
    }
    this.isLoadingProducts = true;
    try {
      const subs = await iap.queryProducts(this.ctx(), {
        productType: iap.ProductType.AUTORENEWABLE,
        productIds: [IapProducts.YEARLY],
      });
      for (const product of subs) {
        if (product.id === IapProducts.YEARLY) {
          this.yearlyPrice = product.price;
          this.yearlyName = product.name;
        }
      }
      const oneOff = await iap.queryProducts(this.ctx(), {
        productType: iap.ProductType.NONCONSUMABLE,
        productIds: [IapProducts.LIFETIME],
      });
      for (const product of oneOff) {
        if (product.id === IapProducts.LIFETIME) {
          this.lifetimePrice = product.price;
          this.lifetimeName = product.name;
        }
      }
      this.error = '';
    } catch (e) {
      const err = e as BusinessError;
      this.error = this.describe(err);
      hilog.warn(DOMAIN, TAG, 'queryProducts 失败: %{public}s', this.error);
    } finally {
      this.isLoadingProducts = false;
    }
  }

  async purchaseYearly(): Promise<PurchaseOutcome> {
    return await this.buy(IapProducts.YEARLY, iap.ProductType.AUTORENEWABLE);
  }

  async purchaseLifetime(): Promise<PurchaseOutcome> {
    return await this.buy(IapProducts.LIFETIME, iap.ProductType.NONCONSUMABLE);
  }

  private async buy(productId: string, productType: iap.ProductType): Promise<PurchaseOutcome> {
    if (OPENSOURCE_UNLOCKED) {
      return 'purchased';
    }
    if (this.isPurchasing) {
      return 'failed';
    }
    this.isPurchasing = true;
    this.error = '';
    try {
      const param: iap.PurchaseParameter = { productId: productId, productType: productType };
      const result = await iap.createPurchase(this.ctx(), param);
      // createPurchase 正常返回 = 订单已成立并付款，权益先发下去：
      // 回执结构未来若再变，也绝不能出现「钱付了没解锁」。
      this.grantProduct(productId);
      const purchases = parsePurchaseData(result.purchaseData);
      if (purchases.length === 0) {
        // 解析不出就没有 purchaseToken，本次没法确认发货；打结构摘要，
        // 下次 bootstrap 的 UNFINISHED 扫描会把这笔补上。
        hilog.warn(DOMAIN, TAG, '购买回执解析为空: %{public}s', describePurchaseData(result.purchaseData));
        return 'purchased';
      }
      for (const purchase of purchases) {
        if (purchase.productId === productId) {
          // 发放权益后确认发货（失败不影响本次解锁，下次 bootstrap 会补）
          await this.finish(purchase);
        }
      }
      return 'purchased';
    } catch (e) {
      const err = e as BusinessError;
      const code = err.code ?? -1;
      if (code === iap.IAPErrorCode.USER_CANCELED) {
        return 'canceled';
      }
      if (code === iap.IAPErrorCode.PRODUCT_OWNED) {
        // 已拥有（换机重装 / 上一次发放没落地）。这个码本身就是权益凭据：
        // 非消耗型「已拥有」= 永久持有；订阅若已失效是允许再买的，能报此码即在订阅中。
        // 故直接发放，再跑一遍恢复补齐 finish。
        // 先按正规路径恢复（refresh 会按查询结果覆写标志位，必须放在兜底发放之前）
        await this.refresh();
        await this.finishPending();
        this.grantProduct(productId);
        return 'owned';
      }
      this.error = this.describe(err);
      hilog.warn(DOMAIN, TAG, '购买失败(%{public}d): %{public}s', code, this.error);
      return 'failed';
    } finally {
      this.isPurchasing = false;
    }
  }

  /// 恢复购买：重查权益 + 补发漏单。返回恢复后是否为 Pro。
  async restore(): Promise<boolean> {
    if (OPENSOURCE_UNLOCKED) {
      return true;
    }
    if (this.isRestoring) {
      return this.isPro;
    }
    this.isRestoring = true;
    this.error = '';
    try {
      if (!this.bootstrapped) {
        // 首次环境检测失败过（如当时没登录华为账号），这里重试
        try {
          await iap.queryEnvironmentStatus(GlobalContext.getBase());
          this.unavailable = '';
          this.bootstrapped = true;
        } catch (e) {
          this.unavailable = this.describe(e as BusinessError);
          return this.isPro;
        }
      }
      await this.refresh();
      await this.finishPending();
      if (!this.isPro && this.queryFailure !== '') {
        // 查不到 ≠ 没买过：查询本身失败时把错误码告诉用户，别让人以为购买丢了
        this.error = this.queryFailure;
      }
      return this.isPro;
    } finally {
      this.isRestoring = false;
    }
  }

  /// 打开华为账号的订阅管理页（订阅类合规要求提供可达入口）
  async openManageSubscriptions(): Promise<void> {
    try {
      await iap.showManagedSubscriptions(GlobalContext.getBase(), {
        windowScreenMode: iap.WindowScreenMode.FULLSCREEN,
      });
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(DOMAIN, TAG, '打开订阅管理失败(%{public}d)', err.code ?? -1);
    }
  }

  /// 就地发放权益（购买成功即时生效，不等下一次 refresh）
  private grantProduct(productId: string): void {
    if (productId === IapProducts.LIFETIME) {
      this.hasLifetime = true;
      AppPrefs.putString(KEY_LIFETIME, '1').catch(() => {
      });
    } else if (productId === IapProducts.YEARLY) {
      this.hasSubscription = true;
      AppPrefs.putString(KEY_SUBSCRIPTION, '1').catch(() => {
      });
    } else {
      return;
    }
    this.isPro = this.hasLifetime || this.hasSubscription;
  }

  /// 补发漏单：把两类商品的「未发货」订单逐笔确认
  private async finishPending(): Promise<void> {
    await this.finishPendingOf(iap.ProductType.NONCONSUMABLE);
    await this.finishPendingOf(iap.ProductType.AUTORENEWABLE);
  }

  private async finishPendingOf(productType: iap.ProductType): Promise<void> {
    try {
      const param: iap.QueryPurchasesParameter = {
        productType: productType,
        queryType: iap.PurchaseQueryType.UNFINISHED,
      };
      const result = await iap.queryPurchases(this.ctx(), param);
      for (const data of result.purchaseDataList) {
        for (const purchase of parsePurchaseData(data)) {
          if (isEntitled(purchase)) {
            this.grantProduct(purchase.productId);
          }
          await this.finish(purchase);
        }
      }
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(DOMAIN, TAG, '补发漏单失败(%{public}d)', err.code ?? -1);
    }
  }

  /// 确认发货（见 FINISH_PURCHASE 常量的说明，当前整体关闭）
  private async finish(parsed: ParsedPurchase): Promise<void> {
    if (!FINISH_PURCHASE) {
      hilog.info(DOMAIN, TAG, '跳过 finishPurchase: %{public}s', parsed.productId);
      return;
    }
    if (parsed.purchaseToken === '' || parsed.purchaseOrderId === '') {
      return;
    }
    try {
      await iap.finishPurchase(this.ctx(), {
        productType: this.productTypeOf(parsed),
        purchaseToken: parsed.purchaseToken,
        purchaseOrderId: parsed.purchaseOrderId,
      });
    } catch (e) {
      const err = e as BusinessError;
      // 1001860053 = 已确认过，属正常幂等结果
      if (err.code !== iap.IAPErrorCode.PURCHASE_FINISHED) {
        hilog.warn(DOMAIN, TAG, 'finishPurchase 失败(%{public}d)', err.code ?? -1);
      }
    }
  }

  /// 商品类型以本地商品表为准（载荷字段缺失时也能给对），回落看是否带订阅状态段
  private productTypeOf(parsed: ParsedPurchase): iap.ProductType {
    if (parsed.productId === IapProducts.YEARLY) {
      return iap.ProductType.AUTORENEWABLE;
    }
    if (parsed.productId === IapProducts.LIFETIME) {
      return iap.ProductType.NONCONSUMABLE;
    }
    return parsed.isSubscription ? iap.ProductType.AUTORENEWABLE : iap.ProductType.NONCONSUMABLE;
  }

  /// 错误码 → 用户可读文案（未覆盖的码回落到通用提示，不把码抛给用户）
  private describe(err: BusinessError): string {
    switch (err.code) {
      case iap.IAPErrorCode.ACCOUNT_NOT_LOGGED_IN:
        return '请先登录华为账号后再购买';
      case iap.IAPErrorCode.NETWORK_ERROR:
        return '网络连接失败，请稍后重试';
      case iap.IAPErrorCode.ACCOUNT_TERRITORY_NOT_SUPPORTED:
        return '当前华为账号所在国家 / 地区暂不支持应用内购买';
      case iap.IAPErrorCode.PRODUCT_TERRITORY_NOT_SUPPORTED:
        return '本商品在当前国家 / 地区未上架';
      case iap.IAPErrorCode.INVALID_PRODUCT:
        return '商品信息不可用，请稍后重试';
      case iap.IAPErrorCode.USER_NOT_ALLOWED:
        return '当前账号不允许进行购买';
      case iap.IAPErrorCode.APP_NOT_AUTHORIZED:
        return '应用未获授权，请更新到最新版本';
      case iap.IAPErrorCode.FREQUENT_CALLS:
        return '操作过于频繁，请稍后重试';
      case 801:
        return '当前设备不支持应用内购买';
      default:
        return '支付服务暂不可用，请稍后重试';
    }
  }
}

/// 全局单例：EntryAbility 启动时 bootstrap，各闸门只读 isPro
export const entitlement = new EntitlementStore();
