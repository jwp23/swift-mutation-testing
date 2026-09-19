# Reporting & Infrastructure

← [Result Parsing & Cache](08-result-parsing-cache.md) | [Index →](README.md)

---

## Reporting/ProgressReporter.swift

```swift
protocol ProgressReporter: Sendable {
    func report(_ event: RunnerEvent) async
}
```

Adopted by `ConsoleProgressReporter` and `SilentProgressReporter`. The async requirement allows actor-isolated implementations without `nonisolated` boilerplate.

---

## Reporting/ConsoleProgressReporter.swift

```swift
actor ConsoleProgressReporter: ProgressReporter {
    func report(_ event: RunnerEvent) async
}
```

Serialises progress output to stdout. Each `RunnerEvent` case maps to a formatted `print` call. `.mutantStarted`, `.fallbackBuildStarted`, and `.fallbackBuildFinished` are no-ops (no output).

**Output per event:**

| Event | Output |
|---|---|
| `.discoveryFinished` | `✓ Discovery: N mutants (M schematizable[, K incompatible]) in X.Xs` |
| `.loadedFromCache` | `✓ Loaded N mutants from cache` |
| `.buildStarted` | blank line + `Building for testing...` |
| `.buildFinished` | `✓ Built in X.Xs` |
| `.simulatorPoolReady` | `✓ N simulators ready` + blank line + `Testing mutants...` |
| `.mutantFinished` | `<icon> <index>/<total>  <operator>  <filename>:<line>` |

Progress icon is provided by `ExecutionStatus.progressIcon`.

---

## Reporting/SilentProgressReporter.swift

```swift
struct SilentProgressReporter: Sendable, ProgressReporter {
    func report(_ event: RunnerEvent) async {}
}
```

No-op reporter. Used when `--quiet` is active.

---

## Reporting/RunnerEvent.swift

```swift
enum RunnerEvent: Sendable {
    case discoveryFinished(mutantCount: Int, schematizableCount: Int, incompatibleCount: Int, duration: Double)
    case loadedFromCache(mutantCount: Int)
    case buildStarted
    case buildFinished(duration: Double)
    case simulatorPoolReady(size: Int)
    case mutantStarted(descriptor: MutantDescriptor, index: Int, total: Int)
    case mutantFinished(descriptor: MutantDescriptor, status: ExecutionStatus, index: Int, total: Int)
    case fallbackBuildStarted(filePath: String)
    case fallbackBuildFinished(filePath: String, success: Bool)
}
```

Lifecycle events emitted by `MutantExecutor` and its stages to the `ProgressReporter`.

---

## Reporting/RunnerSummary.swift

```swift
struct RunnerSummary: Sendable {
    let results: [ExecutionResult]
    let totalDuration: Double

    var killed: [ExecutionResult]
    var survived: [ExecutionResult]
    var unviable: [ExecutionResult]
    var timeouts: [ExecutionResult]
    var noCoverage: [ExecutionResult]
    var score: Double
    var resultsByFile: [String: [ExecutionResult]]
}
```

Aggregates all `ExecutionResult` values and computes the mutation score.

**Score formula:**

```
score = killed / (killed + survived + timeouts + noCoverage) × 100
```

`unviable` mutants are excluded from the denominator. When `denominator == 0` the score is `100.0`.

`resultsByFile` groups results by `descriptor.filePath`, used by all reporters to produce per-file breakdowns.

---

## Reporting/TextReporter.swift

```swift
struct TextReporter: Sendable {
    init(projectRoot: String = "")
    func report(_ summary: RunnerSummary)
    func format(_ summary: RunnerSummary) -> String
}
```

Prints a human-readable summary to stdout. Always active (not gated by a CLI flag).

Output sections:
1. Per-file table: relative path, score %, killed/survived/timeout/unviable counts
2. Survived mutants list: `<file>:<line>:<col>  <operator>` sorted by file then line
3. Overall score line
4. Total killed / survived / timeouts / unviable / noCoverage counts
5. Total duration

`format(_:)` is exposed separately for testing.

---

## Reporting/JsonReporter.swift

```swift
struct JsonReporter: Sendable {
    let outputPath: String
    let projectRoot: String
    func report(_ summary: RunnerSummary) throws
}
```

Writes a Stryker-compatible JSON report to `outputPath`. Encodes a `MutationReportPayload` with `JSONEncoder` (pretty-printed, sorted keys).

Fixed thresholds: `high = 80`, `low = 60`.

---

## Reporting/HtmlReporter.swift

```swift
struct HtmlReporter: Sendable {
    let outputPath: String
    let projectRoot: String
    func report(_ summary: RunnerSummary) throws
}
```

