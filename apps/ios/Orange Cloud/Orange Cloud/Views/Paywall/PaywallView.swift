//
//  PaywallView.swift
//  Orange Cloud
//
//  场景付费墙（sheet）：从六个 Pro 闸门与设置页入口弹出。
//  三档商品（年度主推/月度/买断）全部从 StoreKit 动态取价，不硬编码任何价格；
//  试用时长 / 续订周期同样取自 StoreKit，且只对仍有资格的账户展示试用（见 SubscriptionOfferText）。
//  含恢复购买与隐私政策/使用条款链接（订阅审核硬性要求）。
//

import SwiftUI
import StoreKit

struct PaywallView: View {

    /// 触发场景；nil = 从设置页常驻入口打开
    var feature: ProFeature? = nil

    @Environment(EntitlementStore.self) private var entitlements
    @Environment(\.dismiss) private var dismiss
    @Environment(\.purchase) private var purchase

    @State private var selectedID = EntitlementStore.ProductID.yearly
    @State private var isPurchasing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header

                    if entitlements.isPro {
                        unlockedCard
                    } else {
                        featureList
                        planPicker
                        ctaButton
                        restoreButton
                    }

                    legalFooter
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background { SkyBackground() }
            .navigationTitle("Orange Cloud Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭")
                }
            }
        }
        .task {
            await entitlements.loadProducts()
        }
        .alert("购买失败", isPresented: .init(
            get: { entitlements.purchaseError != nil },
            set: { if !$0 { entitlements.purchaseError = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(entitlements.purchaseError ?? "")
        }
        .sensoryFeedback(.success, trigger: entitlements.isPro)
    }

    // MARK: - 头部

    private var header: some View {
        VStack(spacing: 8) {
            TintIcon(systemImage: feature?.systemImage ?? "sparkles", color: .ocOrange, size: 56)
                .padding(.top, 12)

            Text(feature?.headline ?? String(localized: "解锁多账号与全部专业功能"))
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)

            if let feature {
                Text(feature.blurb)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 已解锁

    private var unlockedCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.ocOrange)
                .oneShotBounceSymbolEffect()
            Text("Pro 已解锁")
                .font(.headline)
            Text("感谢支持 Orange Cloud 的持续开发。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .glassIsland()
    }

    // MARK: - Pro 功能清单

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 12) {
            bulletRow("person.2",                      String(localized: "多账号快速切换"))
            bulletRow("externaldrive",                 String(localized: "存储管理（R2 / D1 / KV）"))
            bulletRow("text.alignleft",                String(localized: "Workers 实时日志 + Live Activity"))
            bulletRow("shield",                        String(localized: "WAF 规则启停"))
            bulletRow("arrow.triangle.2.circlepath",   String(localized: "Cloudflare Tunnel"))
            bulletRow("chart.xyaxis.line",             String(localized: "完整流量分析（7 / 30 天）"))
        }
        .padding(OCLayout.islandPadding + 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassIsland()
    }

    private func bulletRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.ocOrange)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }

    // MARK: - 三档选择

    @ViewBuilder
    private var planPicker: some View {
        if entitlements.products.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            VStack(spacing: 10) {
                ForEach(entitlements.products, id: \.id) { product in
                    planRow(product)
                }
            }
        }
    }

    private func planRow(_ product: Product) -> some View {
        let isSelected = selectedID == product.id
        return Button {
            selectedID = product.id
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(planName(product))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        if product.id == EntitlementStore.ProductID.yearly {
                            Text("推荐")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.ocOrangeText)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.ocOrange.opacity(0.16), in: Capsule())
                        }
                    }
                    Text(planDetail(product))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(product.displayPrice)
                    .font(.body.weight(.bold))
                    .foregroundStyle(.primary)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.ocOrange : Color.secondary.opacity(0.4))
            }
            .padding(OCLayout.islandPadding)
            .glassIsland(cornerRadius: OCLayout.chipRadius)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: OCLayout.chipRadius, style: .continuous)
                        .strokeBorder(Color.ocOrange.opacity(0.7), lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func planName(_ product: Product) -> String {
        switch product.id {
        case EntitlementStore.ProductID.yearly:   String(localized: "年度")
        case EntitlementStore.ProductID.monthly:  String(localized: "月度")
        case EntitlementStore.ProductID.lifetime: String(localized: "买断")
        default: product.displayName
        }
    }

    /// 订阅：「[首次优惠 · ]续订周期」，优惠只在当前账户仍有资格时显示；时长与形式全取自 StoreKit。
    private func planDetail(_ product: Product) -> String {
        if let subscription = product.subscription {
            let renewal = SubscriptionOfferText.renewal(subscription.subscriptionPeriod)
            guard let offer = entitlements.eligibleIntroOffers[product.id] else { return renewal }
            return "\(SubscriptionOfferText.offer(offer)) · \(renewal)"
        }
        if product.id == EntitlementStore.ProductID.lifetime {
            return String(localized: "一次性付费 · 含未来全部新模块")
        }
        return product.description
    }

    // MARK: - 购买

    private var selectedProduct: Product? {
        entitlements.products.first { $0.id == selectedID }
    }

    private var ctaTitle: String {
        guard let product = selectedProduct else { return String(localized: "解锁 Pro") }
        if product.id == EntitlementStore.ProductID.lifetime {
            return String(localized: "买断 Pro")
        }
        if let offer = entitlements.eligibleIntroOffers[product.id],
           let trial = SubscriptionOfferText.freeTrialCTA(offer) {
            return trial
        }
        return String(localized: "解锁 Pro")
    }

    private var ctaButton: some View {
        Button {
            Task { await buySelected() }
        } label: {
            Group {
                if isPurchasing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(ctaTitle)
                        .font(.body.weight(.bold))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.ocOrangePressed)
        .disabled(isPurchasing || selectedProduct == nil)
    }

    private var restoreButton: some View {
        Button("恢复购买") {
            Task {
                await entitlements.restorePurchases()
            }
        }
        .font(.footnote)
        .disabled(isPurchasing)
    }

    private func buySelected() async {
        guard let product = selectedProduct else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await purchase(product)
            await entitlements.handle(result)
        } catch {
            entitlements.purchaseError = error.localizedDescription
        }
    }

    // MARK: - 法律脚注

    private var legalFooter: some View {
        VStack(spacing: 8) {
            Text("订阅会自动续订，可随时在系统「设置 › Apple 账户 › 订阅」中取消。买断为一次性付费，永久有效。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Link("隐私政策", destination: URL(string: "https://o-c.do/privacy")!)
                Link("使用条款", destination: URL(string: "https://o-c.do/terms")!)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }
}

#Preview {
    PaywallView(feature: .storage)
        .environment(EntitlementStore.shared)
}
