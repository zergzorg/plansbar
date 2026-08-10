import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// PlansBar lives in the menu bar and does not need a Dock icon.
app.setActivationPolicy(.accessory)
app.run()
