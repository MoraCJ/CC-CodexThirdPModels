import Foundation

enum LogService {
    static func runtimeLogURL(_ name: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/CJLocalProxy/claude-local-proxy/logs",
                isDirectory: true
            )
            .appendingPathComponent(name)
    }

    static func tailFile(_ url: URL, maxCharacters: Int = 12_000) -> String {
        guard FileManager.default.fileExists(atPath: url.path),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return "暂无日志 / No log file yet"
        }
        let tail = content.count > maxCharacters ? String(content.suffix(maxCharacters)) : content
        return redact(tail)
    }

    static func redact(_ input: String) -> String {
        input.replacingOccurrences(
            of: #"(?i)(Authorization:\s*Bearer\s+)[A-Za-z0-9._\-]+"#,
            with: "$1<REDACTED>",
            options: .regularExpression
        )
    }

    static func maskKey(_ key: String) -> String {
        guard key.count > 8 else { return "<REDACTED>" }
        return "\(key.prefix(4))…\(key.suffix(4))"
    }
}
