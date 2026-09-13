import AppKit
import SwiftUI
import CleanupCore

enum SettingsSection: Sendable { case schedule, rules, appearance }

struct CleanupPreview: Identifiable {
    let id = UUID()
    let rules: [CleanupRule]
    let candidates: [Candidate]
    let approvalRule: CleanupRule?
}

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
    @Published var preview: CleanupPreview?

    var trashCount: Int { candidates.filter { $0.action == .trash }.count }
    var fileCount: Int { candidates.filter { $0.action == .file }.count }
    var busy: Bool { running || saving || connecting }
    var nextRun: Date? { scheduleLoaded ? savedSettings.nextRun() : nil }

    func refresh() {
        guard !refreshing, !busy, preview == nil else { return }
        refreshing = true
        DispatchQueue.global(qos: .userInitiated).async {
            let settings = Result { try AppServices.store().settings() }
            let scan = (try? settings.get()).map { AppServices.engine(settings: $0).scan() } ?? ScanResult()
            let history = Result { try AppServices.store().history() }
            let loaded = ScheduleService.isLoaded()
            Task { @MainActor in
                self.refreshing = false
                self.candidates = scan.candidates
                self.scheduleLoaded = loaded
                var errors = scan.errors
                switch settings {
                case .success(let value):
                    if !self.loaded { self.settings = value; self.loaded = true; self.applyAppearance(value.appearance) }
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

    func reviewCleanup(rule: CleanupRule? = nil) {
        guard !busy, !refreshing else { return }
        let rules = rule.map { [$0] } ?? savedSettings.rules
        var scanRules = rules
        if rule != nil { scanRules[0].enabled = true }
        refreshing = true
        errorMessage = nil
        let engine = CleanupEngine(rules: scanRules)
        DispatchQueue.global(qos: .userInitiated).async {
            let scan = engine.scan()
            Task { @MainActor in
                self.refreshing = false
                if scan.errors.isEmpty {
                    self.preview = CleanupPreview(rules: rules, candidates: scan.candidates, approvalRule: rule)
                } else { self.errorMessage = scan.errors.joined(separator: "\n") }
            }
        }
    }

    func confirmPreview(_ review: CleanupPreview) {
        preview = nil
        if let rule = review.approvalRule {
            guard let index = settings.rules.firstIndex(where: { $0.id == rule.id }), settings.rules[index] == rule else {
                errorMessage = "The rule changed. Preview it again before enabling automatic cleanup."
                return
            }
            settings.rules[index].automaticApproval = rule.approvalSignature
            message = "Automatic cleanup approved for \(rule.name). Save rules to apply."
        } else { clean(review: review) }
    }

    private func clean(review: CleanupPreview) {
        guard !busy, !refreshing else { return }
        running = true
        message = nil
        errorMessage = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try AppServices.clean(trigger: "Manual", review: review) }
            Task { @MainActor in
                self.running = false
                switch result {
                case .success(let run):
                    if run.trashed > 0 { self.finderConnected = true }
                    self.message = "Moved \(run.trashed) to Trash · Filed \(run.filed)"
                    if !run.errors.isEmpty {
                        self.errorMessage = run.errors.joined(separator: "\n")
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
                    self.message = "Finder is connected. Cleanup can move matching files to Trash."
                case .failure(let error):
                    self.errorMessage = "Finder access failed. In System Settings → Privacy & Security → Automation, enable Finder under File Cleanup. \(error.localizedDescription)"
                }
            }
        }
    }

    func applyAppearance(_ preference: AppearancePreference) {
        switch preference {
        case .system: NSApplication.shared.appearance = nil
        case .light: NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .dark: NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
    }
    func saveSchedule() { saveChanges(.schedule) }
    func saveChanges(_ section: SettingsSection) {
        guard !busy, !refreshing else { return }
        var proposed = savedSettings
        switch section {
        case .schedule: proposed.enabled = settings.enabled; proposed.times = settings.times
        case .rules: proposed.rules = settings.rules
        case .appearance: proposed.appearance = settings.appearance
        }
        let toSave = proposed
        saving = true
        errorMessage = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try ScheduleService.apply(toSave) }
            Task { @MainActor in
                self.saving = false
                switch result {
                case .success:
                    self.savedSettings = toSave
                    self.scheduleLoaded = toSave.enabled
                    switch section {
                    case .schedule: self.message = toSave.enabled ? "Daily schedule saved." : "Automatic cleanup is paused."
                    case .rules: self.message = "Cleanup rules saved. Overview now previews these rules."
                    case .appearance: self.message = "Appearance saved."
                    }
                    self.refresh()
                case .failure(let error): self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
