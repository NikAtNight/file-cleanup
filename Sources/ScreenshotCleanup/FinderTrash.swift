import Foundation
import CleanupCore

struct FinderTrash {
    static func connect() throws {
        _ = try Command.run("/usr/bin/osascript", ["-e", "with timeout of 30 seconds\ntell application \"Finder\" to get name of startup disk\nend timeout"])
    }

    static func trash(_ urls: [URL]) throws -> TrashBatchResult {
        guard !urls.isEmpty else { return TrashBatchResult(trashed: 0) }

        // Resolve every argument before deleting. Finder receives one batch, so it
        // does not play its Trash sound separately for every file.
        let script = """
        on run arguments
            set targetFiles to {}
            set skippedIndices to {}
            repeat with argumentIndex from 1 to count of arguments
                try
                    set end of targetFiles to (POSIX file (item argumentIndex of arguments)) as alias
                on error
                    set end of skippedIndices to argumentIndex as text
                end try
            end repeat
            set trashedCount to 0
            if (count of targetFiles) > 0 then
                with timeout of 120 seconds
                    tell application "Finder" to set trashedFiles to (delete targetFiles) as list
                end timeout
                set trashedCount to count of trashedFiles
            end if
            set AppleScript's text item delimiters to ","
            return (trashedCount as text) & "|" & (skippedIndices as text)
        end run
        """
        let output: String
        do {
            // File paths are arguments, never interpolated into AppleScript.
            output = try Command.run("/usr/bin/osascript", ["-e", script] + urls.map(\.path))
        } catch {
            throw CleanupError.command("Finder could not confirm the cleanup batch. Some files may already be in Trash. \(error.localizedDescription)")
        }
        let parts = output.split(separator: "|", omittingEmptySubsequences: false)
        let skippedParts = parts.count == 2 ? parts[1].split(separator: ",", omittingEmptySubsequences: false) : []
        let skipped = parts.count == 2 && parts[1].isEmpty ? [] : skippedParts.compactMap { Int($0) }
        guard parts.count == 2, let count = Int(parts[0]), count >= 0,
              (parts[1].isEmpty || skipped.count == skippedParts.count),
              Set(skipped).count == skipped.count,
              skipped.allSatisfy({ (1...urls.count).contains($0) }),
              count + skipped.count == urls.count else {
            throw CleanupError.command("Finder did not confirm that all \(urls.count) files were moved to Trash. Some files may already be in Trash. Refresh the preview before trying again.")
        }
        return TrashBatchResult(trashed: count, errors: skipped.map {
            "Skipped \(urls[$0 - 1].path): the file could not be accessed. It may have moved or its folder permission may have changed."
        })
    }
}
