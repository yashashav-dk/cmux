public import Foundation

public struct ProcessRequest: Sendable, Equatable {
    public var executable: String
    public var arguments: [String]
    /// `nil` inherits the app process environment.
    public var environment: [String: String]?
    public var currentDirectory: String?
    public var timeout: TimeInterval

    public init(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectory: String? = nil,
        timeout: TimeInterval
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.currentDirectory = currentDirectory
        self.timeout = timeout
    }
}
