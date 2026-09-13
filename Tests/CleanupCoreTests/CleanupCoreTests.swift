import XCTest
@testable import CleanupCore

final class CleanupCoreTests: XCTestCase {
    private var root: URL!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try FileManager.default.removeItem(at: root) }
    }

    @discardableResult
    private func file(_ path: String, age: TimeInterval = 0, contents: String = "image") throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: url.path)
        return url
    }

    func testStrictTwentyFourHourBoundary() throws {
        try file("Screenshot old.png", age: 86401)
        try file("Screenshot boundary.png", age: 86400)
        try file("Screenshot recent.png", age: 86399)
        try file("Screenshots/Screenshot filed boundary.png", age: 86400)
        try file("Screenshots/Screenshot filed old.png", age: 86401)
        let scan = CleanupEngine(desktop: root).scan(now: now)
        XCTAssertTrue(scan.errors.isEmpty)
        let candidates = scan.candidates
        let actions = Dictionary(uniqueKeysWithValues: candidates.map { ($0.url.lastPathComponent, $0.action) })
        XCTAssertEqual(actions, ["Screenshot old.png": .trash, "Screenshot boundary.png": .file,
                                 "Screenshot recent.png": .file, "Screenshot filed old.png": .trash])
    }

    func testScanOnlyIncludesRegularMatchingFilesInSupportedDirectories() throws {
        try file("Screenshot modern.PNG")
        try file("Screen Shot legacy.pNg")
        try file("Screenshots/Screenshot archived.png", age: 90000)
        try file("Screenshot wrong.jpg")
        try file("screenshot lowercase.png")
        try file("Unrelated.png")
        try file("Nested/Screenshot nested.png")
        try file("Screenshots/Nested/Screenshot nested archive.png", age: 90000)
        let target = try file("target.png")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Screenshot link.png"), withDestinationURL: target)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Screenshot directory.png"), withIntermediateDirectories: true)
        let scan = CleanupEngine(desktop: root).scan(now: now)
        XCTAssertTrue(scan.errors.isEmpty)
        let candidates = scan.candidates
        XCTAssertEqual(Set(candidates.map { $0.url.lastPathComponent }),
                       ["Screenshot modern.PNG", "Screen Shot legacy.pNg", "Screenshot archived.png"])
        XCTAssertTrue(candidates.allSatisfy { $0.bytes == 5 })
    }

    func testCollisionPreservesExistingFilesAndUsesNextAvailableName() throws {
        try file("Screenshot same.png", contents: "incoming")
        let original = try file("Screenshots/Screenshot same.png", contents: "original")
        let firstSuffix = try file("Screenshots/Screenshot same-1.png", contents: "other")
        let result = CleanupEngine(desktop: root).run(trigger: "test", now: now) { _ in XCTFail("Unexpected trash") }
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.filed, 1)
        XCTAssertEqual(try String(contentsOf: original), "original")
        XCTAssertEqual(try String(contentsOf: firstSuffix), "other")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Screenshots/Screenshot same-2.png")), "incoming")
    }

    func testMissingScreenshotsDirectoryAllowsScanningAndCleanup() throws {
        let old = try file("Screenshot old.png", age: 90000)
        let engine = CleanupEngine(desktop: root)
        let scan = engine.scan(now: now)
        XCTAssertTrue(scan.errors.isEmpty)
        XCTAssertEqual(scan.candidates.map(\.url.lastPathComponent), [old.lastPathComponent])
        XCTAssertEqual(scan.candidates.first?.action, .trash)
        let result = engine.run(trigger: "test", now: now) { try FileManager.default.removeItem(at: $0) }
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.trashed, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
    }

    func testInvalidScreenshotsDirectoryReportsErrorAndStillCleansDesktop() throws {
        let old = try file("Screenshot old.png", age: 90000)
        let obstruction = try file("Screenshots", contents: "keep this file")
        let engine = CleanupEngine(desktop: root)
        let scan = engine.scan(now: now)
        XCTAssertEqual(scan.errors.count, 1)
        XCTAssertTrue(try XCTUnwrap(scan.errors.first).contains("Screenshots"))
        XCTAssertEqual(scan.candidates.map(\.url.lastPathComponent), [old.lastPathComponent])
        let result = engine.run(trigger: "test", now: now) { try FileManager.default.removeItem(at: $0) }
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertEqual(result.trashed, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertEqual(try String(contentsOf: obstruction), "keep this file")
    }

    func testTrashFailureContinuesAndFilesRecentScreenshots() throws {
        let failed = try file("Screenshot a failed.png", age: 90000)
        let old = try file("Screenshot b old.png", age: 90000)
        try file("Screenshot c recent.png")
        var attempted: [URL] = []
        let result = CleanupEngine(desktop: root).run(trigger: "manual", now: now) { url in
            attempted.append(url)
            if url.lastPathComponent == failed.lastPathComponent { throw CocoaError(.fileWriteNoPermission) }
            try FileManager.default.removeItem(at: url)
        }
        XCTAssertEqual(attempted.map(\.lastPathComponent), [failed, old].map(\.lastPathComponent))
        XCTAssertEqual(result.trigger, "manual")
        XCTAssertEqual(result.trashed, 1)
        XCTAssertEqual(result.filed, 1)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.errors.count, 1)
        let error = try XCTUnwrap(result.errors.first)
        XCTAssertTrue(error.contains(failed.lastPathComponent))
        XCTAssertTrue(FileManager.default.fileExists(atPath: failed.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Screenshots/Screenshot c recent.png").path))
    }

    func testSymlinkedScreenshotsDirectoryCannotReachExternalFiles() throws {
        let desktop = root.appendingPathComponent("Desktop", isDirectory: true)
        let external = root.appendingPathComponent("External", isDirectory: true)
        let recent = try file("Desktop/Screenshot recent.png", contents: "desktop image")
        let old = try file("External/Screenshot old.png", age: 90000, contents: "external image")
        try FileManager.default.createSymbolicLink(at: desktop.appendingPathComponent("Screenshots"), withDestinationURL: external)
        let engine = CleanupEngine(desktop: desktop)

        let scan = engine.scan(now: now)
        XCTAssertFalse(scan.errors.isEmpty)
        XCTAssertEqual(scan.candidates.map(\.url.lastPathComponent), [recent.lastPathComponent])
        XCTAssertEqual(scan.candidates.first?.action, .file)

        let result = engine.run(trigger: "test", now: now) { _ in XCTFail("Must not trash files through a directory symlink") }
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.trashed, 0)
        XCTAssertEqual(result.filed, 0)
        XCTAssertEqual(try String(contentsOf: recent), "desktop image")
        XCTAssertEqual(try String(contentsOf: old), "external image")
        XCTAssertFalse(FileManager.default.fileExists(atPath: external.appendingPathComponent(recent.lastPathComponent).path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: external.path), [old.lastPathComponent])
    }

    func testRepeatedRunHasNoFurtherWork() throws {
        try file("Screenshot old.png", age: 90000)
        try file("Screenshot new.png")
        let engine = CleanupEngine(desktop: root)
        let first = engine.run(trigger: "test", now: now) { try FileManager.default.removeItem(at: $0) }
        let second = engine.run(trigger: "test", now: now) { _ in XCTFail("Already processed") }
        XCTAssertTrue(first.succeeded)
        XCTAssertEqual(first.trashed, 1)
        XCTAssertEqual(first.filed, 1)
        XCTAssertTrue(second.succeeded)
        XCTAssertEqual(second.trashed, 0)
        XCTAssertEqual(second.filed, 0)
    }

    func testRunLockExcludesConcurrentRunAndReleases() throws {
        let url = root.appendingPathComponent("cleanup.lock")
        var first: RunLock? = try RunLock(url: url)
        XCTAssertNotNil(first)
        XCTAssertThrowsError(try RunLock(url: url)) { error in
            guard case CleanupError.alreadyRunning = error else { return XCTFail("Unexpected error: \(error)") }
        }
        first = nil
        XCTAssertNoThrow(try RunLock(url: url))
    }

    func testRunLockReportsMissingParent() {
        XCTAssertThrowsError(try RunLock(url: root.appendingPathComponent("missing/cleanup.lock")))
    }
}
