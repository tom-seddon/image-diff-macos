import AppKit
import ImageDiffCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let arguments: [String]
    private var windowController: MainWindowController?
    private var pendingFiles: [URL] = []

    init(arguments: [String]) {
        self.arguments = arguments
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let options: CommandLineOptions
        do {
            options = try Arguments.parse(arguments)
        } catch {
            showAlert(title: "Image Diff", text: "\(error)", usage: Arguments.guiUsage, style: .warning)
            exit(2)
        }

        if options.showHelp {
            showAlert(title: "Image Diff \(AppVersion.current)", text: "", usage: Arguments.guiUsage, style: .informational)
            exit(0)
        }

        let controller = MainWindowController(options: options)
        windowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

        if !pendingFiles.isEmpty {
            controller.openFiles(pendingFiles)
            pendingFiles = []
        }
    }

    /// Files opened from Finder: dropped on the Dock icon, or Open With.
    func application(_ application: NSApplication, open urls: [URL]) {
        if let controller = windowController {
            controller.openFiles(urls)
        } else {
            pendingFiles += urls
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func showAlert(title: String, text: String, usage: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.alertStyle = style
        // The usage text lines up in columns, so show it in a fixed-width font.
        let usageField = NSTextField(labelWithString: usage)
        usageField.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        usageField.sizeToFit()
        alert.accessoryView = usageField
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
