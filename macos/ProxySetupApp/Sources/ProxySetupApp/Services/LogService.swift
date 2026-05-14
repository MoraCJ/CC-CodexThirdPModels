import Foundation

enum LogService {
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
