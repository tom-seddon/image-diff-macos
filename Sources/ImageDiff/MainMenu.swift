import AppKit

/// The menu bar. Window commands are sent to the first responder, which reaches MainWindowController
/// as the window's delegate.
enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Image Diff", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Image Diff", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Image Diff", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        add(appMenu, title: "Image Diff", to: main)

        let file = NSMenu(title: "File")
        file.addItem(item("Choose Left Image…", #selector(MainWindowController.chooseLeft(_:)), "o"))
        file.addItem(item("Choose Right Image…", #selector(MainWindowController.chooseRight(_:)), "o", [.command, .shift]))
        file.addItem(.separator())
        file.addItem(item("Compare / Reload", #selector(MainWindowController.compare(_:)), "r"))
        file.addItem(item("Swap Left and Right", #selector(MainWindowController.swap(_:)), "x", [.command, .shift]))
        file.addItem(.separator())
        file.addItem(item("Save Difference…", #selector(MainWindowController.saveDifference(_:)), "s"))
        file.addItem(.separator())
        file.addItem(item("Close Window", #selector(NSWindow.performClose(_:)), "w"))
        add(file, title: "File", to: main)

        // Standard editing commands, so cut, copy and paste work in the path boxes.
        let edit = NSMenu(title: "Edit")
        edit.addItem(item("Undo", Selector(("undo:")), "z"))
        edit.addItem(item("Redo", Selector(("redo:")), "z", [.command, .shift]))
        edit.addItem(.separator())
        edit.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        edit.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        edit.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        edit.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        add(edit, title: "Edit", to: main)

        let view = NSMenu(title: "View")
        view.addItem(item("Difference", #selector(MainWindowController.showDifference(_:)), ""))
        view.addItem(item("Flip", #selector(MainWindowController.showFlip(_:)), ""))
        view.addItem(item("Switch Left/Right", #selector(MainWindowController.flip(_:)), ""))
        view.addItem(.separator())
        view.addItem(item("Zoom to Fit", #selector(MainWindowController.zoomToFit(_:)), "0"))
        view.addItem(item("Actual Size", #selector(MainWindowController.zoomToActualSize(_:)), "1"))
        view.addItem(item("Zoom In", #selector(MainWindowController.zoomIn(_:)), "="))
        view.addItem(item("Zoom Out", #selector(MainWindowController.zoomOut(_:)), "-"))
        view.addItem(.separator())
        view.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        add(view, title: "View", to: main)

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        add(window, title: "Window", to: main)
        NSApp.windowsMenu = window

        return main
    }

    private static func item(_ title: String, _ action: Selector, _ key: String,
                             _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private static func add(_ menu: NSMenu, title: String, to main: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        main.addItem(item)
    }
}
