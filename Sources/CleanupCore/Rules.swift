import Foundation

public enum AppearancePreference: String, Codable, CaseIterable, Sendable {
    case system, light, dark
}

public struct CleanupRule: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var enabled: Bool
    public var sourcePath: String
    public var archivePath: String?
    public var extensions: [String]
    public var prefixes: [String]
    public var ageHours: Int

    public init(id: UUID = UUID(), name: String, enabled: Bool = true, sourcePath: String,
                archivePath: String? = nil, extensions: [String] = ["png"],
                prefixes: [String] = ["Screenshot ", "Screen Shot "], ageHours: Int = 24) {
        self.id = id; self.name = name; self.enabled = enabled; self.sourcePath = sourcePath
        self.archivePath = archivePath; self.extensions = extensions; self.prefixes = prefixes; self.ageHours = ageHours
    }
    public static func screenshots(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> CleanupRule {
        let source = home.appendingPathComponent("Desktop", isDirectory: true)
        return CleanupRule(id: UUID(uuidString: "B45C777D-1327-4983-ACDC-61A6AC036EEF")!, name: "Screenshots",
                           sourcePath: source.path, archivePath: source.appendingPathComponent("Screenshots").path)
    }
    public var source: URL { URL(fileURLWithPath: sourcePath, isDirectory: true) }
    public var archive: URL? { archivePath.map { URL(fileURLWithPath: $0, isDirectory: true) } }
    public func matches(_ url: URL) -> Bool {
        extensions.contains(where: { $0.lowercased() == url.pathExtension.lowercased() }) &&
        (prefixes.isEmpty || prefixes.contains(where: { url.lastPathComponent.hasPrefix($0) }))
    }
    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              sourcePath.hasPrefix("/"), sourcePath != "/", !sourcePath.contains("\0"),
              (1...8760).contains(ageHours), !extensions.isEmpty,
              extensions.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains) }),
              prefixes.allSatisfy({ !$0.isEmpty && !$0.contains("/") && !$0.contains("\0") }) else {
            throw CleanupError.command("\(name.isEmpty ? "New rule" : name): choose a source folder, file extensions, and an age from 1 to 8,760 hours. Name prefixes cannot contain slashes.")
        }
        if let archivePath {
            guard archivePath.hasPrefix("/"), archivePath != "/", !archivePath.contains("\0"),
                  archive!.standardizedFileURL.resolvingSymlinksInPath() != source.standardizedFileURL.resolvingSymlinksInPath() else {
                throw CleanupError.command("\(name): choose a different folder for newer files.")
            }
        }
    }
}