Writes a self-contained HTML dashboard to `outputPath`. Includes a per-file score table with `<details>` elements listing survived mutants inline. Score cells are colour-coded: green (100%), yellow (≥ 50%), red (< 50%).

---

## Reporting/SonarReporter.swift

```swift
struct SonarReporter: Sendable {
    let outputPath: String
    let projectRoot: String
    func report(_ summary: RunnerSummary) throws
}
```

Writes a SonarQube Generic Issue Import Format JSON file to `outputPath`. Reports survived mutants as `MAJOR` issues and `noCoverage` mutants as `MINOR` issues.

`engineId` is always `"swift-mutation-testing"`. `ruleId` is the operator identifier. `type` is `"CODE_SMELL"`.

---

## ExecutionStatus Extensions

### Reporting/ExecutionStatus+MutationReportStatus.swift

```swift
extension ExecutionStatus {
    var mutationReportStatus: String
}
```

Maps `ExecutionStatus` to the string value used in `MutationReportMutant.status`.

| Case | String |
|---|---|
| `.killed` | `"Killed"` |
| `.killedByCrash` | `"Crash"` |
| `.survived` | `"Survived"` |
| `.unviable` | `"Unviable"` |
| `.timeout` | `"Timeout"` |
| `.noCoverage` | `"NoCoverage"` |

---

### Reporting/ExecutionStatus+ProgressIcon.swift

```swift
extension ExecutionStatus {
    var progressIcon: String
}
```

Single-character icon displayed by `ConsoleProgressReporter` for each finished mutant.

| Case | Icon |
|---|---|
| `.killed`, `.killedByCrash` | `✓` |
| `.survived` | `✗` |
| `.unviable` | `⚠` |
| `.timeout` | `⏱` |
| `.noCoverage` | `–` |

---

## MutationReport Types

### Reporting/MutationReport/MutationReportPayload.swift

```swift
struct MutationReportPayload: Sendable, Encodable {
    let schemaVersion: String
    let thresholds: MutationReportThresholds
    let projectRoot: String
    let files: [String: MutationReportFile]
}
```

Root JSON object for the Stryker report format. `schemaVersion` is always `"1"`.

---

### Reporting/MutationReport/MutationReportFile.swift

```swift
struct MutationReportFile: Sendable, Encodable {
    let language: String
    let source: String
    let mutants: [MutationReportMutant]
}
```

`language` is always `"swift"`. `source` is the full source file content at report time.

---

### Reporting/MutationReport/MutationReportMutant.swift

```swift
struct MutationReportMutant: Sendable, Encodable {
    let id: String
    let mutatorName: String
    let originalText: String
    let replacement: String
    let location: MutationReportLocation
    let status: String
    let description: String
    let killedBy: String?
}
```

`killedBy` is populated only for `.killed(by:)` status.

---

### Reporting/MutationReport/MutationReportLocation.swift

```swift
struct MutationReportLocation: Sendable, Encodable {
    let start: MutationReportPosition
    let end: MutationReportPosition
}
```

`end.column` is computed as `start.column + originalText.count`.

---

### Reporting/MutationReport/MutationReportPosition.swift

```swift
struct MutationReportPosition: Sendable, Encodable {
    let line: Int
    let column: Int
}
```

---

### Reporting/MutationReport/MutationReportThresholds.swift

```swift
struct MutationReportThresholds: Sendable, Encodable {
    let high: Int
    let low: Int
}
```

Fixed values: `high = 80`, `low = 60`.

---

## Sonar Types

### Reporting/Sonar/SonarPayload.swift

```swift
struct SonarPayload: Sendable, Encodable {
    let issues: [SonarIssue]
}
```

Root JSON object for the SonarQube Generic Issue Import format.

---

### Reporting/Sonar/SonarIssue.swift

```swift
struct SonarIssue: Sendable, Encodable {
    let engineId: String
    let ruleId: String
    let severity: String
    let type: String
    let primaryLocation: SonarLocation
}
```

| Field | Value |
|---|---|
| `engineId` | `"swift-mutation-testing"` |
| `ruleId` | Operator identifier |
| `severity` | `"MAJOR"` (survived) or `"MINOR"` (noCoverage) |
| `type` | `"CODE_SMELL"` |

---

### Reporting/Sonar/SonarLocation.swift

```swift
struct SonarLocation: Sendable, Encodable {
    let message: String
    let filePath: String
    let textRange: SonarRange
}
```

`message` is `"[<operatorIdentifier>] <description>"`. `filePath` is relative to `projectRoot`.

