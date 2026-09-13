# Screenshot cleanup workflow

## Requirement source and owner

Owner: Nikhil. Requested on 2026-09-13: fix the existing cleanup app, create a GitHub repository under `~/Talix`, add a settings window with editable automation times and a manual trigger. This repository owns the implementation formerly in Argus `cron/`.

## Intended behavior

Opening the app displays Overview. Cleanup starts only from Clean up now or the LaunchAgent’s `--scheduled` invocation. Screenshots with modification dates strictly older than 24 hours go to Trash; newer screenshots on Desktop move to Desktop/Screenshots. Existing destination files remain intact. Individual scan, Trash, or filing failures do not stop unrelated files.

Schedule changes affect the existing LaunchAgent, with initial times 09:30 and 10:00. Disabling the schedule unloads the job and removes its plist. The app records up to 30 manual and scheduled results. This is a single-user local app with no server, telemetry, or account system.

## Implementation path

- `Main.main`: separates window startup, dry run, schedule installation, and scheduled execution.
- `AppModel`: independently loads preview, settings, history, and schedule status. It runs file operations off the UI thread and blocks concurrent UI operations.
- `CleanupEngine.scan` → `ScanResult`: collects valid candidates and contextual errors from both directories.
- `AppServices.clean` → `RunLock` → `CleanupEngine.run`: holds a shared filesystem lock through cleanup and history persistence.
- `FinderTrash.trash`: passes a filename as a separate osascript argument, converts it to an alias, and asks Finder to trash it. File content and names are never interpolated into AppleScript code.
- `Store`: validates settings and atomically writes settings and history.
- `ScheduleService.apply`: validates the proposed schedule, holds the cleanup lock, replaces the job, and restores the previous plist/job on failure.

## Permissions and recovery

The app needs Desktop access and permission to control Finder. Check access requests Finder control without moving a file. Denials appear in the UI. Scheduled failures appear in Activity and the scheduled log. The app does not request Full Disk Access.

Finder is required because the original FileManager Trash call failed with Cocoa error 513 on iCloud-managed originals. Finder successfully trashed the same file. A FileManager Trash-directory lookup returned a nonexistent Desktop/.Trash, while Finder used Library/Mobile Documents/.Trash. This is observed behavior on this Mac, not a claim about every macOS installation.

Quitting is blocked while cleanup or schedule updates are active. Closing the window during an operation leaves the app running. The next run rescans actual files, so already-completed items are not processed again. Installation backups preserve the previous app and schedule under Application Support. No test or build artifact contains user screenshots in Git.

## Verification

Environment: macOS 26, Apple silicon, Swift 6.3.3, Xcode 26.6.

- PASS: `swift test`, 17 tests. Covers age boundary, screenshot filtering, excluded symlinks/directories, refused Screenshots folder symlinks, filename collisions, failure continuation, scan failures, idempotency, process lock, settings validation, next-run dates, LaunchAgent arguments, persistence errors, and history limit.
- PASS: `bash scripts/install.sh` built, verified the signature, backed up the previous app, and installed the existing daily schedule with `--scheduled`.
- PASS: app window opened; Check access succeeded and macOS recorded Screenshot Cleanup → Finder approval.
- Initial manual integration test found a Finder AppleScript alias-coercion error. Corrected before final validation. The failed run remains in local Activity as evidence.
- PASS: final manual UI run moved 61 remaining old screenshots to Trash with zero errors. The preceding integration run filed the two recent screenshots. Finder alias coercion was also verified separately on one old screenshot.
- PASS: `launchctl kickstart gui/501/com.nikhlkapadia.cleanup-desktop-screenshots`; job exited 0 and recorded a Scheduled result with no remaining work. No app window appeared during the background run. A future wall-clock wake/sleep run has not been observed.
- PASS: UI pause/save removed and unloaded the LaunchAgent; enable/save restored it. Changed the first time to 10:30 in the UI and verified both settings JSON and plist, then restored 09:30. Defaults remain 09:30 and 10:00, enabled.
- PASS: final native window captures in `docs/screenshots/` show Overview and Schedule. Check access approval was recorded for the installed app and Finder.
- PASS: shell syntax, plist validation, code signature validation, and Git whitespace checks.
- Repository: private `NikAtNight/screenshot-cleanup`. Source publication verification is recorded in Git and the final task report.

Test code: `Tests/CleanupCoreTests/`. Local validation captures are stored in ignored `artifacts/`. The initial source commit can be identified from Git history; this record does not embed a self-referential commit hash.
