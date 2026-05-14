import Foundation

struct CommandResult: Equatable, Sendable {
    var exitCode: Int32
    var stdout: String
    var stderr: String
}

protocol CommandRunning: Sendable {
    func run(_ executable: String, _ arguments: [String]) async -> CommandResult
}

struct CommandRunner: CommandRunning {
    func run(_ executable: String, _ arguments: [String]) async -> CommandResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        if executable == "command" {
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", ([executable] + arguments).joined(separator: " ")]
        } else if executable.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable] + arguments
        }

        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
            let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return CommandResult(exitCode: process.terminationStatus, stdout: out, stderr: err)
        } catch {
            return CommandResult(exitCode: 127, stdout: "", stderr: String(describing: error))
        }
    }
}

struct MockCommandRunner: CommandRunning {
    var outputs: [String: CommandResult]

    func run(_ executable: String, _ arguments: [String]) async -> CommandResult {
        let key = ([executable] + arguments).joined(separator: " ")
        return outputs[key] ?? CommandResult(exitCode: 127, stdout: "", stderr: "missing mock for \(key)")
    }
}