---

### Reporting/Sonar/SonarRange.swift

```swift
struct SonarRange: Sendable, Encodable {
    let startLine: Int
    let endLine: Int
    let startColumn: Int
    let endColumn: Int
}
```

`endColumn` is `startColumn + originalText.count`. `startLine == endLine` (single-line range).

---

## Infrastructure/ProcessLaunching.swift

```swift
protocol ProcessLaunching: Sendable {
    func launch(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> Int32

    func launchCapturing(
        _ request: ProcessRequest
    ) async throws -> (exitCode: Int32, output: String)

    func launchStreaming(
        _ request: ProcessRequest,
        stopWhen: @escaping @Sendable (String) -> Bool
    ) async throws -> StreamedProcessResult
}
```

Abstraction over process execution. `launch` discards output (stdout/stderr → `/dev/null`). `launchCapturing` accepts a `ProcessRequest` value, captures combined stdout+stderr, and returns it as a `String`.

`launchStreaming` reads the output as it is produced, offers every completed line to `stopWhen`,
and kills the process tree at the first line accepted — the fail-fast path `TestExecutionStage`
uses to stop a mutant's test run at its first failing test. It returns a `StreamedProcessResult`
(`exitCode`, `output`, `stoppedEarly`); a launcher with no streaming of its own inherits a default
implementation that runs the process to completion, offers no line, and reports
`stoppedEarly: false`.

Return value `-1` from `launch`/`launchCapturing` means the process was killed by the timeout
handler or by task cancellation — both paths mark the same `killedByUs` flag before killing the
process tree. A `stoppedEarly` result instead carries the signal-derived status of the process the
runner killed, which is why callers classify it from `output` rather than from `exitCode`.

`RunnerBackedProcessLaunching: ProcessLaunching` (same file) is a protocol for conformers backed
by a `ProcessRunner`: it requires only `func makeRunner() -> ProcessRunner` and supplies
`launch`/`launchCapturing`/`launchStreaming` as a default extension forwarding to `makeRunner()`.
Both `SPMProcessLauncher` and `XcodeProcessLauncher` conform to it instead of duplicating the
forwarding methods.

---

## Infrastructure/ProcessRequest.swift

```swift
struct ProcessRequest: Sendable {
    let executableURL: URL
    let arguments: [String]
    let environment: [String: String]?
    let additionalEnvironment: [String: String]
    let workingDirectoryURL: URL
    let timeout: Double
}
```

| Field | Description |
|---|---|
| `executableURL` | Path to the executable |
| `arguments` | Command-line arguments |
| `environment` | Full environment override (replaces inherited environment when non-nil) |
| `additionalEnvironment` | Key-value pairs merged into the existing environment |
| `workingDirectoryURL` | Working directory for the process |
| `timeout` | Maximum execution time in seconds |

---

## Infrastructure/StreamedProcessResult.swift

```swift
struct StreamedProcessResult: Sendable {
    let exitCode: Int32
    let output: String
    let stoppedEarly: Bool
}
```

Result of a `launchStreaming` call. `stoppedEarly` marks a run the launcher itself killed because
a line matched the caller's stop condition; that process died from the signal that stopped it, so
`exitCode` reports the signal rather than any verdict and the caller must read the verdict from
`output` — which always contains the line the stop was decided on.

---

## Infrastructure/OutputLineBuffer.swift

```swift
final class OutputLineBuffer: @unchecked Sendable {
    var output: String
    func append(_ chunk: Data) -> [String]
}
```

Accumulates a streamed process's output and returns each line once it is complete, holding a
trailing partial line back until a later chunk finishes it. Lines are split on the raw bytes, not
on decoded text, because a read can end in the middle of a multi-byte character. `NSLock`-guarded:
Foundation runs the pipe's readability handler on its own queue.

---

## Infrastructure/ProcessRunner.swift

```swift
struct ProcessRunner: Sendable {
    var postTerminationCleanup: (@Sendable (Int32) -> Void)?
    let killProcessTree: @Sendable (Int32) -> Void

    func launch(executableURL:arguments:workingDirectoryURL:timeout:) async throws -> Int32
    func launchCapturing(_ request: ProcessRequest) async throws -> (exitCode: Int32, output: String)
    func launchStreaming(_ request: ProcessRequest, stopWhen: @escaping @Sendable (String) -> Bool)
        async throws -> StreamedProcessResult
}
```

Low-level process execution engine. Uses `withTaskCancellationHandler` + `withCheckedThrowingContinuation` to bridge `Process.terminationHandler` into the Swift Concurrency runtime.

