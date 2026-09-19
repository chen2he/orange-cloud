//
//  ZoneAnalyticsViewModel.swift
//  Orange Cloud
//
//  Zone 流量分析：当前 + 前一周期并发加载（环比趋势），会话级内存缓存。
//  不进 SwiftData——时间窗口随"现在"滚动，持久化命中率几乎为零。
//

import Foundation
import Observation

@Observable
@MainActor
final class ZoneAnalyticsViewModel {

    var selectedRange: AnalyticsTimeRange = .last24h
    var isLoading = false
    var error: String?
    private(set) var points: [TrafficDataPoint] = []
    private(set) var previousPoints: [TrafficDataPoint] = []

    // 全球流量地图：按国家/地区聚合，独立加载（仅 Pro 触发），与主时间序列分离
    var isLoadingCountries = false
    private(set) var countries: [CountryTraffic] = []
    private var countryCache: [AnalyticsTimeRange: [CountryTraffic]] = [:]

    private var cache: [AnalyticsTimeRange: (current: [TrafficDataPoint], previous: [TrafficDataPoint])] = [:]
    private let analyticsService: AnalyticsService
    private let zoneId: String

    init(analyticsService: AnalyticsService, zoneId: String) {
        self.analyticsService = analyticsService
        self.zoneId = zoneId
    }

    // MARK: - 汇总

    var totalRequests:  Int { points.reduce(0) { $0 + $1.requests } }
    var totalBytes:     Int { points.reduce(0) { $0 + $1.bytes } }
    var totalThreats:   Int { points.reduce(0) { $0 + $1.threats } }
    var totalPageViews: Int { points.reduce(0) { $0 + $1.pageViews } }
    var totalUniques:   Int { points.reduce(0) { $0 + $1.uniques } }
    private var totalCachedRequests: Int { points.reduce(0) { $0 + $1.cachedRequests } }

    /// 缓存命中率（0–100），无请求时 nil
    var cacheHitRate: Double? {
        guard totalRequests > 0 else { return nil }
        return Double(totalCachedRequests) / Double(totalRequests) * 100
    }

    // MARK: - 环比趋势（与前一等长周期对比）

    private var prevRequests: Int { previousPoints.reduce(0) { $0 + $1.requests } }
    private var prevBytes:    Int { previousPoints.reduce(0) { $0 + $1.bytes } }
    private var prevThreats:  Int { previousPoints.reduce(0) { $0 + $1.threats } }
    private var prevUniques:  Int { previousPoints.reduce(0) { $0 + $1.uniques } }
    private var prevCachedRequests: Int { previousPoints.reduce(0) { $0 + $1.cachedRequests } }

    var requestsTrend: Double? { percentChange(current: totalRequests, previous: prevRequests) }
    var bytesTrend:    Double? { percentChange(current: totalBytes, previous: prevBytes) }
    var threatsTrend:  Double? { percentChange(current: totalThreats, previous: prevThreats) }
    var uniquesTrend:  Double? { percentChange(current: totalUniques, previous: prevUniques) }

    /// 命中率变化（百分点差）
    var cacheHitTrendPt: Double? {
        guard let current = cacheHitRate, prevRequests > 0 else { return nil }
        let previous = Double(prevCachedRequests) / Double(prevRequests) * 100
        return current - previous
    }

    private func percentChange(current: Int, previous: Int) -> Double? {
        guard previous > 0 else { return nil }
        return (Double(current) - Double(previous)) / Double(previous) * 100
    }

    // MARK: - 加载

    func load(force: Bool = false) async {
        // 把范围钉在发起时刻：视图在 onChange(of: selectedRange) 里起的是不取消的 Task，
        // 快速 24h→7d→30d 会有多个请求在飞；以前 await 之后再读 selectedRange，
        // 慢到的 7d 数据会写进 .last30d 的缓存、图表也跟着错位，直到下拉刷新才纠正。
        let range = selectedRange
        if !force, let cached = cache[range] {
            points = cached.current
            previousPoints = cached.previous
            return
        }
        isLoading = true
        error = nil
        do {
            // 当前与前一周期并发拉取；前一周期失败不阻塞主数据（趋势显示为空）
            async let currentTask = analyticsService.zoneTraffic(zoneId: zoneId, range: range)
            async let previousTask = analyticsService.zoneTrafficPrevious(zoneId: zoneId, range: range)

            let current = try await currentTask
            let previous = (try? await previousTask) ?? []

            cache[range] = (current, previous)
            guard range == selectedRange else { return }   // 用户已切走：只进缓存，不上屏
            points = current
            previousPoints = previous
        } catch {
            guard range == selectedRange, !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
        if range == selectedRange { isLoading = false }
    }

    /// 全球流量地图数据（Pro）。地图卡 .task 调用；当前范围已有缓存则直接复用。
    /// 失败仅置空，不写主 error（地图是看板级增强，不应打断主分析区）。
    func loadCountries(force: Bool = false) async {
        let range = selectedRange
        if !force, let cached = countryCache[range] {
            countries = cached
            return
        }
        isLoadingCountries = true
        do {
            let result = try await analyticsService.zoneCountryTraffic(zoneId: zoneId, range: range)
            countryCache[range] = result
            guard range == selectedRange else { return }
            countries = result
        } catch {
            guard range == selectedRange, !error.isCancellation else { return }
            countries = []
        }
        if range == selectedRange { isLoadingCountries = false }
    }

    /// 下拉刷新：清空缓存重新拉取
    func refresh() async {
        cache.removeAll()
        countryCache.removeAll()
        clearInsight()
        await load(force: true)
    }

    // MARK: - 设备端 AI 摘要（只读，Pro）

    var isSummarizing = false
    var summaryError: String?
    private(set) var insight: TrafficInsight?

    /// 换时间范围 / 刷新时清空旧摘要，避免摘要与当前数据对不上。
    func clearInsight() {
        insight = nil
        summaryError = nil
    }

    /// 在设备上把当前所选范围的数据读成一句话要点 + 几条亮点。
    func generateInsight(locale: Locale = .current) async {
        guard !isSummarizing, !points.isEmpty else { return }
        isSummarizing = true
        summaryError = nil
        defer { isSummarizing = false }
        // 摘要要提及主要来源，惰性补齐国家维度（Pro 才会走到这里）
        if countries.isEmpty { await loadCountries() }
        do {
            insight = try await AnalyticsAssistant.summarize(makeSummaryInput(), locale: locale)
        } catch {
            summaryError = error.localizedDescription
        }
    }

    /// 从既有聚合值拼出确定性事实集——模型只接触这里的数字。
    private func makeSummaryInput() -> TrafficSummaryInput {
        let top = countries
            .sorted { $0.requests > $1.requests }
            .prefix(5)
            .map { TrafficSummaryInput.TopCountry(name: $0.displayName, requests: $0.requests, threats: $0.threats) }
        return TrafficSummaryInput(
            periodLabel:     selectedRange.periodLabel,
            totalRequests:   totalRequests,
            requestsTrend:   requestsTrend,
            totalBytes:      totalBytes,
            bytesTrend:      bytesTrend,
            totalThreats:    totalThreats,
            threatsTrend:    threatsTrend,
            totalUniques:    totalUniques,
            uniquesTrend:    uniquesTrend,
            cacheHitRate:    cacheHitRate,
            cacheHitTrendPt: cacheHitTrendPt,
            topCountries:    Array(top)
        )
    }
}
