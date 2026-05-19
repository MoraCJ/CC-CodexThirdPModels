import Foundation

struct CommandResult: Equatable, Sendable {
    var exitCode: Int32
    var stdout: String
    var stderr: String
    var timedOut: Bool = false
}

protocol CommandRunning: Sendable {
    func run(_ executable: String, _ arguments: [String]) async -> CommandResult
}

protocol TimedCommandRunning: CommandRunning {
    func run(_ executable: String, _ arguments: [String], timeoutSeconds: TimeInterval?) async -> CommandResult
}

struct CommandRunner: CommandRunning {
    func run(_ executable: String, _ arguments: [String]) async -> CommandResult {
        await run(executable, arguments, timeoutSeconds: nil)
    }
}

extension CommandRunner: TimedCommandRunning {
    func run(_ executable: String, _ arguments: [String], timeoutSeconds: TimeInterval?) async -> CommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(
                    returning: runProcess(
                        executable,
                        arguments,
                        timeoutSeconds: timeoutSeconds
                    )
                )
            }
        }
    }
}

private func runProcess(
    _ executable: String,
    _ arguments: [String],
    timeoutSeconds: TimeInterval?
) -> CommandResult {
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

            let semaphore = DispatchSemaphore(value: 0)
            DispatchQueue.global(qos: .utility).async {
                process.waitUntilExit()
                semaphore.signal()
            }

            if let timeoutSeconds, timeoutSeconds > 0 {
                let waitResult = semaphore.wait(timeout: .now() + timeoutSeconds)
                if waitResult == .timedOut {
                    process.terminate()
                    _ = semaphore.wait(timeout: .now() + 2)
                    let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let message = "command timed out after \(String(format: "%.1f", timeoutSeconds))s"
                    return CommandResult(
                        exitCode: 124,
                        stdout: out,
                        stderr: err.isEmpty ? message : "\(err)\n\(message)",
                        timedOut: true
                    )
                }
            } else {
                semaphore.wait()
            }

            let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return CommandResult(exitCode: process.terminationStatus, stdout: out, stderr: err)
        } catch {
            return CommandResult(exitCode: 127, stdout: "", stderr: String(describing: error))
        }
}

struct MockCommandRunner: CommandRunning {
    var outputs: [String: CommandResult]

    func run(_ executable: String, _ arguments: [String]) async -> CommandResult {
        let key = ([executable] + arguments).joined(separator: " ")
        return outputs[key] ?? CommandResult(exitCode: 127, stdout: "", stderr: "missing mock for \(key)")
    }
}
