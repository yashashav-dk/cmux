public import Foundation

/// Allowlist environment for the refresh subprocess. Nothing from the app
/// process environment is inherited beyond what is listed here.
public struct RefreshEnvironment: Sendable {
    public static let path = "~/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    private let home: String
    private let user: String
    private let logname: String
    private let tmpdir: String
    private let lang: String?

    public init(home: String, user: String, logname: String, tmpdir: String, lang: String?) {
        self.home = home
        self.user = user
        self.logname = logname
        self.tmpdir = tmpdir
        self.lang = lang
    }

    public func variables(configDir: String?) -> [String: String] {
        var result: [String: String] = [
            "HOME": home,
            "USER": user,
            "LOGNAME": logname,
            "TMPDIR": tmpdir,
            "PATH": Self.path.replacingOccurrences(of: "~", with: home),
        ]
        if let lang { result["LANG"] = lang }
        if let configDir { result["CLAUDE_CONFIG_DIR"] = configDir }
        return result
    }
}
