import Foundation
import Darwin

public enum CleanupAction: String, Codable { case trash, file }

public struct ScanResult {
    public init() {}
    public var candidates: [Candidate] = []
    public var errors: [String] = []
}

public struct TrashBatchResult {
    public var trashed: Int
    public var errors: [String]
    public init(trashed: Int, errors: [String] = []) { self.trashed = trashed; self.errors = errors }
}

public struct Candidate: Identifiable {
    public var id: String { url.path }
    public let url: URL
    public let action: CleanupAction
    public let bytes: Int64
    public let ruleName: String
    public let destinationDirectory: URL?
}

public struct RunResult: Codable, Identifiable {
    public var id = UUID()
    public var date = Date()
    public var trigger: String
    public var trashed = 0
    public var filed = 0
    public var errors: [String] = []
    public var succeeded: Bool { errors.isEmpty }
    public init(trigger: String) { self.trigger = trigger }
}

public enum CleanupError: LocalizedError {
    case alreadyRunning
    case command(String)
    public var errorDescription: String? {
        switch self {
        case .alreadyRunning: return "A cleanup is already running. Try again when it finishes."
        case .command(let message): return message
        }
    }
}

public struct CleanupEngine {
    public let rules: [CleanupRule]
    public init(rules: [CleanupRule]) { self.rules = rules }
    public init(desktop: URL) {
        rules = [CleanupRule(name: "Screenshots", sourcePath: desktop.path,
                             archivePath: desktop.appendingPathComponent("Screenshots").path)]
    }

    public func scan(now: Date = Date()) -> ScanResult {
        let fm = FileManager.default
        var result = ScanResult()
        var settings = Settings()
        settings.rules = rules
        do { try settings.validate() }
        catch { result.errors.append(error.localizedDescription); return result }
        for rule in rules where rule.enabled {
            let cutoff = now.addingTimeInterval(-Double(rule.ageHours) * 3600)
            for directory in [rule.source, rule.archive].compactMap({ $0 }) {
                do {
                    try verifyDirectory(directory)
                    if directory == rule.archive && !fm.fileExists(atPath: directory.path) { continue }
                    let urls = try fm.contentsOfDirectory(at: directory,
                        includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey],
                        options: [.skipsHiddenFiles])
                    for url in urls where rule.matches(url) {
                        do {
                            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey])
                            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                            guard let modified = values.contentModificationDate else { throw CocoaError(.fileReadUnknown) }
                            if modified < cutoff {
                                result.candidates.append(Candidate(url: url, action: .trash, bytes: Int64(values.fileSize ?? 0), ruleName: rule.name, destinationDirectory: nil))
                            } else if directory == rule.source, let archive = rule.archive {
                                result.candidates.append(Candidate(url: url, action: .file, bytes: Int64(values.fileSize ?? 0), ruleName: rule.name, destinationDirectory: archive))
                            }
                        } catch { result.errors.append("\(rule.name) / \(url.lastPathComponent): \(error.localizedDescription)") }
                    }
                } catch { result.errors.append("\(rule.name) / \(directory.path): \(error.localizedDescription)") }
            }
        }
        result.candidates.sort { $0.url.path < $1.url.path }
        return result
    }

    public func run(trigger: String, now: Date = Date(), trash: ([URL]) throws -> TrashBatchResult) -> RunResult {
        var result = RunResult(trigger: trigger)
        let scan = scan(now: now)
        result.errors = scan.errors
        let oldFiles = scan.candidates.filter { $0.action == .trash }.map(\.url)
        if !oldFiles.isEmpty {
            do {
                let batch = try trash(oldFiles)
                result.trashed = batch.trashed
                result.errors.append(contentsOf: batch.errors)
            }
            catch { result.errors.append(error.localizedDescription) }
        }
        for candidate in scan.candidates where candidate.action == .file {
            do {
                guard let directory = candidate.destinationDirectory else { continue }
                try verifyDirectory(directory)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: candidate.url, to: uniqueDestination(candidate.url, in: directory))
                result.filed += 1
            } catch { result.errors.append("\(candidate.url.lastPathComponent): \(error.localizedDescription)") }
        }
        return result
    }

    private func verifyDirectory(_ directory: URL) throws {
        // Check ancestors too, so a folder nested below a symlink cannot escape its selected location.
        var current = directory.standardizedFileURL
        while current.path != "/" {
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: current.path)) != nil {
                // macOS exposes /var and /tmp as system symlinks. These are valid temp roots, not user routing.
                if current.path != "/var" && current.path != "/tmp" {
                    throw CleanupError.command("\(directory.lastPathComponent) uses a symbolic link. Choose the actual folder instead.")
                }
            }
            current.deleteLastPathComponent()
        }
    }

    private func uniqueDestination(_ source: URL, in directory: URL) -> URL {
        var candidate = directory.appendingPathComponent(source.lastPathComponent)
        var suffix = 1
        while FileManager.default.fileExists(atPath: candidate.path) || (try? FileManager.default.destinationOfSymbolicLink(atPath: candidate.path)) != nil {
            candidate = directory.appendingPathComponent("\(source.deletingPathExtension().lastPathComponent)-\(suffix).\(source.pathExtension)")
            suffix += 1
        }
        return candidate
    }
}

/// The same lock covers manual runs and the separate launchd process.
public final class RunLock {
    private let descriptor: Int32
    public init(url: URL) throws {
        descriptor = open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw CleanupError.command("Could not open the cleanup lock.") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw CleanupError.alreadyRunning
        }
    }
    deinit { flock(descriptor, LOCK_UN); close(descriptor) }
}
