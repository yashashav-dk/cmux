public import Foundation

public struct ResetTextStrings: Sendable, Equatable {
    public var idle: String
    public var reset: String
    public var inFormat: String
    public var tooltipFormat: String

    public init(idle: String, reset: String, inFormat: String, tooltipFormat: String) {
        self.idle = idle
        self.reset = reset
        self.inFormat = inFormat
        self.tooltipFormat = tooltipFormat
    }

    public static let english = ResetTextStrings(
        idle: "idle",
        reset: "reset",
        inFormat: "in %@",
        tooltipFormat: "Resets %@ · %@ used · fetched %@"
    )
}

public struct ResetTextFormatter: Sendable {
    private let timeZone: TimeZone
    private let locale: Locale
    private let calendar: Calendar
    private let strings: ResetTextStrings

    public init(
        timeZone: TimeZone,
        locale: Locale = Locale(identifier: "en_US_POSIX"),
        calendar: Calendar = Calendar(identifier: .gregorian),
        strings: ResetTextStrings = .english
    ) {
        var calendar = calendar
        calendar.timeZone = timeZone
        calendar.locale = locale
        self.timeZone = timeZone
        self.locale = locale
        self.calendar = calendar
        self.strings = strings
    }

    public func text(for window: UsageWindow?, now: Date) -> String {
        guard let resetsAt = window?.resetsAt else { return strings.idle }
        let interval = resetsAt.timeIntervalSince(now)
        if interval < 0 { return strings.reset }
        if interval < 24 * 3600 {
            return String(format: strings.inFormat, duration(interval))
        }
        return absolute(resetsAt)
    }

    public func tooltip(for window: UsageWindow, lastFetched: Date, now: Date) -> String {
        let percent = "\(Int(window.percent.rounded()))%"
        let fetchedAge = max(0, now.timeIntervalSince(lastFetched))
        let fetched: String
        if fetchedAge < 60 {
            fetched = "just now"
        } else {
            fetched = "\(duration(fetchedAge)) ago"
        }
        return String(format: strings.tooltipFormat, text(for: window, now: now), percent, fetched)
    }

    private func duration(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int(interval / 60))
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest)m" }
        if rest == 0 { return "\(hours)h" }
        return "\(hours)h\(rest)m"
    }

    private func absolute(_ date: Date) -> String {
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = locale
        weekdayFormatter.calendar = calendar
        weekdayFormatter.timeZone = timeZone
        weekdayFormatter.dateFormat = "EEE"
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour24 = parts.hour ?? 0
        let minute = parts.minute ?? 0
        let hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12
        let suffix = hour24 < 12 ? "am" : "pm"
        let time = minute == 0 ? "\(hour12)\(suffix)" : "\(hour12):\(String(format: "%02d", minute))\(suffix)"
        return "\(weekdayFormatter.string(from: date)) \(time)"
    }
}
