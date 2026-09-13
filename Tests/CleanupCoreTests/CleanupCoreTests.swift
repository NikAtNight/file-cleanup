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
        let result = CleanupEngine(desktop: root).run(trigger: "test", now: now) { _ in XCTFail("Unexpected trash"); return TrashBatchResult(trashed: 0) }
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
        let result = engine.run(trigger: "test", now: now) { urls in
            for url in urls { try FileManager.default.removeItem(at: url) }
            return TrashBatchResult(trashed: urls.count)
        }
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.trashed, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
    }

    func testInvalidScreenshotsDirectoryAbortsAllEffects() throws {
        let old = try file("Screenshot old.png", age: 90000)
        let obstruction = try file("Screenshots", contents: "keep this file")
        let engine = CleanupEngine(desktop: root)
        let scan = engine.scan(now: now)
        XCTAssertEqual(scan.errors.count, 1)
        XCTAssertTrue(try XCTUnwrap(scan.errors.first).contains("Screenshots"))
        XCTAssertEqual(scan.candidates.map(\.url.lastPathComponent), [old.lastPathComponent])
        let result = engine.run(trigger: "test", now: now) { urls in
            for url in urls { try FileManager.default.removeItem(at: url) }
            return TrashBatchResult(trashed: urls.count)
        }
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertEqual(result.trashed, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.path))
        XCTAssertEqual(try String(contentsOf: obstruction), "keep this file")
    }

    func testTrashBatchFailureStillFilesRecentScreenshots() throws {
        let failed = try file("Screenshot a failed.png", age: 90000)
        let old = try file("Screenshot b old.png", age: 90000)
        try file("Screenshot c recent.png")
        var attempted: [[URL]] = []
        let result = CleanupEngine(desktop: root).run(trigger: "manual", now: now) { urls in
            attempted.append(urls)
            throw CocoaError(.fileWriteNoPermission)
        }
        XCTAssertEqual(attempted.count, 1)
        XCTAssertEqual(try XCTUnwrap(attempted.first).map(\.lastPathComponent), [failed, old].map(\.lastPathComponent))
        XCTAssertEqual(result.trigger, "manual")
        XCTAssertEqual(result.trashed, 0)
        XCTAssertEqual(result.filed, 1)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: failed.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Screenshots/Screenshot c recent.png").path))
    }

    func testPartialTrashBatchRecordsSuccessAndErrorWhileFilingRecentFiles() throws {
        let skipped = try file("Screenshot a skipped.png", age: 90000)
        let old = try file("Screenshot b old.png", age: 90000)
        try file("Screenshot recent.png")
        var batches = 0
        let message = "Screenshot a skipped.png: file unavailable"
        let result = CleanupEngine(desktop: root).run(trigger: "test", now: now) { urls in
            batches += 1
            XCTAssertEqual(urls.map(\.lastPathComponent), [skipped, old].map(\.lastPathComponent))
            let processed = try XCTUnwrap(urls.first { $0.lastPathComponent == old.lastPathComponent })
            try FileManager.default.removeItem(at: processed)
            return TrashBatchResult(trashed: 1, errors: [message])
        }
        XCTAssertEqual(batches, 1)
        XCTAssertEqual(result.trashed, 1)
        XCTAssertEqual(result.errors, [message])
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.filed, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: skipped.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Screenshots/Screenshot recent.png").path))
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

        let result = engine.run(trigger: "test", now: now) { _ in XCTFail("Must not trash files through a directory symlink"); return TrashBatchResult(trashed: 0) }
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
        let first = engine.run(trigger: "test", now: now) { urls in
            for url in urls { try FileManager.default.removeItem(at: url) }
            return TrashBatchResult(trashed: urls.count)
        }
        let second = engine.run(trigger: "test", now: now) { _ in XCTFail("Already processed"); return TrashBatchResult(trashed: 0) }
        XCTAssertTrue(first.succeeded)
        XCTAssertEqual(first.trashed, 1)
        XCTAssertEqual(first.filed, 1)
        XCTAssertTrue(second.succeeded)
        XCTAssertEqual(second.trashed, 0)
        XCTAssertEqual(second.filed, 0)
    }

    func testCustomRuleWithoutArchiveUsesExtensionsAndAgeWithoutPrefixes() throws {
        let source = root.appendingPathComponent("Downloads")
        try file("Downloads/report.PDF", age: 7201)
        try file("Downloads/boundary.pdf", age: 7200)
        try file("Downloads/recent.pdf", age: 10)
        try file("Downloads/other.png", age: 90000)
        let rule = CleanupRule(name: "Documents", sourcePath: source.path,
                               extensions: ["pdf"], prefixes: [], ageHours: 2)
        let scan = CleanupEngine(rules: [rule]).scan(now: now)
        XCTAssertTrue(scan.errors.isEmpty)
        XCTAssertEqual(scan.candidates.map(\.url.lastPathComponent), ["report.PDF"])
        XCTAssertEqual(scan.candidates.first?.action, .trash)
        XCTAssertEqual(scan.candidates.first?.ruleName, "Documents")
        XCTAssertNil(scan.candidates.first?.destinationDirectory)
    }

    func testDistinctRulesUseOneTrashBatchAndSkipDisabledRule() throws {
        try file("Documents/invoice.pdf", age: 90000)
        try file("Images/Photo old.JPG", age: 90000)
        try file("Images/unmatched.jpg", age: 90000)
        let disabled = try file("Disabled/ignored.png", age: 90000)
        let rules = [
            CleanupRule(name: "Documents", sourcePath: root.appendingPathComponent("Documents").path,
                        extensions: ["pdf"], prefixes: []),
            CleanupRule(name: "Photos", sourcePath: root.appendingPathComponent("Images").path,
                        extensions: ["jpg"], prefixes: ["Photo "]),
            CleanupRule(name: "Disabled", enabled: false, sourcePath: root.appendingPathComponent("Disabled").path,
                        prefixes: [])
        ]
        var batches: [[URL]] = []
        let engine = CleanupEngine(rules: rules)
        let result = engine.run(trigger: "test", now: now, reviewedCandidates: engine.scan(now: now).candidates) { urls in
            batches.append(urls)
            for url in urls { try FileManager.default.removeItem(at: url) }
            return TrashBatchResult(trashed: urls.count)
        }
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.trashed, 2)
        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(Set(try XCTUnwrap(batches.first).map(\.lastPathComponent)), ["invoice.pdf", "Photo old.JPG"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: disabled.path))
    }

    func testSymlinkedSourceCannotScanExternalFiles() throws {
        let old = try file("External/document.pdf", age: 90000)
        let link = root.appendingPathComponent("Linked")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: old.deletingLastPathComponent())
        let rule = CleanupRule(name: "Linked", sourcePath: link.path, extensions: ["pdf"], prefixes: [])
        let engine = CleanupEngine(rules: [rule])
        let scan = engine.scan(now: now)
        XCTAssertFalse(scan.errors.isEmpty)
        XCTAssertTrue(scan.candidates.isEmpty)
        let result = engine.run(trigger: "test", now: now) { _ in XCTFail("Unexpected trash"); return TrashBatchResult(trashed: 0) }
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(try String(contentsOf: old), "image")
    }

    func testBrokenDestinationSymlinkIsPreservedOnCollision() throws {
        try file("Screenshot same.png", contents: "incoming")
        let archive = root.appendingPathComponent("Screenshots")
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        let collision = archive.appendingPathComponent("Screenshot same.png")
        let target = root.appendingPathComponent("missing.png")
        try FileManager.default.createSymbolicLink(at: collision, withDestinationURL: target)
        let result = CleanupEngine(desktop: root).run(trigger: "test", now: now) { _ in XCTFail("Unexpected trash"); return TrashBatchResult(trashed: 0) }
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.filed, 1)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: collision.path), target.path)
        XCTAssertEqual(try String(contentsOf: archive.appendingPathComponent("Screenshot same-1.png")), "incoming")
    }

    func testUnapprovedRulesHaveNoAutomaticEffectsButReviewedRunWorks() throws {
        let old = try file("Custom/old.png", age: 90000)
        let rule = CleanupRule(name: "Custom", sourcePath: old.deletingLastPathComponent().path, prefixes: [])
        let engine = CleanupEngine(rules: [rule])
        let automatic = engine.run(trigger: "scheduled", now: now) { _ in XCTFail("Unapproved run"); return TrashBatchResult(trashed: 0) }
        XCTAssertFalse(automatic.succeeded)
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.path))
        let manual = engine.run(trigger: "manual", now: now, reviewedCandidates: engine.scan(now: now).candidates) { urls in
            for url in urls { try FileManager.default.removeItem(at: url) }
            return TrashBatchResult(trashed: urls.count)
        }
        XCTAssertTrue(manual.succeeded)
        XCTAssertEqual(manual.trashed, 1)
    }

    func testAutomaticLimitCountsFilingAndPausesAllRules() throws {
        let old = try file("First/old.png", age: 90000)
        let recent = try file("First/recent.png")
        let other = try file("Second/other.png", age: 90000)
        var first = CleanupRule(name: "First", sourcePath: old.deletingLastPathComponent().path,
                                archivePath: root.appendingPathComponent("Archive").path, prefixes: [], maxAutomaticFiles: 1)
        var second = CleanupRule(name: "Second", sourcePath: other.deletingLastPathComponent().path, prefixes: [])
        first.automaticApproval = first.approvalSignature
        second.automaticApproval = second.approvalSignature
        let engine = CleanupEngine(rules: [first, second])
        let result = engine.run(trigger: "scheduled", now: now) { _ in XCTFail("Limit must stop the whole run"); return TrashBatchResult(trashed: 0) }
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.filed, 0)
        for url in [old, recent, other] { XCTAssertTrue(FileManager.default.fileExists(atPath: url.path)) }
        let reviewed = engine.run(trigger: "manual", now: now, reviewedCandidates: engine.scan(now: now).candidates) { urls in
            for url in urls { try FileManager.default.removeItem(at: url) }
            return TrashBatchResult(trashed: urls.count)
        }
        XCTAssertTrue(reviewed.succeeded)
        XCTAssertEqual(reviewed.trashed, 2)
        XCTAssertEqual(reviewed.filed, 1)
    }

    func testReviewRejectsChangedMetadataAndNewCandidates() throws {
        let old = try file("Screenshot old.png", age: 90000)
        let engine = CleanupEngine(desktop: root)
        let reviewed = engine.scan(now: now).candidates
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-91000)], ofItemAtPath: old.path)
        let changed = engine.run(trigger: "manual", now: now, reviewedCandidates: reviewed) { _ in XCTFail("Stale review"); return TrashBatchResult(trashed: 0) }
        XCTAssertFalse(changed.succeeded)
        let refreshed = engine.scan(now: now).candidates
        try file("Screenshot added.png", age: 90000)
        let added = engine.run(trigger: "manual", now: now, reviewedCandidates: refreshed) { _ in XCTFail("New candidate"); return TrashBatchResult(trashed: 0) }
        XCTAssertFalse(added.succeeded)
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.path))
    }

    func testReviewRejectsReplacementWithSameSizeAndModificationDate() throws {
        let old = try file("Screenshot old.png", age: 90000, contents: "first")
        let engine = CleanupEngine(desktop: root)
        let reviewed = engine.scan(now: now).candidates
        let replacement = try file("replacement.png", age: 90000, contents: "other")
        try FileManager.default.removeItem(at: old)
        try FileManager.default.moveItem(at: replacement, to: old)
        let fresh = engine.scan(now: now).candidates
        XCTAssertEqual(fresh.first?.bytes, reviewed.first?.bytes)
        XCTAssertEqual(fresh.first?.modifiedDate, reviewed.first?.modifiedDate)
        XCTAssertNotEqual(fresh.first?.fileIdentity, reviewed.first?.fileIdentity)
        let result = engine.run(trigger: "manual", now: now, reviewedCandidates: reviewed) { _ in
            XCTFail("Replacement was not reviewed")
            return TrashBatchResult(trashed: 0)
        }
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(try String(contentsOf: old), "other")
    }

    func testProtectedLocationsAndPackageAncestorsAreRejectedBeforeEffects() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let paths = ["/", home.path, "/System", "/Library", "/Applications", home.appendingPathComponent("Library").path]
        for path in paths {
            let engine = CleanupEngine(rules: [CleanupRule(name: "Protected", sourcePath: path, prefixes: [])])
            let scan = engine.scan(now: now)
            XCTAssertFalse(scan.errors.isEmpty, path)
            XCTAssertTrue(scan.candidates.isEmpty, path)
        }
        for package in ["Archive.photoslibrary", "Archive.photolibrary", "Example.app"] {
            let old = try file(package + "/Inside/old.png", age: 90000)
            let engine = CleanupEngine(rules: [CleanupRule(name: "Package", sourcePath: old.deletingLastPathComponent().path, prefixes: [])])
            let result = engine.run(trigger: "manual", now: now, reviewedCandidates: []) { _ in XCTFail("Protected files"); return TrashBatchResult(trashed: 0) }
            XCTAssertFalse(result.succeeded)
            XCTAssertTrue(FileManager.default.fileExists(atPath: old.path))
        }
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
