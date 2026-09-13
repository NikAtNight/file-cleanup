import AppKit
import SwiftUI
import CleanupCore

@MainActor final class AppModel: ObservableObject {
    @Published var candidates: [Candidate] = []
    @Published var history: [RunResult] = []
    @Published var settings = CleanupCore.Settings()
    @Published var savedSettings = CleanupCore.Settings()
    @Published var running = false
    @Published var refreshing = false
    @Published var saving = false
    @Published var connecting = false
    @Published var scheduleLoaded = false
    @Published var finderConnected = false
    @Published var message: String?
    @Published var errorMessage: String?
    @Published var selectedPage = "Overview"
    @Published var loaded = false

    var trashCount: Int { candidates.filter { $0.action == .trash }.count }
    var fileCount: Int { candidates.filter { $0.action == .file }.count }
    var busy: Bool { running || saving || connecting }
    var nextRun: Date? { scheduleLoaded ? savedSettings.nextRun() : nil }

    func refresh() {
        guard !refreshing, !busy else { return }
        refreshing = true
        DispatchQueue.global(qos: .userInitiated).async {
            let scan = AppServices.engine.scan()
            let settings = Result { try AppServices.store().settings() }
            let history = Result { try AppServices.store().history() }
            let loaded = ScheduleService.isLoaded()
            Task { @MainActor in
                self.refreshing = false
                self.candidates = scan.candidates
                self.scheduleLoaded = loaded
                var errors = scan.errors
                switch settings {
                case .success(let value):
                    if !self.loaded { self.settings = value; self.loaded = true }
                    self.savedSettings = value
                case .failure(let error): errors.append("Settings: \(error.localizedDescription)")
                }
                switch history {
                case .success(let value): self.history = value
                case .failure(let error): errors.append("History: \(error.localizedDescription)")
                }
                if !errors.isEmpty { self.errorMessage = errors.joined(separator: "\n") }
            }
        }
    }

    func clean() {
        guard !busy, !refreshing else { return }
        running = true
        message = nil
        errorMessage = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try AppServices.clean(trigger: "Manual") }
            Task { @MainActor in
                self.running = false
                switch result {
                case .success(let run):
                    if run.trashed > 0 { self.finderConnected = true }
                    self.message = "Moved \(run.trashed) to Trash · Filed \(run.filed)"
                    if !run.errors.isEmpty {
                        self.errorMessage = "\(run.errors.count) item(s) need attention. Open Activity for details. If Finder access was denied, allow Screenshot Cleanup → Finder in System Settings → Privacy & Security → Automation."
                    }
                case .failure(let error): self.errorMessage = error.localizedDescription
                }
                self.refresh()
            }
        }
    }

    func connectFinder() {
        guard !busy, !refreshing else { return }
        connecting = true
        errorMessage = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try FinderTrash.connect() }
            Task { @MainActor in
                self.connecting = false
                switch result {
                case .success:
                    self.finderConnected = true
                    self.message = "Finder is connected. Cleanup can move screenshots to Trash."
                case .failure(let error):
                    self.errorMessage = "Finder access failed. In System Settings → Privacy & Security → Automation, enable Finder under Screenshot Cleanup. \(error.localizedDescription)"
                }
            }
        }
    }

    func saveSchedule() {
        guard !busy, !refreshing else { return }
        let proposed = settings
        saving = true
        errorMessage = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try ScheduleService.apply(proposed) }
            Task { @MainActor in
                self.saving = false
                switch result {
                case .success:
                    self.savedSettings = proposed
                    self.scheduleLoaded = proposed.enabled
                    self.message = proposed.enabled ? "Daily schedule saved." : "Automatic cleanup is paused."
                case .failure(let error): self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