**Timeout handling:** a `Task` sleeping for `timeout` seconds marks a `OneWayFlag` and calls `killProcessTree(pid)`. The `terminationHandler` checks the flag and returns `-1` instead of the actual exit code.

**Cancellation handling:** `onCancel` marks the flag and calls `killProcessTree(pid)` immediately, ensuring the continuation is always resumed via the `terminationHandler`.

**Post-termination cleanup:** `postTerminationCleanup` is called after every process termination (success or failure); `SPMProcessLauncher` uses it to `SIGKILL` the process group.

`launchCapturing` writes output to a temporary file (UUID-named) and reads it in the `terminationHandler` to avoid pipe buffer limits. Sets process group via `setpgid(pid, pid)` to enable group signaling.

**Streaming:** `launchStreaming` reads through a `Pipe` instead, accumulating bytes in an
`OutputLineBuffer` and offering each completed line to `stopWhen`. The first accepted line marks a
second `OneWayFlag` and calls the same `killProcessTree(pid)` the timeout uses — there is no
separate kill path. The launch normally resumes once the process has exited *and* the pipe has
reached end of file, since output can still arrive after the termination handler runs.

End of file is not guaranteed. A descendant that left the process group *before* the root exited
keeps the write end open and is beyond every signal that remains: the group signal never covered
it, and once the root has been reaped the parent-pid walk `killProcessTree` depends on can no
longer find it (its survivors have been reparented). What bounds the launch is therefore not the
timeout — which is cancelled when the process exits, as on the other two paths — but
`ProcessRunner.outputGracePeriod` (5 s): once the process has exited, output still arriving has
that long to finish, and the launch then returns with what it read. Partial output a caller can
still reach a verdict from beats a launch that never returns.

---

## Infrastructure/SPMProcessLauncher.swift

```swift
struct SPMProcessLauncher: Sendable, RunnerBackedProcessLaunching {
    func makeRunner() -> ProcessRunner
}
```

SPM-specific implementation of `ProcessLaunching`, via the `RunnerBackedProcessLaunching`
protocol (`launch`/`launchCapturing` come from that protocol's default extension —
`XcodeProcessLauncher` conforms the same way). `makeRunner()` configures a `ProcessRunner` with:
- `postTerminationCleanup`: kills the process group via `kill(-pid, SIGKILL)`
- `killProcessTree`: freezes and snapshots the launched process's descendants via
  `frozenDescendantPIDs(of:)` *before* sending `SIGTERM`, then after a five-second grace period
  sends `kill(-pid, SIGKILL)` and kills that snapshot via `killDescendants(_:)`

