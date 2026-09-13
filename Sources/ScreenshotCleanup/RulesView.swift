import SwiftUI
import AppKit
import CleanupCore

struct RulesView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Each rule checks one source folder and, optionally, the folder where newer files are kept. Subfolders and symbolic links are skipped.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            ForEach($model.settings.rules) { $rule in
                RuleEditor(rule: $rule) { model.settings.rules.removeAll { $0.id == rule.id } }
            }
            HStack {
                Button {
                    model.settings.rules.append(CleanupRule(name: "New rule", sourcePath: "", extensions: ["png"], prefixes: []))
                } label: { Label("Add a rule", systemImage: "plus") }.buttonStyle(.bordered)
                Spacer()
                Button(model.saving ? "Saving…" : "Save rules") { model.saveChanges(.rules) }
                    .buttonStyle(.borderedProminent).disabled(!model.loaded || model.refreshing)
            }
            if model.settings.rules != model.savedSettings.rules {
                Text("Unsaved rules. Cleanup continues to use your saved rules until you save.")
                    .font(.system(size: 11)).foregroundStyle(.orange)
            }
            Label("Files go to Trash in one Finder operation per run. A system Trash sound may play once.", systemImage: "speaker.wave.1")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4).card()
        }.disabled(model.busy)
    }
}

private struct RuleEditor: View {
    @Binding var rule: CleanupRule
    let remove: () -> Void
    @State private var extensionsText: String
    @State private var prefixesText: String
    init(rule: Binding<CleanupRule>, remove: @escaping () -> Void) {
        _rule = rule
        self.remove = remove
        _extensionsText = State(initialValue: rule.wrappedValue.extensions.joined(separator: ", "))
        _prefixesText = State(initialValue: rule.wrappedValue.prefixes.joined(separator: "\n"))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                TextField("Rule name", text: $rule.name).font(.system(size: 17, weight: .semibold)).textFieldStyle(.plain)
                Toggle("Enabled", isOn: $rule.enabled).toggleStyle(.switch).labelsHidden().help("Enable this rule")
                Button(action: remove) { Image(systemName: "minus.circle") }.buttonStyle(.plain).help("Remove rule without changing files")
            }
            Divider()
            folder("Source folder", path: rule.sourcePath) { chooseFolder { rule.sourcePath = $0 } }
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("File extensions").font(.system(size: 12, weight: .medium))
                    TextField("png, jpg, pdf", text: $extensionsText).textFieldStyle(.roundedBorder)
                    Text("Comma-separated. Required; no dots or wildcards.").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text("Name starts with").font(.system(size: 12, weight: .medium))
                    TextEditor(text: $prefixesText).font(.system(size: 12, design: .monospaced)).frame(height: 48).overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.border))
                    Text("One prefix per line. Spaces matter. Leave empty for any name.").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("Move to Trash after").font(.system(size: 12, weight: .medium))
                TextField("Hours", value: $rule.ageHours, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder).frame(width: 75)
                Text("hours since last modification").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
            }
            Toggle("Move newer matches to a separate folder", isOn: Binding(
                get: { rule.archivePath != nil }, set: { rule.archivePath = $0 ? "" : nil }))
                .font(.system(size: 12))
            if let path = rule.archivePath {
                folder("Folder for newer files", path: path) { chooseFolder { rule.archivePath = $0 } }
                Text("Older matches in this folder are also moved to Trash. Existing files are never overwritten.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                Text("Newer files stay in the source folder.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }.card()
        .onChange(of: extensionsText) { rule.extensions = parse($0) }
        .onChange(of: prefixesText) { rule.prefixes = $0.components(separatedBy: .newlines).filter { !$0.isEmpty } }
    }
    private func parse(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    private func folder(_ title: String, path: String, choose: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 12, weight: .medium))
            HStack {
                Image(systemName: "folder").foregroundStyle(Theme.accent)
                Text(path.isEmpty ? "Choose a folder" : path).font(.system(size: 11)).lineLimit(2).textSelection(.enabled)
                Spacer()
                Button("Choose…", action: choose)
            }
        }
    }
    private func chooseFolder(_ completion: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose folder"
        panel.begin { response in
            if response == .OK, let url = panel.url { completion(url.resolvingSymlinksInPath().path) }
        }
    }
}
