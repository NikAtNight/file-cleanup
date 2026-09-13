# File Cleanup

A native macOS Swift app. Keep cleanup policy in `Sources/CleanupCore`; keep Finder, launchd, and UI integration in `Sources/ScreenshotCleanup`.

- Apply the installed unslop skill to user-facing prose.
- Run `swift test` after changes and `bash scripts/build.sh` before installing.
- Use temporary directories and an injected trash operation in tests. Do not touch real user folders during automated tests.
- Never permanently delete user files. Use one Finder Trash batch per run and preserve collision handling for filed screenshots.
- Manual and scheduled runs must share the process lock and history format.
- Preserve literal filename-prefix whitespace and migrate old settings without broadening rules.
- Preserve the bundle identifier and LaunchAgent label so updates replace the existing installation.
- UI startup must not perform cleanup. Scheduled invocation must not open a window.
- Update `docs/flows/cleanup.md` when behavior changes. Keep local screenshots and run logs in ignored `artifacts/`.
