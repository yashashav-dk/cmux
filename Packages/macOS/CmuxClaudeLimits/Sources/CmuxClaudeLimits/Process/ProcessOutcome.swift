public import Foundation

public struct ProcessOutcome: Sendable, Equatable {
    public var exitStatus: Int32?
    public var stdout: Data
    public var stderr: Data
    public var timedOut: Bool
    public var launchError: String?

    public init(
        exitStatus: Int32? = nil,
        stdout: Data = Data(),
        stderr: Data = Data(),
        timedOut: Bool = false,
        launchError: String? = nil
    ) {
        self.exitStatus = exitStatus
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
        self.launchError = launchError
    }
}
