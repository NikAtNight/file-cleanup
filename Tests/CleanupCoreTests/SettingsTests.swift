import XCTest
@testable import CleanupCore

final class SettingsTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try FileManager.default.removeItem(at: root) }
    }

    func testValidationRejectsEmptyDuplicateAndOutOfRangeTimes() {
        let invalid: [[DailyTime]] = [[], [.init(hour: -1, minute: 0)], [.init(hour: 24, minute: 0)],
            [.init(hour: 0, minute: -1)], [.init(hour: 0, minute: 60)],
            [.init(hour: 9, minute: 30), .init(hour: 9, minute: 30)],
            (0..<9).map { .init(hour: $0, minute: 0) }]
        for times in invalid {
            var settings = Settings()
            settings.times = times
            XCTAssertThrowsError(try settings.validate(), "Accepted invalid times: \(times)")
        }
        var settings = Settings()
        settings.times = (0..<8).map { .init(hour: $0, minute: 59) }
        XCTAssertNoThrow(try settings.validate())
        settings.times = [.init(hour: 23, minute: 59), .init(hour: 0, minute: 0)]
        XCTAssertNoThrow(try settings.validate())
    }

    func testSchedulePlistUsesConfiguredTimesAndBackgroundArgument() throws {
        var settings = Settings()
        settings.times = [.init(hour: 8, minute: 15), .init(hour: 20, minute: 45)]
        let executable = "/Applications/Screenshot Cleanup.app/Contents/MacOS/ScreenshotCleanup"
        let log = "/tmp/cleanup log.txt"
        let data = try settings.launchAgentData(executable: executable, log: log)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["ProgramArguments"] as? [String], [executable, "--scheduled"])
        XCTAssertEqual(plist["StartCalendarInterval"] as? [[String: Int]],
                       [["Hour": 8, "Minute": 15], ["Hour": 20, "Minute": 45]])
        XCTAssertEqual(plist["ProcessType"] as? String, "Background")
        XCTAssertEqual(plist["StandardOutPath"] as? String, log)
        XCTAssertEqual(plist["StandardErrorPath"] as? String, log)
        settings.times = []
        XCTAssertThrowsError(try settings.launchAgentData(executable: executable, log: log))
    }

    func testNextRunChoosesEarliestFutureTimeAndRollsToTomorrow() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        func date(_ day: Int, _ hour: Int, _ minute: Int) throws -> Date {
            try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute)))
        }
        var settings = Settings()
        settings.times = [.init(hour: 10, minute: 0), .init(hour: 9, minute: 30)]
        XCTAssertEqual(settings.nextRun(after: try date(13, 9, 0), calendar: calendar), try date(13, 9, 30))
        XCTAssertEqual(settings.nextRun(after: try date(13, 9, 30), calendar: calendar), try date(13, 10, 0))
        XCTAssertEqual(settings.nextRun(after: try date(13, 10, 0), calendar: calendar), try date(14, 9, 30))
        settings.enabled = false
        XCTAssertNil(settings.nextRun(after: try date(13, 9, 0), calendar: calendar))
    }

    func testStoreDefaultsAndSettingsRoundTrip() throws {
        let store = try Store(directory: root.appendingPathComponent("state"))
        XCTAssertEqual(try store.settings(), Settings())
        XCTAssertTrue(try store.history().isEmpty)
        var settings = Settings()
        settings.enabled = false
        settings.times = [.init(hour: 23, minute: 59)]
        try store.save(settings)
        XCTAssertEqual(try Store(directory: store.directory).settings(), settings)
        var invalid = settings
        invalid.times = []
        XCTAssertThrowsError(try store.save(invalid))
        XCTAssertEqual(try store.settings(), settings)
    }

    func testStoreReportsCorruptAndInvalidSettings() throws {
        let store = try Store(directory: root)
        try Data("invalid JSON".utf8).write(to: store.settingsURL)
        XCTAssertThrowsError(try store.settings())
        var settings = Settings()
        settings.times = [.init(hour: 99, minute: 0)]
        try JSONEncoder().encode(settings).write(to: store.settingsURL)
        XCTAssertThrowsError(try store.settings())
    }

    func testHistoryKeepsLatestThirtyRunsAndPreservesErrors() throws {
        let store = try Store(directory: root)
        for index in 0..<35 {
            var result = RunResult(trigger: "run \(index)")
            result.trashed = index
            result.filed = 2
            result.errors = ["permission denied"]
            try store.record(result)
        }
        let history = try store.history()
        XCTAssertEqual(history.count, 30)
        XCTAssertEqual(history.first?.trigger, "run 34")
        XCTAssertEqual(history.last?.trigger, "run 5")
        XCTAssertEqual(history.first?.trashed, 34)
        XCTAssertEqual(history.first?.filed, 2)
        XCTAssertEqual(history.first?.errors, ["permission denied"])
        XCTAssertEqual(history.first?.succeeded, false)
    }

    func testLegacySettingsMigrateDefaultRulesAndAppearance() throws {
        let legacy = Data(#"{"enabled":false,"times":[{"hour":8,"minute":15}]}"#.utf8)
        let store = try Store(directory: root)
        try legacy.write(to: store.settingsURL)
        let settings = try store.settings()
        XCTAssertFalse(settings.enabled)
        XCTAssertEqual(settings.times, [.init(hour: 8, minute: 15)])
        XCTAssertEqual(settings.rules, [.screenshots()])
        XCTAssertEqual(settings.appearance, .system)
        try store.save(settings)
        XCTAssertEqual(try store.settings(), settings)
    }

    func testCustomRulesAndAppearanceRoundTrip() throws {
        let store = try Store(directory: root)
        var settings = Settings()
        settings.appearance = .dark
        settings.rules = [CleanupRule(name: "Documents", sourcePath: root.appendingPathComponent("Documents").path,
                                      extensions: ["pdf", "docx"], prefixes: [], ageHours: 48)]
        try store.save(settings)
        XCTAssertEqual(try store.settings(), settings)
    }

    func testDuplicateOwnedDirectoriesAreRejected() {
        let source = root.appendingPathComponent("Source").path
        let archive = root.appendingPathComponent("Archive").path
        let first = CleanupRule(name: "First", sourcePath: source, archivePath: archive)
        for duplicate in [source, archive, source + "/../Source"] {
            var settings = Settings()
            settings.rules = [first, CleanupRule(name: "Second", sourcePath: duplicate)]
            XCTAssertThrowsError(try settings.validate())
            settings.rules[1].enabled = false
            XCTAssertNoThrow(try settings.validate())
        }
        var settings = Settings()
        settings.rules = [first, first]
        XCTAssertThrowsError(try settings.validate())
    }

    func testRuleValidationRejectsInvalidPathsFiltersAndAges() {
        let valid = CleanupRule(name: "Documents", sourcePath: root.path, extensions: ["pdf"], prefixes: [])
        XCTAssertNoThrow(try valid.validate())
        let changes: [(inout CleanupRule) -> Void] = [
            { $0.name = " " }, { $0.sourcePath = "relative" }, { $0.sourcePath = "/" },
            { $0.ageHours = 0 }, { $0.ageHours = 8761 }, { $0.extensions = [] },
            { $0.extensions = [".pdf"] }, { $0.prefixes = [""] }, { $0.prefixes = ["path/name"] },
            { $0.archivePath = $0.sourcePath }, { $0.archivePath = "relative" }
        ]
        for change in changes {
            var rule = valid
            change(&rule)
            XCTAssertThrowsError(try rule.validate())
        }
    }

    func testAutomaticApprovalRevokesForEveryScopedChange() throws {
        let original = CleanupRule.screenshots()
        XCTAssertTrue(original.allowsAutomaticCleanup)
        let changes: [(inout CleanupRule) -> Void] = [
            { $0.sourcePath += "/Other" }, { $0.archivePath = nil }, { $0.extensions = ["jpg"] },
            { $0.prefixes = [] }, { $0.ageHours = 48 }, { $0.maxAutomaticFiles = 26 }
        ]
        for change in changes {
            var rule = original
            change(&rule)
            XCTAssertFalse(rule.allowsAutomaticCleanup)
        }
        var renamed = original
        renamed.name = "Renamed"
        XCTAssertTrue(renamed.allowsAutomaticCleanup)
        for cap in [0, 1001] {
            var rule = original
            rule.maxAutomaticFiles = cap
            XCTAssertThrowsError(try rule.validate())
        }
    }

    func testFreshSettingsRequireReviewAndLegacySettingsKeepApproval() throws {
        let fresh = Settings()
        XCTAssertFalse(try XCTUnwrap(fresh.rules.first).allowsAutomaticCleanup)
        let roundTrip = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(fresh))
        XCTAssertFalse(try XCTUnwrap(roundTrip.rules.first).allowsAutomaticCleanup)
        let legacy = Data(#"{"enabled":true,"times":[{"hour":9,"minute":30}]}"#.utf8)
        let migrated = try JSONDecoder().decode(Settings.self, from: legacy)
        XCTAssertTrue(try XCTUnwrap(migrated.rules.first).allowsAutomaticCleanup)
        let persistedMigration = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(migrated))
        XCTAssertTrue(try XCTUnwrap(persistedMigration.rules.first).allowsAutomaticCleanup)
    }

    func testLegacyApprovalOnlyMigratesExactOriginalScreenshotPolicy() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let original = CleanupRule.screenshots()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(original)) as? [String: Any])
        object.removeValue(forKey: "automaticApproval")
        object.removeValue(forKey: "maxAutomaticFiles")
        func decode(_ value: [String: Any]) throws -> CleanupRule {
            try decoder.decode(CleanupRule.self, from: JSONSerialization.data(withJSONObject: value))
        }
        XCTAssertTrue(try decode(object).allowsAutomaticCleanup)
        var changed = object
        changed["prefixes"] = [] as [String]
        XCTAssertFalse(try decode(changed).allowsAutomaticCleanup)
        changed = object
        changed["id"] = UUID().uuidString
        XCTAssertFalse(try decode(changed).allowsAutomaticCleanup)
        changed = object
        changed["automaticApproval"] = NSNull()
        XCTAssertFalse(try decode(changed).allowsAutomaticCleanup)
        var revoked = original
        revoked.automaticApproval = nil
        XCTAssertFalse(try decoder.decode(CleanupRule.self, from: encoder.encode(revoked)).allowsAutomaticCleanup)
    }

    func testCorruptHistoryIsReportedAndNotOverwritten() throws {
        let store = try Store(directory: root)
        let corrupt = Data("broken history".utf8)
        try corrupt.write(to: store.historyURL)
        XCTAssertThrowsError(try store.history())
        XCTAssertThrowsError(try store.record(RunResult(trigger: "test")))
        XCTAssertEqual(try Data(contentsOf: store.historyURL), corrupt)
    }
}
