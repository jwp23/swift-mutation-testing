/// Outcome of a launch whose output was read as it was produced.
///
/// `stoppedEarly` marks a run the launcher itself terminated because a line matched the caller's
/// stop condition. Such a run dies from the signal that stopped it, so its `exitCode` reports that
/// signal rather than any verdict the program reached — a caller must read the verdict from
/// `output`, which always contains the line the stop was decided on.
struct StreamedProcessResult: Sendable {
    let exitCode: Int32
    let output: String
    let stoppedEarly: Bool
}
