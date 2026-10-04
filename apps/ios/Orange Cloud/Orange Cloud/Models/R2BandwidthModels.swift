//
//  R2BandwidthModels.swift
//  Orange Cloud
//
//  R2 带宽（近 30 天上传 / 下载）：GraphQL r2BandwidthUsageAdaptiveGroups（account-analytics.read）。
//  单次查询最长 31 天；小于 100 KiB 的传输不计入（UI 加脚注）。
//  按桶过滤用 bucketName：区域限制桶带辖区下划线前缀（eu_xxx / us_xxx），见 R2Bucket.analyticsBucketName。
//

import Foundation

nonisolated struct R2Bandwidth: Sendable, Hashable {
    var uploadBytes = 0
    var downloadBytes = 0
}

nonisolated enum R2BandwidthQuery {

    static let account = """
    query ($accountTag: string!, $since: Time!, $until: Time!) {
      viewer {
        accounts(filter: { accountTag: $accountTag }) {
          bandwidth: r2BandwidthUsageAdaptiveGroups(
            limit: 100,
            filter: { datetime_geq: $since, datetime_lt: $until }
          ) {
            sum { bytesUpload bytesDownload }
            dimensions { date }
          }
        }
      }
    }
    """

    static let bucket = """
    query ($accountTag: string!, $since: Time!, $until: Time!, $bucketName: string!) {
      viewer {
        accounts(filter: { accountTag: $accountTag }) {
          bandwidth: r2BandwidthUsageAdaptiveGroups(
            limit: 100,
            filter: { datetime_geq: $since, datetime_lt: $until, bucketName: $bucketName }
          ) {
            sum { bytesUpload bytesDownload }
            dimensions { date }
          }
        }
      }
    }
    """
}

nonisolated struct R2BandwidthVariables: Codable, Sendable {
    let accountTag: String
    let since:      String
    let until:      String
    let bucketName: String?   // nil 时编码器省略（账号级查询不声明该变量）
}

nonisolated struct R2BandwidthData: Codable, Sendable {
    let viewer: Viewer
    nonisolated struct Viewer: Codable, Sendable { let accounts: [Account] }
    nonisolated struct Account: Codable, Sendable { let bandwidth: [Group]? }
    nonisolated struct Group: Codable, Sendable { let sum: Sum? }
    nonisolated struct Sum: Codable, Sendable {
        let bytesUpload:   Int?
        let bytesDownload: Int?
    }
}
