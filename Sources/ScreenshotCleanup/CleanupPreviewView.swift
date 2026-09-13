import SwiftUI
import CleanupCore

struct CleanupPreviewView: View {
    let review: CleanupPreview
    let confirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var acknowledged = false

    private var trashCount: Int { review.candidates.filter { $0.action == .trash }.count }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(review.approvalRule == nil ? "Review cleanup" : "Approve automatic cleanup")
                .font(.system(size: 23, weight: .semibold, design: .rounded))
            if let rule = review.approvalRule {
                Text("\(rule.name) will run without asking at your scheduled times. It can move up to \(rule.maxAutomaticFiles) files per run, including future matches. Above that limit, the run pauses for review.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Text("Only approve a folder whose matching files you can afford to lose. Keep photo albums and irreplaceable files out of automatic rules.")
                    .font(.system(size: 12)).foregroundStyle(Theme.warning)
            } else {
                Text("Confirm these files before continuing. If the matching files or saved rules change, cleanup stops and asks you to review again.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Text("\(trashCount) to Trash · \(review.candidates.count - trashCount) to file")
                .font(.system(size: 14, weight: .semibold))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if review.candidates.isEmpty {
                        Text("No files currently match. Approval still allows future matches.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    ForEach(review.candidates) { candidate in
                        VStack(alignment: .leading, spacing: 5) {
                            Label(candidate.action == .trash ? "Move to Trash" : "Move to folder", systemImage: candidate.action == .trash ? "trash" : "folder")
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
                            Text(candidate.url.path).font(.system(size: 12)).textSelection(.enabled)
                            if let destination = candidate.destinationDirectory {
                                Text("To: \(destination.path)").font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                            Divider()
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
            }.frame(minHeight: 180, maxHeight: 320).background(Theme.canvas, in: RoundedRectangle(cornerRadius: 10))
            Text("The app never empties Trash. Files remain recoverable until you or macOS empty it.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Toggle(review.approvalRule == nil ? "I've reviewed these files and want to move them." : "I approve this rule for future automatic runs.", isOn: $acknowledged)
                .font(.system(size: 12))
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(review.approvalRule == nil ? "Move reviewed files" : "Approve rule") { confirm() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!acknowledged || (review.approvalRule == nil && review.candidates.isEmpty))
            }
        }.padding(26).frame(width: 620).tint(Theme.accent)
    }
}
