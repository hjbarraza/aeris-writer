import AppKit

// Classic AppKit entry point (see ADR-001: AppKit-primary, no SwiftUI App lifecycle).
let app = NSApplication.shared
// First instance becomes NSDocumentController.shared: must precede any use of .shared.
_ = AerisDocumentController()
let delegate = AppDelegate()
app.delegate = delegate
// `--selfcheck` (debug builds) runs headless: never shown in the Dock, never activated.
#if DEBUG
let selfCheck = CommandLine.arguments.contains("--selfcheck")
#else
let selfCheck = false
#endif
app.setActivationPolicy(selfCheck ? .prohibited : .regular)
if !selfCheck { app.activate(ignoringOtherApps: true) }
app.run()
