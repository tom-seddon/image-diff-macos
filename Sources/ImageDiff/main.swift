import AppKit

// Stop AppKit treating command-line image paths as files to open; the arguments are parsed here.
UserDefaults.standard.register(defaults: ["NSTreatUnknownArgumentsAsOpen": "NO"])

// Finder used to add a process serial number argument; ignore it if it appears.
let arguments = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-psn_") }

let app = NSApplication.shared
let delegate = AppDelegate(arguments: Array(arguments))
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
