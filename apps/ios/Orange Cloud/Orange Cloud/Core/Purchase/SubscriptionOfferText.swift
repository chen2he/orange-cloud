//
//  SubscriptionOfferText.swift
//  Orange Cloud
//
//  付费墙上的订阅周期 / 首次优惠文案，全部由 StoreKit 返回的商品数据生成：
//  试用时长、优惠形式、续订周期改在 App Store Connect 即生效，App 内不写死任何天数。
//  时长用 DateComponentsFormatter 本地化（「7 天」「1 个月」「3 days」…），只允许
//  该周期自身的单位，避免 7 天被折算成「1 周」。
//

import Foundation
import StoreKit

nonisolated enum SubscriptionOfferText {

    /// 周期时长：value × count 个 unit，本地化为「7天」「3 个月」「1 year」。
    static func duration(_ period: Product.SubscriptionPeriod, count: Int = 1) -> String {
        let n = period.value * max(count, 1)
        var components = DateComponents()
        let unit: NSCalendar.Unit
        switch period.unit {
        case .day:   components.day = n;         unit = .day
        case .week:  components.weekOfMonth = n; unit = .weekOfMonth
        case .month: components.month = n;       unit = .month
        case .year:  components.year = n;        unit = .year
        @unknown default: components.day = n;    unit = .day
        }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = unit
        formatter.maximumUnitCount = 1
        return formatter.string(from: components) ?? ""
    }

    /// 续订说明：「每年自动续订」「每月自动续订」；非单位周期如「每 3 个月自动续订」。
    static func renewal(_ period: Product.SubscriptionPeriod) -> String {
        guard period.value == 1 else {
            return String(localized: "每 \(duration(period)) 自动续订")
        }
        switch period.unit {
        case .year:  return String(localized: "每年自动续订")
        case .month: return String(localized: "每月自动续订")
        case .week:  return String(localized: "每周自动续订")
        case .day:   return String(localized: "每天自动续订")
        @unknown default: return String(localized: "每 \(duration(period)) 自动续订")
        }
    }

    /// 首次优惠说明：免费试用 / 首期一次性优惠价 / 前几期按期优惠价。
    static func offer(_ offer: Product.SubscriptionOffer) -> String {
        let total = duration(offer.period, count: offer.periodCount)
        switch offer.paymentMode {
        case .freeTrial:
            return String(localized: "\(total)免费试用")
        case .payUpFront:
            return String(localized: "首 \(total) 仅需 \(offer.displayPrice)")
        case .payAsYouGo:
            return String(localized: "首 \(total) 优惠价 \(offer.displayPrice)/\(duration(offer.period))")
        default:
            return ""
        }
    }

    /// 购买按钮：只有免费试用改写成「开始 X 免费试用」，付费优惠仍是「解锁 Pro」（价格已在行内写明）。
    static func freeTrialCTA(_ offer: Product.SubscriptionOffer) -> String? {
        guard offer.paymentMode == .freeTrial else { return nil }
        return String(localized: "开始\(duration(offer.period, count: offer.periodCount))免费试用")
    }
}
