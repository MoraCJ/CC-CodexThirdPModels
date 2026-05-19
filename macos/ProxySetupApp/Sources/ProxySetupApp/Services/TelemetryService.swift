import Foundation

struct TelemetryBucket: Codable, Equatable, Identifiable {
    var id = UUID()
    var requests: Int
    var failures: Int
    var inputTokens: Int
    var outputTokens: Int
    var totalTokens: Int
    var latencyMsTotal: Int
    var latencyMsAverage: Int

    enum CodingKeys: String, CodingKey {
        case requests
        case failures
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
        case latencyMsTotal = "latency_ms_total"
        case latencyMsAverage = "latency_ms_avg"
    }
}

struct TelemetrySummaryPayload: Codable, Equatable {
    var total: TelemetryBucket
    var byTool: [String: TelemetryBucket]
    var byClient: [String: TelemetryBucket]
    var byModel: [String: TelemetryBucket]

    enum CodingKeys: String, CodingKey {
        case total
        case byTool = "by_tool"
        case byClient = "by_client"
        case byModel = "by_model"
    }
}

struct TelemetrySnapshot: Codable, Equatable {
    var generatedAt: String
    var telemetryFile: String
    var summary: TelemetrySummaryPayload

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case telemetryFile = "telemetry_file"
        case summary
    }
}

struct TelemetryService {
    var runner: CommandRunning = CommandRunner()

    func fetchSummary(config: SetupConfiguration) async throws -> TelemetrySnapshot {
        let url = "https://\(config.listenHost):\(config.listenPort)/telemetry/summary"
        let result = await runner.run("curl", ["-skS", "--max-time", "5", url])
        guard result.exitCode == 0 else {
            throw TelemetryError.fetchFailed(result.stderr)
        }
        guard let data = result.stdout.data(using: .utf8) else {
            throw TelemetryError.invalidJSON
        }
        do {
            return try JSONDecoder().decode(TelemetrySnapshot.self, from: data)
        } catch {
            throw TelemetryError.invalidJSON
        }
    }

    enum TelemetryError: LocalizedError, Equatable {
        case fetchFailed(String)
        case invalidJSON

        var errorDescription: String? {
            switch self {
            case .fetchFailed(let detail):
                return "无法读取 telemetry summary：\(detail.isEmpty ? "curl failed" : detail)"
            case .invalidJSON:
                return "telemetry summary 返回的 JSON 无法解析。"
            }
        }
    }
}
