import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let defaultPanelHeight: CGFloat = 520
    private let minimumPanelHeight: CGFloat = 300
    private let panelHeightKey = "panelHeight"

    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private var client: IndexClient!
    private var preferences: Preferences!
    private var agentPreferences: AgentPreferences!
    private var accessStore: RepositoryAccessStore!
    private var cancellables: Set<AnyCancellable> = []
    private var clickMonitor: Any?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        preferences = Preferences()
        agentPreferences = AgentPreferences()
        accessStore = RepositoryAccessStore()
        client = IndexClient(accessStore: accessStore)

        setupStatusItem()
        setupPanel()
        setupKeyboardShortcuts()
        observeState()
        Task { await client.refresh() }
    }

    // MARK: - Строка меню

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "checklist",
            accessibilityDescription: "Plans"
        )
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.action = #selector(togglePanel)
        statusItem.button?.target = self
    }

    /// Счётчик у иконки — то, ради чего приложение и живёт в строке меню:
    /// состояние работы видно без открытия панели.
    private func observeState() {
        client.$snapshot
            .combineLatest(preferences.$hidden)
            .sink { [weak self] snapshot, hidden in
                guard let self else { return }
                let tasks = snapshot.repositories
                    .filter { !hidden.contains($0.id) }
                    .flatMap(\.tasks)
                    .filter(\.isActive)
                let attention = tasks.filter(\.needsAttention).count
                self.statusItem.button?.title = attention > 0 ? " \(attention)" : ""
            }
            .store(in: &cancellables)
    }

    // MARK: - Панель

    private func setupPanel() {
        let content = PanelView(
            client: client,
            preferences: preferences,
            agentPreferences: agentPreferences,
            accessStore: accessStore
        )
        let hosting = NSHostingController(rootView: content)

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: PanelView.width, height: defaultPanelHeight),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.delegate = self
        panel.contentViewController = hosting
        panel.contentMinSize = NSSize(width: PanelView.width, height: minimumPanelHeight)
        panel.contentMaxSize = NSSize(width: PanelView.width, height: .greatestFiniteMagnitude)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.animationBehavior = .utilityWindow
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
    }

    @objc private func togglePanel() {
        panel.isVisible ? hidePanel() : showPanel()
    }

    private func showPanel() {
        guard let button = statusItem.button,
              let screen = button.window?.screen ?? NSScreen.main else { return }

        let buttonRect = button.window?.convertToScreen(button.convert(button.bounds, to: nil)) ?? .zero
        let maximumHeight = max(
            minimumPanelHeight,
            buttonRect.minY - screen.visibleFrame.minY - 12
        )
        let storedHeight = UserDefaults.standard.double(forKey: panelHeightKey)
        let requestedHeight = storedHeight > 0 ? CGFloat(storedHeight) : defaultPanelHeight
        let height = min(max(requestedHeight, minimumPanelHeight), maximumHeight)

        panel.contentMinSize = NSSize(width: PanelView.width, height: minimumPanelHeight)
        panel.contentMaxSize = NSSize(width: PanelView.width, height: maximumHeight)
        panel.setContentSize(NSSize(width: PanelView.width, height: height))

        let size = panel.frame.size
        var origin = NSPoint(
            x: buttonRect.midX - size.width / 2,
            y: buttonRect.minY - size.height - 6
        )
        // Не даём панели уехать за край экрана на крайних иконках строки меню.
        let maxX = screen.visibleFrame.maxX - size.width - 8
        origin.x = min(max(screen.visibleFrame.minX + 8, origin.x), maxX)

        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hidePanel() }
        }

        Task { await client.refresh() }
    }

    func windowDidResize(_ notification: Notification) {
        guard panel.isVisible else { return }
        UserDefaults.standard.set(panel.contentLayoutRect.height, forKey: panelHeightKey)
    }

    private func hidePanel() {
        panel.orderOut(nil)
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
    }

    private func setupKeyboardShortcuts() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let commandF = modifiers == .command && event.charactersIgnoringModifiers == "f"
            let slash = modifiers.isEmpty
                && event.characters == "/"
                && !(event.window?.firstResponder is NSTextView)
            guard commandF || slash else { return event }
            Task { @MainActor in
                guard let self else { return }
                if !self.panel.isVisible { self.showPanel() }
                NotificationCenter.default.post(name: .focusPlansSearch, object: nil)
            }
            return nil
        }
    }

}

extension Notification.Name {
    static let focusPlansSearch = Notification.Name("focusPlansSearch")
}
