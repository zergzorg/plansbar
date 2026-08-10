import AppKit
import Darwin
import Foundation

let app = NSApplication.shared
let arguments = CommandLine.arguments

if let option = arguments.firstIndex(of: "--render-marketing-preview"), option + 1 < arguments.count {
    let outputURL = URL(fileURLWithPath: arguments[option + 1])
    let mode = arguments.firstIndex(of: "--marketing-mode").flatMap { index in
        index + 1 < arguments.count ? arguments[index + 1] : nil
    } ?? "focus"
    app.setActivationPolicy(.prohibited)
    Task { @MainActor in
        do {
            try MarketingPreviewRenderer.render(to: outputURL, mode: mode)
            exit(0)
        } catch {
            fputs("Unable to render marketing preview: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
    app.run()
} else {
    let delegate = AppDelegate()
    app.delegate = delegate
    // PlansBar lives in the menu bar and does not need a Dock icon.
    app.setActivationPolicy(.accessory)
    app.run()
}
