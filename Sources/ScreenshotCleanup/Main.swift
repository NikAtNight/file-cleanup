import AppKit
import SwiftUI
import CleanupCore

@main enum Main {
    static func main() {
        let arguments = CommandLine.arguments
        if arguments.contains("--dry-run") {
            let scan: ScanResult
            do { scan = AppServices.engine(settings: try AppServices.store().settings()).scan() }
            catch { fail(error) }
            for candidate in scan.candidates {
                print("Would \(candidate.action.rawValue): \(candidate.url.path)")
            }
            for error in scan.errors { FileHandle.standardError.write(Data((error + "\n").utf8)) }
            exit(scan.errors.isEmpty ? 0 : 1)
        }
        if arguments.contains("--install-schedule") {
            do {
                try ScheduleService.apply(AppServices.store().settings())
                print("Schedule installed.")
                exit(0)
            } catch { fail(error) }
        }
        if arguments.contains("--scheduled") {
            do {
                guard try AppServices.store().settings().enabled else { exit(0) }
                let result = try AppServices.clean(trigger: "Scheduled")
                print("\(ISO8601DateFormatter().string(from: result.date)) Trashed: \(result.trashed), filed: \(result.filed), errors: \(result.errors.count)")
                for error in result.errors { print(error) }
                exit(result.succeeded ? 0 : 1)
            } catch { fail(error) }
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
    static func fail(_ error: Error) -> Never {
        FileHandle.standardError.write(Data("Screenshot cleanup failed: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    let model = AppModel()
    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 740),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "File Cleanup"
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 880, height: 640)
        window.contentView = NSHostingView(rootView: ContentView(model: model))
        window.center()
        self.window = window
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About File Cleanup", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit File Cleanup", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        NSApplication.shared.mainMenu = menu
        showWindow()
        model.refresh()
    }
    func showWindow() {
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(); model.refresh(); return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model.busy {
            model.message = "Wait for the current operation to finish before quitting."
            showWindow()
            return .terminateCancel
        }
        return .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !model.busy }
}
