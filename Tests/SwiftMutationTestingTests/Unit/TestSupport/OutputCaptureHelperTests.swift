import Foundation
import Testing

/// Serialized because every test here redirects the process-wide stdout/stderr descriptors: two of
/// these tests running at once would capture each other's output, and the test runner's own progress
/// messages along with it.
extension OutputCaptureSerializedTests {
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
                // `captureOutputSync` blocks its calling thread outright (see `OutputCaptureGate`'s
                // documentation), so running it directly in this `async let` child task would block a
                // cooperative-pool thread while `asyncOutput`'s block is suspended holding the gate.
                // Dispatching it to a non-cooperative queue keeps this test off that thread.
                async let syncOutput: String = withCheckedContinuation {
                    (continuation: CheckedContinuation<String, Never>) in
                    DispatchQueue.global().async {
                        continuation.resume(
                            returning: captureOutputSync {
                                Thread.sleep(forTimeInterval: 0.005)
                                print("SYNC-ONLY")
                            }
                        )
                    }
                }

                let (resolvedAsyncOutput, resolvedSyncOutput) = await (asyncOutput, syncOutput)

                #expect(resolvedAsyncOutput == "ASYNC-START-ASYNC-END\n")
                #expect(resolvedSyncOutput == "SYNC-ONLY\n")
            }
        }

        @Test(
            "Given a capture whose block suspends mid-block, when it finishes, then the capture gate is released"
        )
        func captureReleasesItsGateWhenTheBlockResumesOnAnotherThread() async {
            // `Task.sleep` gives no guarantee that its continuation resumes on a different OS thread,
            // so this can't assert an actual thread hop happened without flaking. What it can assert
            // deterministically: the gate the block suspended while holding gets released regardless
            // of which thread does the releasing — `OutputCaptureGate.release()` documents itself as
            // safe from any thread, and a capture taken afterwards only succeeds if that held.
            for iteration in 0 ..< 20 {
                let output = await captureOutput {
                    print("HOP-\(iteration)", terminator: "")
                    try? await Task.sleep(nanoseconds: 5_000_000)
                    print("-RESUMED")
                }

                #expect(output == "HOP-\(iteration)-RESUMED\n")
            }

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
}
