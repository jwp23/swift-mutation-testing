import Foundation

func captureOutput(_ block: () async -> Void) async -> String {
    let pipe = Pipe()
    let originalStdout = dup(STDOUT_FILENO)
    dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

    await block()

    fflush(stdout)
    dup2(originalStdout, STDOUT_FILENO)
    close(originalStdout)
    pipe.fileHandleForWriting.closeFile()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}

func captureOutputSync(_ block: () -> Void) -> String {
    let pipe = Pipe()
    let originalStdout = dup(STDOUT_FILENO)
    dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

    block()

    fflush(stdout)
    dup2(originalStdout, STDOUT_FILENO)
    close(originalStdout)
    pipe.fileHandleForWriting.closeFile()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}

func captureStandardError(_ block: () async throws -> Void) async throws -> String {
    let pipe = Pipe()
    let originalStderr = dup(STDERR_FILENO)
    dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

    do {
        try await block()
    } catch {
        fflush(stderr)
        dup2(originalStderr, STDERR_FILENO)
        close(originalStderr)
        pipe.fileHandleForWriting.closeFile()
        throw error
    }

    fflush(stderr)
    dup2(originalStderr, STDERR_FILENO)
    close(originalStderr)
    pipe.fileHandleForWriting.closeFile()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}