**`frozenDescendantPIDs(of rootPID:)`** — `SIGSTOP`s the root's process group, then repeatedly
walks the descendants and `SIGSTOP`s each newly discovered pid (an already-escaped descendant is
outside the root's group, so the group stop does not reach it) until a walk finds nothing new,
bounded at five rounds. Returns the descendants enumerated while the tree is frozen. A stopped
process cannot fork, so nothing can appear behind the walk and land in neither the snapshot nor
the root's process group. The tree is left stopped: `SIGTERM` still terminates a stopped process
that does not handle it and `SIGKILL` terminates one that does, whereas resuming it would let an
escaped descendant — which the root group's `SIGTERM` never reaches — go on forking children the
snapshot does not name for the whole grace period. Residual race: a fork the kernel has already
accepted when `SIGSTOP` lands still completes; ordinary POSIX signals offer no atomic
process-group freeze.

**`descendantPIDs(of rootPID:)`** — walks `kinfo_proc` (via `sysctl` `KERN_PROC_ALL`) once,
builds a `parentPID -> [childPID]` map from each process's `kp_eproc.e_ppid`, and returns the
transitive descendants of `rootPID`. Must be called while `rootPID` is still alive: once it
exits and is reaped, any surviving descendant is reparented to launchd (ppid 1), severing the
ancestry chain — which is why the snapshot is taken before `SIGTERM`, not in
`postTerminationCleanup` after the process has already exited. Callers acting on a live root use
`frozenDescendantPIDs(of:)` rather than calling this directly, so the walk cannot be outrun.

**`killDescendants(_ snapshots:)`** — takes descendant snapshots (pid plus the kernel start time
recorded for it), not bare pids. Sends `SIGKILL` to each pid (and the process group it leads),
but only after re-reading the current start time for that pid and confirming it still matches
the snapshot; a mismatch means the pid has been reused by an unrelated process since discovery,
so that pid is skipped rather than signaled. Used on a snapshot from `frozenDescendantPIDs(of:)`
to catch descendants that escaped the launched process's own process group (e.g. via `setsid`),
which `kill(-pid, SIGKILL)` on the root's group does not reach.

---

## Infrastructure/XCTestRunPlist.swift

```swift
struct XCTestRunPlist: Sendable, Equatable {
    init?(_ data: Data)
    func activating(_ mutantID: String) -> Data
}
```

Wraps the raw plist `Data` from the `.xctestrun` file.

`activating(_:)` injects `mutantID` into `EnvironmentVariables.__SWIFT_MUTATION_TESTING_ACTIVE` for every test target in the plist. Handles both the `TestConfigurations` format (Xcode 15+) and the legacy flat dictionary format. Returns a fresh XML plist `Data` — the original is not mutated.

---

## Infrastructure/PathRelativizer.swift

```swift
enum PathRelativizer {
    static func relativePath(for path: String, relativeTo root: String) -> String
}
```

Resolves `path` relative to `root`, symlink-resolving both first so callers get a consistent, comparable path shape — used as cache/metadata dictionary keys by `CacheStore` and `TestFilesHasher`. Returns `path` unchanged if it doesn't fall under `root` (e.g. a symlinked test file pointing outside the project root).

---

## Infrastructure/TestFilesHasher.swift

```swift
struct TestFilesHasher: Sendable {
    func hashPerFile(projectPath: String) -> [String: String]
    func testFilePaths(projectPath: String) -> [String]
}
```

Provides per-file test hashing and test file path enumeration for granular cache invalidation.

| Method | Description |
|---|---|
| `hashPerFile(projectPath:)` | Returns a dictionary mapping relative test file paths to their SHA256 content hashes. Symlinks pointing outside the project root use absolute paths as keys to avoid collisions |
| `testFilePaths(projectPath:)` | Returns all test file paths in the project, as absolute filesystem paths (unlike `hashPerFile`'s relativized keys) |

**Test file collection:** walks `projectPath` recursively (skipping hidden files) and includes every `.swift` file `TestFileConvention.isTestFile(path:)` recognises — the same rule discovery excludes by, so the set hashed here is exactly the set that carries no mutants.

---

## Infrastructure/TestFileConvention.swift

```swift
enum TestFileConvention {
    static func isTestFile(path: String) -> Bool
    static func declaresTests(path: String) -> Bool
}
```

Whether a Swift file belongs to a project's tests rather than its mutable source: the tests themselves and the doubles that support them, recognised from the path alone. The single answer to that question — `SourceFileExclusion` skips these files during discovery so they carry no mutants, and `TestFilesHasher` hashes exactly the same set for cache invalidation.

**Patterns:** test cases are `Tests.swift` and `Spec.swift` (suffix); doubles and shared helpers are `Mock.swift` (suffix) and `/Mocks/`, `/Stubs/`, `/Fakes/`, `/TestHelpers/`, `/TestSupport/` (anywhere in the path). `isTestFile(path:)` matches either group or the test-directory heuristic below.

`declaresTests(path:)` is the narrower question `KillerTestFileResolver` asks: of the files that belong to the tests, which can hold a test at all. It is `isTestFile(path:)` minus the doubles and shared helpers — those declare no test, so naming one as a mutant's `killerTestFile` on a coincidental text match would leave the cache watching a file that can never change the verdict. `Spec.swift` stays eligible: a Quick-style spec declares tests.

**Test-directory heuristic:** a path is a test path if any directory it passes through is a test target by convention — named exactly `Tests`, or a project's own name followed by it, such as `AppTests` or `ProjectTests`. A component ending in `Tests` doesn't count if an earlier (closer-to-root) component is literally `Sources`, which marks a source-code feature directory that happens to end in "Tests" (`Sources/ABTests/`, `Sources/Analytics/ExperimentTests/`) rather than a test target; a component that is exactly `Tests` always counts regardless of a `Sources` ancestor, though that combination shouldn't arise in practice. This is a path-based heuristic with no real target list to check against — a project checked out under a directory that happens to be named `Sources` for unrelated reasons could still be misclassified, an accepted tradeoff. Note the tradeoff's scope: because `TestFilesHasher` walks absolute paths, a checkout under a directory literally named `Sources` (`/Users/me/Sources/Proj/ProjTests/Helper.swift`) drops those files from `testFileHashes` and from killer-test resolution as well as from discovery — editing such a test would not invalidate its cached results.

Build output is deliberately not covered here: skipping `.build/` or derived data is about where discovery may walk, not about what a test file is, so those patterns stay in `SourceFileExclusion`.

---

← [Result Parsing & Cache](08-result-parsing-cache.md) | [Index →](README.md)
