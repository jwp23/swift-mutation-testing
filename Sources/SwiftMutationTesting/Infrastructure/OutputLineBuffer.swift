import Foundation

/// Accumulates a process's output as it arrives and reports each line once it is complete.
///
/// Lines are split on the raw bytes rather than on decoded text: a read can end in the middle of a
/// multi-byte character, and decoding each chunk on its own would leave replacement characters
/// inside the lines a caller matches against.
final class OutputLineBuffer: @unchecked Sendable {
    /// Everything appended so far, in one piece.
    var output: String {
        lock.lock()
        defer { lock.unlock() }
        return Self.decoded(accumulated)
    }

    private let lock = NSLock()
    private var accumulated = Data()
    private var pending = Data()

    /// Decodes bytes a process produced, substituting for anything that is not valid UTF-8 rather
    /// than failing on it. The failable `String(bytes:encoding:)` SwiftLint prefers would drop a
    /// whole line for a single bad byte, and a line a caller matches on is worth keeping even when
    /// part of it is unreadable.
    private static func decoded(_ bytes: some Collection<UInt8>) -> String {
        // swiftlint:disable:next optional_data_string_conversion
        String(decoding: bytes, as: UTF8.self)
    }

    /// Appends the next chunk of output and returns the lines it completed, newline stripped. A
    /// trailing partial line is held back until a later chunk finishes it.
    func append(_ chunk: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }

        accumulated.append(chunk)
        pending.append(chunk)

        var lines: [String] = []

        while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
            lines.append(Self.decoded(pending[pending.startIndex ..< newline]))
            pending = Data(pending[pending.index(after: newline)...])
        }

        return lines
    }
}
