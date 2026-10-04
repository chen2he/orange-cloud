//
//  PrecursorService.swift
//  Orange Cloud
//
//  会话级机器人检测（Precursor，precursor.read / .write）。字段说明见 PrecursorModels。
//

import Foundation

struct PrecursorService {

    private let client: CFAPIClient

    init(client: CFAPIClient) {
        self.client = client
    }

    func config(zoneId: String) async throws -> PrecursorConfig {
        let response: CFAPIResponse<PrecursorConfig> = try await client.get("zones/\(zoneId)/precursor")
        guard response.success, let result = response.result else {
            throw response.toAPIError()
        }
        return result
    }

    /// 只改默认模式（部分更新），返回生效后的配置
    func setMode(zoneId: String, mode: PrecursorMode) async throws -> PrecursorConfig {
        let response: CFAPIResponse<PrecursorConfig> = try await client.put(
            "zones/\(zoneId)/precursor",
            body: PrecursorModeUpdate(defaultMode: mode.rawValue)
        )
        guard response.success else {
            throw response.toAPIError()
        }
        // 响应体形态未定时以请求值兜底
        return response.result ?? PrecursorConfig(defaultMode: mode.rawValue)
    }
}
