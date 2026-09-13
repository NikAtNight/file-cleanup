import Foundation
import Darwin

public enum CleanupAction: String, Codable { case trash, file }

public struct ScanResult {
    public var candidates: [Candidate] = []
    public var errors: [String] = []
}

public struct Candidate: Identifiable {
    public var id: String { url.path }
    public let url: URL
    public let action: CleanupAction
    public let bytes: Int64
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
    public let desktop: URL
    public var screenshots: URL { desktop.appendingPathComponent("Screenshots", isDirectory: true) }
    public init(desktop: URL) { self.desktop = desktop }

    public func scan(now: Date = Date()) -> ScanResult {
        let fm = FileManager.default
        let cutoff = now.addingTimeInterval(-86400)
        var result = ScanResult()
        for directory in [desktop, screenshots] {
            do {
                if directory == screenshots {
                    try verifyScreenshotsDirectory()
                    if !fm.fileExists(atPath: directory.path) { continue }
                }
                let urls = try fm.contentsOfDirectory(at: directory,
                    includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey],
                    options: [.skipsHiddenFiles])
                for url in urls {
                    let name = url.lastPathComponent
                    guard (name.hasPrefix("Screenshot ") || name.hasPrefix("Screen Shot ")),
                          url.pathExtension.lowercased() == "png" else { continue }
                    do {
                        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey])
                        guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                        guard let modified = values.contentModificationDate else { throw CocoaError(.fileReadUnknown) }
                        if modified < cutoff {
                            result.candidates.append(Candidate(url: url, action: .trash, bytes: Int64(values.fileSize ?? 0)))
                        } else if directory == desktop {
                            result.candidates.append(Candidate(url: url, action: .file, bytes: Int64(values.fileSize ?? 0)))
                        }
                    } catch { result.errors.append("\(url.lastPathComponent): \(error.localizedDescription)") }
                }
            } catch { result.errors.append("\(directory.path): \(error.localizedDescription)") }
        }
        result.candidates.sort { $0.url.path < $1.url.path }
        return result
    }

    public func run(trigger: String, now: Date = Date(), trash: (URL) throws -> Void) -> RunResult {
        var result = RunResult(trigger: trigger)
        let scan = scan(now: now)
        result.errors = scan.errors
        for candidate in scan.candidates {
            do {
                switch candidate.action {
                case .trash:
                    try trash(candidate.url)
                    result.trashed += 1
                case .file:
                    try verifyScreenshotsDirectory()
                    try FileManager.default.createDirectory(at: screenshots, withIntermediateDirectories: true)
                    try FileManager.default.moveItem(at: candidate.url, to: uniqueDestination(candidate.url))
                    result.filed += 1
                }
            } catch { result.errors.append("\(candidate.url.lastPathComponent): \(error.localizedDescription)") }
        }
        return result
    }

    private func verifyScreenshotsDirectory() throws {
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: screenshots.path)) != nil {
            throw CleanupError.command("Desktop/Screenshots is a symbolic link. Use a regular folder to keep cleanup within Desktop.")
        }
    }

    private func uniqueDestination(_ source: URL) -> URL {
        let initial = screenshots.appendingPathComponent(source.lastPathComponent)
        var candidate = initial
        var suffix = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = screenshots.appendingPathComponent("\(source.deletingPathExtension().lastPathComponent)-\(suffix).\(source.pathExtension)")
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
