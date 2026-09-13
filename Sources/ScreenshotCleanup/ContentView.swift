import SwiftUI
import AppKit
import CleanupCore

private let accent = Theme.accent
private let canvas = Theme.canvas

struct ContentView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if let error = model.errorMessage { notice(error, isError: true) }
                    if let message = model.message { notice(message, isError: false) }
                    switch model.selectedPage {
                    case "Schedule": schedule
                    case "Rules": RulesView(model: model)
                    case "Appearance": appearance
                    case "Activity": activity
                    default: overview
                    }
                }
                .padding(32)
                .frame(maxWidth: 1000, alignment: .leading)
            }
            .background(canvas)
        }
        .tint(accent)
        .onChange(of: model.settings.appearance) { model.applyAppearance($0) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refresh() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 32) {
            HStack(spacing: 10) {
                Image(systemName: "folder").font(.system(size: 24, weight: .semibold)).foregroundStyle(accent)
                    .frame(width: 42, height: 42).background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("File").font(.system(size: 15, weight: .semibold))
                    Text("Cleanup").font(.system(size: 15, weight: .semibold)).foregroundStyle(accent)
                }
            }
            VStack(spacing: 6) {
                navigation("Overview", icon: "square.grid.2x2")
                navigation("Rules", icon: "slider.horizontal.3")
                navigation("Schedule", icon: "clock")
                navigation("Appearance", icon: "circle.lefthalf.filled")
                navigation("Activity", icon: "clock.arrow.circlepath")
            }
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Label(model.scheduleLoaded ? "Automation on" : "Automation off", systemImage: model.scheduleLoaded ? "checkmark.circle.fill" : "pause.circle")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(accent)
                Text("Runs on this Mac while you’re logged in.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            }
            Divider()
            Button { model.selectedPage = "Rules" } label: {
                Label("Manage folders", systemImage: "folder").font(.system(size: 12))
            }.buttonStyle(.plain).foregroundStyle(.secondary)
            Text("FILE CLEANUP  2.1").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 22).padding(.vertical, 30)
        .frame(width: 200)
        .background(Theme.sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.border).frame(width: 1) }
    }

    private func navigation(_ title: String, icon: String) -> some View {
        Button { model.selectedPage = title } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 18)
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer()
            }.padding(.horizontal, 13).padding(.vertical, 12)
                .foregroundStyle(model.selectedPage == title ? accent : .secondary)
                .background(model.selectedPage == title ? accent.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).accessibilityLabel(title)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOUR FILES, IN ORDER").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.7).foregroundStyle(accent)
            HStack(alignment: .center) {
                Text(model.selectedPage == "Overview" ? "File Cleanup" : model.selectedPage)
                    .font(.system(size: 29, weight: .semibold, design: .rounded))
                Spacer()
                if model.selectedPage != "Schedule" {
                    Button { model.refresh() } label: { Image(systemName: "arrow.clockwise").font(.system(size: 14)) }
                        .buttonStyle(.plain).disabled(model.busy || model.refreshing).help("Refresh matching files and recent runs")
                }
            }
            Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }
    private var subtitle: String {
        switch model.selectedPage {
        case "Schedule": return "Choose when your cleanup rules run."
        case "Rules": return "Choose what to clean, where to look, and what to keep."
        case "Appearance": return "Choose how File Cleanup looks on this Mac."
        case "Activity": return "The last 30 runs, including anything that needs attention."
        default: return "Keep what’s useful. Clear what’s ready to go."
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                metric("Ready for Trash", count: model.trashCount, detail: "Past your rules’ age limits", icon: "trash")
                metric("Ready to file", count: model.fileCount, detail: "Move to your chosen folders", icon: "folder")
            }
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: "sparkles").font(.system(size: 24)).foregroundStyle(accent)
                        .frame(width: 48, height: 48).background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 7) {
                        Text(model.running ? "Cleaning up…" : (model.candidates.isEmpty ? "Your folders are up to date" : "Ready when you are"))
                            .font(.system(size: 19, weight: .semibold, design: .rounded))
                        Text("Only files matching your saved rules are included. Items in Trash remain recoverable until it’s emptied.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                    }
                }
                HStack {
                    Button(action: model.clean) {
                        HStack(spacing: 8) {
                            if model.running { ProgressView().controlSize(.small) }
                            else { Image(systemName: "sparkles") }
                            Text(model.running ? "Cleaning up…" : "Clean up now").fontWeight(.semibold)
                        }.padding(.horizontal, 12).padding(.vertical, 7)
                    }.buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(model.busy || model.refreshing || model.candidates.isEmpty || !model.loaded).accessibilityLabel("Clean up now")
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("NEXT AUTOMATIC RUN").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                        if let date = model.nextRun { Text(date, format: .dateTime.weekday(.abbreviated).hour().minute()).font(.system(size: 12, weight: .medium)) }
                        else { Text("Not scheduled").font(.system(size: 12, weight: .medium)) }
                    }
                }
            }.card()
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Upcoming cleanup").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text("\(model.candidates.count) files").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if model.refreshing { ProgressView("Checking your folders…").controlSize(.small) }
                else if model.candidates.isEmpty {
                    Label("No matching files need attention.", systemImage: "checkmark.circle").font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 10)
                } else {
                    ForEach(model.candidates.prefix(5)) { candidate in
                        HStack(spacing: 10) {
                            Image(systemName: "photo").foregroundStyle(.secondary).frame(width: 24)
                            Text(candidate.url.lastPathComponent).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(candidate.action == .trash ? "To Trash" : "To \(candidate.destinationDirectory?.lastPathComponent ?? "folder")")
                                .font(.system(size: 10, weight: .medium)).foregroundStyle(candidate.action == .trash ? Color.secondary : accent)
                                .padding(.horizontal, 8).padding(.vertical, 4).background(canvas, in: Capsule())
                        }
                    }
                    if model.candidates.count > 5 { Text("And \(model.candidates.count - 5) more").font(.system(size: 11)).foregroundStyle(.secondary) }
                }
            }.card()
            finderConnection
        }
    }

    private func metric(_ title: String, count: Int, detail: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary); Spacer(); Image(systemName: icon).foregroundStyle(accent) }
            Text("\(count)").font(.system(size: 38, weight: .medium, design: .rounded)).monospacedDigit()
            Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).card()
    }

    private var finderConnection: some View {
        HStack(spacing: 12) {
            Image(systemName: model.finderConnected ? "checkmark.shield" : "hand.raised").font(.system(size: 20)).foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.finderConnected ? "Finder connected" : "Finder access").font(.system(size: 12, weight: .medium))
                Text("Finder handles local and iCloud files in one Trash operation.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button(model.connecting ? "Connecting…" : "Check access", action: model.connectFinder).disabled(model.busy || model.refreshing).accessibilityLabel("Check Finder access")
        }.card()
    }

    private var schedule: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 22) {
                Toggle(isOn: $model.settings.enabled) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Daily cleanup").font(.system(size: 16, weight: .semibold))
                        Text("Run automatically at the times below.").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }.toggleStyle(.switch)
                Divider()
                ForEach(model.settings.times.indices, id: \.self) { index in
                    HStack {
                        Label("Run \(index + 1)", systemImage: "clock").font(.system(size: 13)).foregroundStyle(.secondary)
                        Spacer()
                        DatePicker("Time", selection: timeBinding(index), displayedComponents: .hourAndMinute).labelsHidden().frame(width: 110)
                        Button {
                            model.settings.times.remove(at: index)
                        } label: { Image(systemName: "minus.circle").foregroundStyle(.secondary) }
                            .buttonStyle(.plain).disabled(model.settings.times.count == 1).help("Remove this run time")
                    }
                }
                Button {
                    for hour in 0..<24 {
                        let candidate = DailyTime(hour: hour, minute: 0)
                        if !model.settings.times.contains(candidate) { model.settings.times.append(candidate); break }
                    }
                } label: { Label("Add a run time", systemImage: "plus") }
                    .buttonStyle(.plain).foregroundStyle(accent).disabled(model.settings.times.count >= 8)
                Divider()
                HStack {
                    Text("\(TimeZone.current.identifier) · Every day").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button(model.saving ? "Saving…" : "Save schedule", action: model.saveSchedule)
                        .buttonStyle(.borderedProminent).disabled(model.busy || model.refreshing || !model.loaded)
                }
                if model.settings.times != model.savedSettings.times || model.settings.enabled != model.savedSettings.enabled { Text("You have unsaved changes.").font(.system(size: 11)).foregroundStyle(.orange) }
            }.card().disabled(model.running || model.saving)
            VStack(alignment: .leading, spacing: 12) {
                Label("What happens at each run", systemImage: "arrow.triangle.2.circlepath").font(.system(size: 14, weight: .semibold))
                Text("1. Find files matching your saved rules.\n2. Move older matches to Trash in a single batch.\n3. File newer matches when a destination is set.\n4. Save the result to Activity.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(8)
                Text("Times follow this Mac’s time zone. macOS may catch up after sleep. The app window can be closed; you need to stay logged in.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
            }.card()
            finderConnection
        }
    }
    private func timeBinding(_ index: Int) -> Binding<Date> {
        Binding(get: {
            guard model.settings.times.indices.contains(index) else { return Date() }
            let time = model.settings.times[index]
            return Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: time.hour, minute: time.minute)) ?? Date()
        }, set: { date in
            guard model.settings.times.indices.contains(index) else { return }
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            model.settings.times[index] = DailyTime(hour: components.hour ?? 0, minute: components.minute ?? 0)
        })
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Color theme").font(.system(size: 16, weight: .semibold))
                Picker("Appearance", selection: $model.settings.appearance) {
                    Text("System").tag(AppearancePreference.system)
                    Text("Light").tag(AppearancePreference.light)
                    Text("Dark").tag(AppearancePreference.dark)
                }.pickerStyle(.segmented)
                Text("System follows your Mac’s appearance. Changes preview immediately; save to keep your choice.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                HStack {
                    Spacer()
                    Button("Save appearance") { model.saveChanges(.appearance) }
                        .buttonStyle(.borderedProminent).disabled(model.busy || model.refreshing || !model.loaded)
                }
            }.card()
        }
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.history.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 32)).foregroundStyle(accent)
                    Text("Your next cleanup starts the history").font(.system(size: 17, weight: .semibold))
                    Text("Manual and scheduled runs will appear here.").font(.system(size: 12)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 35).card()
            }
            ForEach(model.history) { run in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        Image(systemName: run.succeeded ? "checkmark.circle.fill" : "exclamationmark.circle.fill").foregroundStyle(run.succeeded ? accent : .orange)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(run.succeeded ? "Cleanup complete" : "Completed with errors").font(.system(size: 14, weight: .semibold))
                            Text("\(run.trigger) · \(run.trashed) trashed · \(run.filed) filed").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(run.date, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    if !run.errors.isEmpty {
                        DisclosureGroup("\(run.errors.count) error(s)") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(run.errors.enumerated()), id: \.offset) { _, error in
                                    Text(error).font(.system(size: 11)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }.padding(.top, 8)
                        }.font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }.card()
            }
        }
    }
    private func notice(_ text: String, isError: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isError ? "exclamationmark.circle" : "checkmark.circle")
            Text(text).font(.system(size: 12)).textSelection(.enabled).lineSpacing(3)
            Spacer(minLength: 0)
            Button {
                if isError { model.errorMessage = nil } else { model.message = nil }
            } label: { Image(systemName: "xmark").font(.system(size: 10)) }.buttonStyle(.plain)
        }.foregroundStyle(isError ? Theme.warning : accent)
            .padding(14).background(isError ? Color.orange.opacity(0.09) : accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
}
