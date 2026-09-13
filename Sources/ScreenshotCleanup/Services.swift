import AppKit
import CleanupCore

struct Command {
    static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw CleanupError.command(text.isEmpty ? "\(URL(fileURLWithPath: executable).lastPathComponent) exited with code \(process.terminationStatus)." : text)
        }
        return text
    }
}

struct FinderTrash {
    static func connect() throws {
        _ = try Command.run("/usr/bin/osascript", ["-e", "with timeout of 30 seconds\ntell application \"Finder\" to get name of startup disk\nend timeout"])
    }
    static func trash(_ url: URL) throws {
        // Arguments stay separate from AppleScript source, including quotes in filenames.
        let script = """
        on run arguments
            set targetFile to (POSIX file (item 1 of arguments)) as alias
            with timeout of 30 seconds
                tell application "Finder" to delete targetFile
            end timeout
        end run
        """
        _ = try Command.run("/usr/bin/osascript", ["-e", script, url.path])
    }
}

struct AppServices {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let support = home.appendingPathComponent("Library/Application Support/Screenshot Cleanup", isDirectory: true)
    static let desktop = home.appendingPathComponent("Desktop", isDirectory: true)
    static let engine = CleanupEngine(desktop: desktop)
    static func store() throws -> Store { try Store(directory: support) }
    static func clean(trigger: String) throws -> RunResult {
        let store = try store()
        let lock = try RunLock(url: store.lockURL)
        return withExtendedLifetime(lock) {
            var result = engine.run(trigger: trigger, trash: FinderTrash.trash)
            do { try store.record(result) }
            catch { result.errors.append("Could not save run history: \(error.localizedDescription)") }
            return result
        }
    }
}

struct ScheduleService {
    static let label = "com.nikhlkapadia.cleanup-desktop-screenshots"
    static var domain: String { "gui/\(getuid())" }
    static var plist: URL { AppServices.home.appendingPathComponent("Library/LaunchAgents/\(label).plist") }
    static var installedExecutable: String {
        AppServices.home.appendingPathComponent("Applications/Screenshot Cleanup.app/Contents/MacOS/ScreenshotCleanup").path
    }
    static func isLoaded() -> Bool {
        (try? Command.run("/bin/launchctl", ["print", "\(domain)/\(label)"])) != nil
    }
    static func apply(_ settings: Settings) throws {
        try settings.validate()
        guard FileManager.default.isExecutableFile(atPath: installedExecutable) else {
            throw CleanupError.command("Install Screenshot Cleanup in your Applications folder before saving a schedule.")
        }
        let store = try AppServices.store()
        let lock = try RunLock(url: store.lockURL)
        try withExtendedLifetime(lock) {
            let fm = FileManager.default
            let oldData = fm.fileExists(atPath: plist.path) ? try Data(contentsOf: plist) : nil
            let wasLoaded = isLoaded()
            let logDirectory = AppServices.home.appendingPathComponent(".local/var/log", isDirectory: true)
            try fm.createDirectory(at: logDirectory, withIntermediateDirectories: true)
            try fm.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try settings.launchAgentData(executable: installedExecutable,
                log: logDirectory.appendingPathComponent("cleanup-desktop-screenshots.log").path)
            if wasLoaded { _ = try Command.run("/bin/launchctl", ["bootout", "\(domain)/\(label)"]) }
            do {
                if settings.enabled {
                    try data.write(to: plist, options: .atomic)
                    _ = try Command.run("/bin/launchctl", ["bootstrap", domain, plist.path])
                } else if fm.fileExists(atPath: plist.path) {
                    try fm.removeItem(at: plist)
                }
                try store.save(settings)
            } catch {
                let original = error
                do {
                    if isLoaded() { _ = try Command.run("/bin/launchctl", ["bootout", "\(domain)/\(label)"]) }
                    if let oldData { try oldData.write(to: plist, options: .atomic) }
                    else if fm.fileExists(atPath: plist.path) { try fm.removeItem(at: plist) }
                    if wasLoaded { _ = try Command.run("/bin/launchctl", ["bootstrap", domain, plist.path]) }
                } catch {
                    throw CleanupError.command("Schedule update failed: \(original.localizedDescription) Previous schedule could not be restored: \(error.localizedDescription)")
                }
                throw original
            }
        }
    }
}
