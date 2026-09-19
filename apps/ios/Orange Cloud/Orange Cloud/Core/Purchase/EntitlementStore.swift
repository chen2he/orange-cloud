//
//  EntitlementStore.swift
//  Orange Cloud
//
//  Pro 解锁状态（StoreKit 2）：有效订阅（月/年）或买断任一存在即 Pro。
//  开源自编译构建：OPENSOURCE_UNLOCKED 编译条件直接全功能，运行时不发起任何 StoreKit 调用。
//

import Foundation
import StoreKit

@Observable
@MainActor
final class EntitlementStore {

    static let shared = EntitlementStore()

    nonisolated enum ProductID {
        static let monthly  = "jiamin.chen.orange_cloud.pro.monthly"
        static let yearly   = "jiamin.chen.orange_cloud.pro.yearly"
        static let lifetime = "jiamin.chen.orange_cloud.pro.lifetime"
        /// 付费墙展示顺序：年度（主推）→ 月度 → 买断
        static let all = [yearly, monthly, lifetime]
    }

    /// StoreKit 验证出的解锁状态（订阅有效或持有买断）
    private var entitled = false
    private(set) var hasLifetime = false
    /// 按 ProductID.all 顺序排列，付费墙直接展示
    private(set) var products: [Product] = []
    /// 当前 Apple 账户仍可享受的首次优惠（免费试用等），按商品 ID。
    /// 用过试用 / 订阅过同组的账户 Apple 判定不再有资格——此时不在表里，付费墙不能再写「免费试用」。
    /// 资格未查清前为空（宁可少展示优惠，也不误导成免费）。
    private(set) var eligibleIntroOffers: [String: Product.SubscriptionOffer] = [:]
    private(set) var isLoadingProducts = false
    /// 恢复购买进行中（防并发 AppStore.sync 互相取消；付费墙据此禁用按钮）
    private(set) var isRestoring = false
    var purchaseError: String?

    private var updatesTask: Task<Void, Never>?

    var isPro: Bool {
        #if OPENSOURCE_UNLOCKED
        return true
        #else
        return entitled
        #endif
    }

    /// App 启动时调用一次：恢复当前 entitlement 并监听后续交易（含外部购买/退款）
    func start() {
        #if !OPENSOURCE_UNLOCKED
        guard updatesTask == nil else { return }
        updatesTask = Task {
            await refreshEntitlements()
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await refreshEntitlements()
            }
        }
        #endif
    }

    func loadProducts() async {
        #if !OPENSOURCE_UNLOCKED
        guard products.isEmpty, !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let loaded = try await Product.products(for: ProductID.all)
            products = ProductID.all.compactMap { id in loaded.first { $0.id == id } }
            if products.isEmpty {
                // 不抛错但结果为空：StoreKit 配置文件解析失败或商品 ID 不匹配
                AppLog.purchase.error("Product.products(for:) 返回空结果，请求的 ID：\(ProductID.all.joined(separator: ", "))")
                purchaseError = String(localized: "无法加载商品信息，请稍后再试。")
            } else {
                AppLog.purchase.info("已加载 \(self.products.count) 个商品")
                await refreshIntroOfferEligibility()
            }
        } catch {
            AppLog.purchase.error("Product.products(for:) 失败：\(String(describing: error))")
            purchaseError = String(localized: "无法加载商品信息，请稍后再试。")
        }
        #endif
    }

    /// 处理 PaywallView 的购买结果（购买动作经 SwiftUI 的 \.purchase 发起）
    func handle(_ result: Product.PurchaseResult) async {
        switch result {
        case .success(let verification):
            if case .verified(let transaction) = verification {
                await transaction.finish()
                await refreshEntitlements()
                AppLog.purchase.notice("purchase verified: \(transaction.productID)")
            } else {
                AppLog.purchase.error("purchase result unverified")
                purchaseError = String(localized: "购买凭证校验失败，请尝试恢复购买。")
            }
        case .userCancelled, .pending:
            AppLog.purchase.info("purchase userCancelled/pending")
            break
        @unknown default:
            break
        }
    }

    func restorePurchases() async {
        #if !OPENSOURCE_UNLOCKED
        // 防重入：连点「恢复购买」会并发调用 AppStore.sync()，StoreKit 把前一个取消
        //（成对的 "restorePurchases failed: 请求已取消"）。进行中直接忽略后续调用。
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            AppLog.purchase.notice("restorePurchases synced, pro=\(entitled)")
        } catch {
            // 用户主动取消（关掉 App Store 登录弹窗等）不是故障：不弹错误、降级 info 不进遥测
            let isCancellation: Bool = {
                if error is CancellationError { return true }
                if let urlError = error as? URLError, urlError.code == .cancelled { return true }
                if case StoreKitError.userCancelled = error { return true }
                return false
            }()
            if isCancellation {
                AppLog.purchase.info("restorePurchases cancelled by user")
            } else {
                AppLog.purchase.error("restorePurchases failed: \(error.localizedDescription)")
                purchaseError = error.localizedDescription
            }
        }
        #endif
    }

    private func refreshEntitlements() async {
        var pro = false
        var lifetime = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.revocationDate == nil else { continue }
            switch transaction.productID {
            case ProductID.lifetime:
                lifetime = true
                pro = true
            case ProductID.monthly, ProductID.yearly:
                pro = true
            default:
                break
            }
        }
        hasLifetime = lifetime
        entitled = pro
        AppLog.purchase.info("entitlements refreshed: pro=\(pro) lifetime=\(lifetime)")
        // 购买 / 恢复 / 退款都可能改变试用资格
        await refreshIntroOfferEligibility()
    }

    private func refreshIntroOfferEligibility() async {
        var eligible: [String: Product.SubscriptionOffer] = [:]
        for product in products {
            guard let subscription = product.subscription,
                  let offer = subscription.introductoryOffer else { continue }
            if await subscription.isEligibleForIntroOffer {
                eligible[product.id] = offer
            }
        }
        eligibleIntroOffers = eligible
        AppLog.purchase.info("intro offer eligible: \(eligible.keys.sorted().joined(separator: ", "))")
    }
}
