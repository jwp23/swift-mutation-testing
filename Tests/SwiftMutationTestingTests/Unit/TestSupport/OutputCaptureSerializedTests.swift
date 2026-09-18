import Testing

/// Shared serialization umbrella for every suite that uses `OutputCaptureHelper`'s
/// `captureOutput`/`captureOutputSync`/`captureStandardError` helpers.
///
/// Those helpers redirect the process-global `STDOUT_FILENO`/`STDERR_FILENO` descriptors.
/// Swift Testing's `.serialized` trait only prevents a suite's own tests from running
/// concurrently with each other — it does not prevent two independently `.serialized` suites
/// from interleaving with each other under the default parallel scheduler. Nesting every
/// capture-using suite as a member of this single `.serialized` parent extends that guarantee
/// across all of them, so no two capture-using tests anywhere in the project can run at once.
@Suite("Tests using OutputCaptureHelper", .serialized)
enum OutputCaptureSerializedTests {}
