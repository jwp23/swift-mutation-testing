import Foundation

struct XcodeProcessLauncher: Sendable, RunnerBackedProcessLaunching {
    func makeRunner() -> ProcessRunner {
        ProcessRunner(
            onTimeout: { pid in
                guard pid > 0 else { return }
                kill(-pid, SIGTERM)
                Task {
                    try? await Task.sleep(for: .seconds(5))
                    kill(-pid, SIGKILL)
                }
            }
        )
    }
}
