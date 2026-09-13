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
    public var automaticApproval: String?
    public var maxAutomaticFiles: Int
    public var ageHours: Int

    public init(id: UUID = UUID(), name: String, enabled: Bool = true, sourcePath: String,
                archivePath: String? = nil, extensions: [String] = ["png"],
                prefixes: [String] = ["Screenshot ", "Screen Shot "], ageHours: Int = 24, automaticApproval: String? = nil, maxAutomaticFiles: Int = 25) {
        self.automaticApproval = automaticApproval; self.maxAutomaticFiles = maxAutomaticFiles
        self.id = id; self.name = name; self.enabled = enabled; self.sourcePath = sourcePath
        self.archivePath = archivePath; self.extensions = extensions; self.prefixes = prefixes; self.ageHours = ageHours
    }
    public static func screenshots(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> CleanupRule {
        let source = home.appendingPathComponent("Desktop", isDirectory: true)
        var rule = CleanupRule(id: UUID(uuidString: "B45C777D-1327-4983-ACDC-61A6AC036EEF")!, name: "Screenshots",
                           sourcePath: source.path, archivePath: source.appendingPathComponent("Screenshots").path)
        rule.automaticApproval = rule.approvalSignature
        return rule
    }
    public var approvalSignature: String {
        let fields: [String: Any] = ["source": sourcePath, "archive": archivePath as Any? ?? NSNull(),
            "extensions": extensions, "prefixes": prefixes, "ageHours": ageHours, "maxAutomaticFiles": maxAutomaticFiles]
        // All values are JSON primitives, so serialization cannot fail.
        let data = try! JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
    public var allowsAutomaticCleanup: Bool { automaticApproval == approvalSignature }

    private enum CodingKeys: String, CodingKey {
        case id, name, enabled, sourcePath, archivePath, extensions, prefixes, ageHours, automaticApproval, maxAutomaticFiles
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        enabled = try values.decode(Bool.self, forKey: .enabled)
        sourcePath = try values.decode(String.self, forKey: .sourcePath)
        archivePath = try values.decodeIfPresent(String.self, forKey: .archivePath)
        extensions = try values.decode([String].self, forKey: .extensions)
        prefixes = try values.decode([String].self, forKey: .prefixes)
        ageHours = try values.decode(Int.self, forKey: .ageHours)
        maxAutomaticFiles = try values.decodeIfPresent(Int.self, forKey: .maxAutomaticFiles) ?? 25
        automaticApproval = try values.decodeIfPresent(String.self, forKey: .automaticApproval)
        if !values.contains(.automaticApproval) {
            let original = Self.screenshots()
            if id == original.id && sourcePath == original.sourcePath && archivePath == original.archivePath &&
                extensions == original.extensions && prefixes == original.prefixes && ageHours == 24 && maxAutomaticFiles == 25 {
                automaticApproval = approvalSignature
            }
        }
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encode(enabled, forKey: .enabled)
        try values.encode(sourcePath, forKey: .sourcePath)
        try values.encodeIfPresent(archivePath, forKey: .archivePath)
        try values.encode(extensions, forKey: .extensions)
        try values.encode(prefixes, forKey: .prefixes)
        try values.encode(ageHours, forKey: .ageHours)
        try values.encode(maxAutomaticFiles, forKey: .maxAutomaticFiles)
        try values.encode(automaticApproval, forKey: .automaticApproval)
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
              (1...1000).contains(maxAutomaticFiles), (1...8760).contains(ageHours), !extensions.isEmpty,
              extensions.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains) }),
              prefixes.allSatisfy({ !$0.isEmpty && !$0.contains("/") && !$0.contains("\0") }) else {
            throw CleanupError.command("\(name.isEmpty ? "New rule" : name): choose a source folder, file extensions, and an age from 1 to 8,760 hours, with an automatic limit from 1 to 1,000 files. Name prefixes cannot contain slashes.")
        }
        if let archivePath {
            guard archivePath.hasPrefix("/"), archivePath != "/", !archivePath.contains("\0"),
                  archive!.standardizedFileURL.resolvingSymlinksInPath() != source.standardizedFileURL.resolvingSymlinksInPath() else {
                throw CleanupError.command("\(name): choose a different folder for newer files.")
            }
        }
    }
}
