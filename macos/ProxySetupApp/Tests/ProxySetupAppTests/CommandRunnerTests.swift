import Foundation
import Testing
@testable import ProxySetupApp

struct CommandRunnerTests {
    @Test
    func timeoutTerminatesLongRunningProcess() async {
        let result = await CommandRunner().run(
            "/bin/sh",
            ["-c", "sleep 2"],
            timeoutSeconds: 0.1
        )

        #expect(result.timedOut)
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("timed out"))
    }
}
