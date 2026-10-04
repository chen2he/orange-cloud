//
//  DNSService.swift
//  Orange Cloud
//

import Foundation

struct DNSService {

    private let client: CFAPIClient

    init(client: CFAPIClient) {
        self.client = client
    }

    /// 拉取 Zone 下全部 DNS 记录（自动翻页）。带 include_shadow_metadata=true：
    /// 被 NS 委派遮蔽的记录在 meta.shadowed_by 里列出遮蔽它的 NS 记录，
    /// NS 委派记录在 meta.shadowed_records_count 里给出遮蔽数。
    func listRecords(zoneId: String) async throws -> [DNSRecord] {
        var records: [DNSRecord] = []
        var page = 1
        while true {
            let response: CFAPIResponseArray<DNSRecord> = try await client.get(
                "zones/\(zoneId)/dns_records",
                queryItems: [
                    URLQueryItem(name: "page",     value: String(page)),
                    URLQueryItem(name: "per_page", value: "100"),
                    URLQueryItem(name: "include_shadow_metadata", value: "true"),
                ]
            )
            guard response.success else {
                throw response.toAPIError()
            }
            records.append(contentsOf: response.result ?? [])
            let totalPages = response.resultInfo?.totalPages ?? 1
            guard page < totalPages else { break }
            page += 1
        }
        return records
    }

    /// 查某主机名的解析记录（服务端按 name 精确过滤，Pages 域名解析检查用）
    func listRecords(zoneId: String, name: String) async throws -> [DNSRecord] {
        let response: CFAPIResponseArray<DNSRecord> = try await client.get(
            "zones/\(zoneId)/dns_records",
            queryItems: [
                URLQueryItem(name: "name",     value: name),
                URLQueryItem(name: "per_page", value: "100"),
            ]
        )
        guard response.success else {
            throw response.toAPIError()
        }
        return response.result ?? []
    }

    /// 仅取记录总数（per_page 最小档 + result_info.total_count，不拉全量记录）
    func recordCount(zoneId: String) async throws -> Int {
        let response: CFAPIResponseArray<DNSRecord> = try await client.get(
            "zones/\(zoneId)/dns_records",
            queryItems: [
                URLQueryItem(name: "page",     value: "1"),
                URLQueryItem(name: "per_page", value: "5"),
            ]
        )
        guard response.success else {
            throw response.toAPIError()
        }
        return response.resultInfo?.totalCount ?? (response.result?.count ?? 0)
    }

    func createRecord(zoneId: String, record: CreateDNSRecord) async throws -> DNSRecord {
        let response: CFAPIResponse<DNSRecord> = try await client.post(
            "zones/\(zoneId)/dns_records",
            body: record
        )
        guard response.success, let result = response.result else {
            throw response.toAPIError()
        }
        return result
    }

    func updateRecord(zoneId: String, recordId: String, record: CreateDNSRecord) async throws -> DNSRecord {
        let response: CFAPIResponse<DNSRecord> = try await client.put(
            "zones/\(zoneId)/dns_records/\(recordId)",
            body: record
        )
        guard response.success, let result = response.result else {
            throw response.toAPIError()
        }
        return result
    }

    func deleteRecord(zoneId: String, recordId: String) async throws {
        try await client.delete("zones/\(zoneId)/dns_records/\(recordId)")
    }
}
