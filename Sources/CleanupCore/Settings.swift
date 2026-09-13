import Foundation

public struct DailyTime: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String { "\(hour):\(minute)" }
    public var hour: Int
    public var minute: Int
    public init(hour: Int, minute: Int) { self.hour = hour; self.minute = minute }
}

public struct Settings: Codable, Equatable, Sendable {
    public var enabled = true
    public var times = [DailyTime(hour: 9, minute: 30), DailyTime(hour: 10, minute: 0)]
    public init() {}
    public func validate() throws {
        guard !times.isEmpty, times.count <= 8,
              times.allSatisfy({ (0...23).contains($0.hour) && (0...59).contains($0.minute) }),
              Set(times).count == times.count else {
            throw CleanupError.command("Choose one to eight different daily run times.")
        }
    }
    public func nextRun(after date: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard enabled else { return nil }
        return times.compactMap {
            calendar.nextDate(after: date, matching: DateComponents(hour: $0.hour, minute: $0.minute), matchingPolicy: .nextTime)
        }.min()
    }
    public func launchAgentData(executable: String, log: String) throws -> Data {
        try validate()
        let plist: [String: Any] = [
            "Label": "com.nikhlkapadia.cleanup-desktop-screenshots",
            "ProgramArguments": [executable, "--scheduled"],
            "StartCalendarInterval": times.map { ["Hour": $0.hour, "Minute": $0.minute] },
            "StandardOutPath": log,
            "StandardErrorPath": log,
            "ProcessType": "Background"
        ]
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }
}

public struct Store {
    public let directory: URL
    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    public var settingsURL: URL { directory.appendingPathComponent("settings.json") }
    public var historyURL: URL { directory.appendingPathComponent("history.json") }
    public var lockURL: URL { directory.appendingPathComponent("cleanup.lock") }
    public func settings() throws -> Settings {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return Settings() }
        let settings = try JSONDecoder().decode(Settings.self, from: Data(contentsOf: settingsURL))
        try settings.validate()
        return settings
    }
    public func save(_ settings: Settings) throws {
        try settings.validate()
        try JSONEncoder().encode(settings).write(to: settingsURL, options: .atomic)
    }
    public func history() throws -> [RunResult] {
        guard FileManager.default.fileExists(atPath: historyURL.path) else { return [] }
        return try JSONDecoder().decode([RunResult].self, from: Data(contentsOf: historyURL))
    }
    public func record(_ result: RunResult) throws {
        var history = try history()
        history.insert(result, at: 0)
        try JSONEncoder().encode(Array(history.prefix(30))).write(to: historyURL, options: .atomic)
    }
}
