import Foundation
import Testing

/// Serialized because every test here redirects the process-wide stdout/stderr descriptors: two of
/// these tests running at once would capture each other's output, and the test runner's own progress
/// messages along with it.
@Suite("OutputCaptureHelper", .serialized)
struct OutputCaptureHelperTests {
    @Test(
        "Given overlapping async and sync captures, when run concurrently, then each capture keeps only its own output"
    )
    func overlappingCapturesDoNotCorruptEachOther() async {
        for _ in 0 ..< 20 {
            async let asyncOutput = captureOutput {
                print("ASYNC-START", terminator: "")
                try? await Task.sleep(nanoseconds: 5_000_000)
                print("-ASYNC-END")
            }
            async let syncOutput: String = {
                captureOutputSync {
                    Thread.sleep(forTimeInterval: 0.005)
                    print("SYNC-ONLY")
                }
            }()

            let (resolvedAsyncOutput, resolvedSyncOutput) = await (asyncOutput, syncOutput)

            #expect(resolvedAsyncOutput == "ASYNC-START-ASYNC-END\n")
            #expect(resolvedSyncOutput == "SYNC-ONLY\n")
        }
    }

    /// Carries the thread identity observed on either side of the awaited block's suspension point.
    /// The block runs to completion before the test reads it back, so the unsynchronized access is safe.
    private final class ThreadIdentityProbe: @unchecked Sendable {
        var threadBeforeSuspension: UInt64 = 0
        var threadAfterSuspension: UInt64 = 0
    }

    private static func currentThreadID() -> UInt64 {
        var identifier: UInt64 = 0
        pthread_threadid_np(nil, &identifier)
        return identifier
    }

    @Test(
        "Given a capture whose block resumes on a different thread, when it finishes, then the capture gate is released"
    )
    func captureReleasesItsGateWhenTheBlockResumesOnAnotherThread() async {
        var suspensionsThatChangedThread = 0

        for iteration in 0 ..< 20 {
            let probe = ThreadIdentityProbe()

            let output = await captureOutput {
                probe.threadBeforeSuspension = Self.currentThreadID()
                print("HOP-\(iteration)", terminator: "")
                try? await Task.sleep(nanoseconds: 5_000_000)
                print("-RESUMED")
                probe.threadAfterSuspension = Self.currentThreadID()
            }

            #expect(output == "HOP-\(iteration)-RESUMED\n")
            if probe.threadBeforeSuspension != probe.threadAfterSuspension {
                suspensionsThatChangedThread += 1
            }
        }

        // The capture gate is acquired before the block and released after it, so a block that
        // resumes on another thread releases the gate from a thread that never acquired it. Without
        // observing at least one such hop the test would pass vacuously, never exercising the case.
        #expect(
            suspensionsThatChangedThread > 0,
            "No iteration resumed on a different thread, so cross-thread release was never exercised"
        )

        // A capture taken afterwards proves the gate was genuinely released, not merely un-owned.
        let subsequentOutput = await captureOutput { print("AFTER") }
        #expect(subsequentOutput == "AFTER\n")
    }

    /// Records the wall-clock window during which each capture's block actually ran, so the test
    /// can assert those windows never overlap — the direct, observable consequence of `captureOutput`
    /// and `captureStandardError` sharing one gate rather than each holding its own.
    private actor ExecutionWindowRecorder {
        private(set) var windows: [(label: String, start: Date, end: Date)] = []

        func record(_ label: String, start: Date, end: Date) {
            windows.append((label, start, end))
        }
    }

    @Test(
        "Given overlapping stdout and stderr captures, when run concurrently, then each capture keeps only its output"
    )
    func overlappingStdoutAndStderrCapturesDoNotCorruptEachOther() async throws {
        for _ in 0 ..< 20 {
            let recorder = ExecutionWindowRecorder()

            async let stdoutOutput = captureOutput {
                let start = Date()
                print("STDOUT-START", terminator: "")
                try? await Task.sleep(nanoseconds: 20_000_000)
                print("-STDOUT-END")
                await recorder.record("stdout", start: start, end: Date())
            }
            async let stderrOutput = captureStandardError {
                let start = Date()
                FileHandle.standardError.write(Data("STDERR-START".utf8))
                try? await Task.sleep(nanoseconds: 20_000_000)
                FileHandle.standardError.write(Data("-STDERR-END\n".utf8))
                await recorder.record("stderr", start: start, end: Date())
            }

            let (resolvedStdoutOutput, resolvedStderrOutput) = try await (stdoutOutput, stderrOutput)

            #expect(resolvedStdoutOutput == "STDOUT-START-STDOUT-END\n")
            #expect(resolvedStderrOutput == "STDERR-START-STDERR-END\n")

            let windows = await recorder.windows.sorted { $0.start < $1.start }
            #expect(windows.count == 2)
            #expect(
                windows[0].end <= windows[1].start,
                Comment(
                    rawValue: "captureOutput and captureStandardError ran their blocks concurrently instead of "
                        + "serializing on the shared capture gate"
                )
            )
        }
    }
}
