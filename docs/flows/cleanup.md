# File cleanup workflow

## Requirement source and owner

Owner: Nikhil. Requested on 2026-09-13: fix the screenshot cleanup app and add a native window, manual trigger, daily schedule, and GitHub repository under Talix. The follow-up requested configurable folders and file rules, dark mode, general file-oriented copy, the name File Cleanup, and an end to repeated per-file Trash sounds.

## Intended behavior

Opening the app shows Overview without modifying files. A saved rule specifies a source folder, extensions, literal filename prefixes, an age threshold in hours, and an optional folder for newer matches. Only regular, nonhidden, nonsymlink files directly inside the selected folders qualify. Newer files stay put unless a destination is configured. Older matches from all enabled rules enter one Finder Trash batch. Existing destination files remain intact.

Rules cannot share a folder. Duplicate ownership is rejected before scanning or saving. The engine rejects user-created symlink folders and ancestors; the macOS /var and /tmp system redirects are allowed for temporary directories. The original screenshot rule remains the default and migration fallback. No rule is broadened during migration.

System, Light, and Dark appearance are available. Each editor saves its own settings section. Unsaved rule changes cannot be activated by saving appearance or schedule changes. The default daily times remain 09:30 and 10:00. Closing the window does not disable the LaunchAgent.

## Implementation path

- `Settings.init(from:)` migrates older JSON with default rules and System appearance. `Settings.validate` checks rules, directory ownership, times, and unique IDs.
- `CleanupRule` defines matching and age/location configuration. `CleanupEngine.scan` returns candidates plus contextual errors. Folder scan failures do not hide settings or stop unrelated readable folders.
- `AppServices.clean` holds `RunLock` across cleanup and history persistence. Both manual and scheduled entry points construct the engine from saved rules.
- `FinderTrash.trash` resolves arguments into aliases and asks Finder to delete all accessible files once. It returns `TrashBatchResult` with confirmed count and skipped-file errors. Paths never enter AppleScript source. Finder-level failure warns that some files may already have moved, without per-file retries.
- `AppModel.saveChanges` merges only the chosen settings section into saved settings. `ScheduleService.apply` serializes updates with cleanup, replaces the LaunchAgent, and rolls back on failure.
- `Theme` supplies adaptive colors shared by the main window and rule editor. `AppModel.applyAppearance` sets the application appearance, including native title bars.
- Installation renames the app to File Cleanup while preserving the bundle identifier, executable name, LaunchAgent label, and Application Support directory.

## Permissions and recovery

File Cleanup needs access to selected protected folders and permission to control Finder. The folder picker selects actual folder paths. Check access requests Finder control without moving a file. Denials are visible in the window; scheduled errors appear in Activity and the log. No Full Disk Access or global sound changes are requested.

Finder is used because FileManager Trash failed on iCloud-managed originals on this Mac while Finder succeeded. Finder’s scripting dictionary has no silent delete option. One batch replaces repeated per-file operations, but one system Trash sound may remain.

Quitting is blocked during cleanup or saving. Closing the window leaves an active operation running. The next run rescans files. History stores the latest 30 results. Installation backups retain the previous app and schedule.

## Verification

Environment: macOS 26, Apple silicon, Swift 6.3.3, Xcode 26.6.

- PASS: 26 XCTest cases in `Tests/CleanupCoreTests`. Coverage includes legacy migration, custom rules, filename whitespace semantics, age boundaries, extensions, missing directories, source/archive symlinks, broken-symlink collisions, batch partial results, idempotency, process locks, persistence errors, and schedule serialization.
- PASS: exact Finder batch script with generated temporary files: one file, multiple files with quotes/Unicode/newlines, mixed valid/missing files, and all missing. Missing items do not prevent the valid batch.
- PASS: installed LaunchAgent with an isolated temporary rule trashed three matching old TXT files in one batch, preserved recent and unrelated files, and recorded a result with zero errors. The original settings were restored immediately afterward. No real user files were used for this integration check.
- PASS: installation migrated Screenshot Cleanup to File Cleanup and preserved default prefix whitespace, 24-hour age, 09:30/10:00 schedule, and stored history.
- PASS: native Light and Dark appearance selected through the UI; saved Dark survived quitting and reopening.
- PASS: edited the age field through the UI, saved 48 hours, verified persisted rules, then restored 24 hours. Original literal prefix spaces remained intact.
- Earlier release verification: manual cleanup of real screenshot backlog, schedule pause/resume, edited time reflected in the LaunchAgent, and background completion without a window.
- NOT RUN: audible recording measurement, future wall-clock wake/sleep run, and installation on a second Mac. One Finder operation is verified; complete silence is not claimed.

Native captures are in `docs/screenshots`. Local execution logs and temporary validation artifacts are ignored under `artifacts/`. The source and checks are recorded in Git; this document avoids a self-referential commit hash.
