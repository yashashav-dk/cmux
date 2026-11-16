public import Foundation

/// Runs a child process with stdin on `/dev/null`, draining stdout and stderr
/// concurrently and terminating the child when the timeout elapses.
public struct ForegroundProcessRunner: ProcessRunning {
    public init() {}

    public func run(_ request: ProcessRequest) async -> ProcessOutcome {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: Self.runBlocking(request))
            }
        }
    }

    private final class Drain: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        func set(_ value: Data) {
            lock.lock()
            data = value
            lock.unlock()
        }
        func get() -> Data {
            lock.lock()
            defer { lock.unlock() }
            return data
        }
    }

    private static func runBlocking(_ request: ProcessRequest) -> ProcessOutcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: request.executable)
        process.arguments = request.arguments
        if let environment = request.environment {
            process.environment = environment
        }
        if let directory = request.currentDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: directory)
        }
        process.standardInput = FileHandle.nullDevice
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            return ProcessOutcome(launchError: String(describing: error))
        }

        let outDrain = Drain()
        let errDrain = Drain()
        let group = DispatchGroup()
        for (pipe, drain) in [(outPipe, outDrain), (errPipe, errDrain)] {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                drain.set(pipe.fileHandleForReading.readDataToEndOfFile())
                group.leave()
            }
        }

        var timedOut = false
        if exited.wait(timeout: .now() + request.timeout) == .timedOut {
            timedOut = true
            process.terminate()
            if exited.wait(timeout: .now() + 2) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 2)
            }
        }
        _ = group.wait(timeout: .now() + 2)

        return ProcessOutcome(
            exitStatus: timedOut ? nil : process.terminationStatus,
            stdout: outDrain.get(),
            stderr: errDrain.get(),
            timedOut: timedOut,
            launchError: nil
        )
    }
}
