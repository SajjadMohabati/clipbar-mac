import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let digitKeys = [
        kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
        kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
    ]

    private let store = ClipStore()
    private let settings = Settings.shared
    private var statusItem: NSStatusItem!
    private var panel: Panel!
    private var editorWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var previousApp: NSRunningApplication?
    private var observers: Set<AnyCancellable> = []
    private var askedForAccessibility = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.load()
        setUpStatusItem()
        setUpPanel()

        HotKey.shared.install { [weak self] in self?.togglePanel() }
        HotKey.shared.register(settings.shortcut)

        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.store.applyLimits() }
            .store(in: &observers)
        store.$paused
            .sink { [weak self] paused in self?.statusItem.button?.appearsDisabled = paused }
            .store(in: &observers)

        _ = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event) ?? event
        }
        _ = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                if self?.panel.isVisible == true { self?.hide() }
            }
        }

        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)

        if ProcessInfo.processInfo.environment["CLIPBAR_AUTOSHOW"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.show() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.flush()
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "ClipBar")
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            togglePanel()
        }
    }

    private func showMenu() {
        hide()
        let menu = NSMenu()
        menu.addItem(menuItem("Open ClipBar", #selector(togglePanel)))
        menu.addItem(menuItem(store.paused ? "Resume Capturing" : "Pause Capturing", #selector(togglePause)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Settings…", #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit ClipBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func menuItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func togglePause() {
        store.paused.toggle()
    }

    // MARK: - Panel

    private func setUpPanel() {
        panel = Panel(contentRect: NSRect(origin: .zero, size: ClipView.size))
        panel.contentView = NSHostingView(rootView: ClipView(
            store: store,
            paste: { [weak self] item, direct in self?.paste(item, direct: direct) },
            edit: { [weak self] item in self?.showEditor(item) },
            openSettings: { [weak self] in self?.openSettings() }
        ))
        panel.setAccessibilityLabel("ClipBar")
    }

    @objc private func togglePanel() {
        panel.isVisible ? hide() : show()
    }

    private func show() {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }
        store.prepareForDisplay()
        positionPanel()
        panel.alphaValue = 0
        // A non-activating panel takes the keyboard without deactivating the current app,
        // so its focused field is still focused when the panel closes and ⌘V lands there.
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            panel.animator().alphaValue = 1
        }
    }

    private func positionPanel() {
        let size = panel.frame.size
        guard let button = statusItem.button, let anchor = button.window?.frame,
              let screen = button.window?.screen ?? NSScreen.main else { return panel.center() }
        let visible = screen.visibleFrame
        let margin = ClipView.margin
        var origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.minY - size.height + margin - 4)
        origin.x = min(max(origin.x, visible.minX - margin + 4), visible.maxX - size.width + margin - 4)
        origin.y = min(origin.y, visible.maxY - size.height + margin)
        panel.setFrameOrigin(origin)
    }

    private func hide(restoringFocus: Bool = true) {
        panel.orderOut(nil)
        if restoringFocus { restoreFocus() }
    }

    /// Only needed when one of ClipBar's own windows (editor, settings) took over activation.
    private func restoreFocus() {
        guard NSApp.isActive, let app = previousApp, !app.isTerminated else { return }
        NSApp.yieldActivation(to: app)
        app.activate()
    }

    /// Copies the item and, when allowed, pastes it into the app that was active before ClipBar.
    private func paste(_ item: ClipItem, direct: Bool) {
        store.copy(item)
        hide()
        guard direct, settings.autoPaste, let target = previousApp else { return }
        guard Clipboard.canPaste else {
            // Without Accessibility access the item is only copied; point the user at the fix once.
            if !askedForAccessibility {
                askedForAccessibility = true
                Clipboard.requestPastePermission()
            }
            return
        }
        Task {
            // Wait (briefly) until the target app is active again before sending ⌘V.
            for _ in 0..<50 where NSApp.isActive || NSWorkspace.shared.frontmostApplication != target {
                try? await Task.sleep(for: .milliseconds(10))
            }
            try? await Task.sleep(for: .milliseconds(50))
            // The ClipBar shortcut may itself be ⌘V; free it so the synthetic ⌘V reaches the app.
            HotKey.shared.unregister()
            Clipboard.pressPaste()
            try? await Task.sleep(for: .milliseconds(150))
            HotKey.shared.register(settings.shortcut)
        }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard panel.isKeyWindow else { return event }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let code = Int(event.keyCode)

        if flags == .command, let index = Self.digitKeys.firstIndex(of: code) {
            if store.visible.indices.contains(index) { paste(store.visible[index], direct: true) }
            return nil
        }

        switch (code, flags) {
        case (kVK_UpArrow, _): store.moveSelection(by: -1)
        case (kVK_DownArrow, _): store.moveSelection(by: 1)
        case (kVK_Return, []), (kVK_ANSI_KeypadEnter, []): withSelection { paste($0, direct: true) }
        case (kVK_Return, .option), (kVK_ANSI_KeypadEnter, .option): withSelection { paste($0, direct: false) }
        case (kVK_Escape, _):
            if store.query.isEmpty { hide() } else { store.query = "" }
        case (kVK_Tab, []): store.cycleFilter(by: 1)
        case (kVK_Tab, .shift): store.cycleFilter(by: -1)
        case (kVK_Delete, .command): withSelection(store.remove)
        case (kVK_ANSI_P, .command): withSelection(store.togglePin)
        case (kVK_ANSI_E, .command): withSelection(showEditor)
        case (kVK_ANSI_Comma, .command): openSettings()
        default: return event
        }
        return nil
    }

    private func withSelection(_ action: (ClipItem) -> Void) {
        if let item = store.selectedItem { action(item) }
    }

    // MARK: - Windows

    private func showEditor(_ item: ClipItem) {
        hide(restoringFocus: false)
        let window = editorWindow ?? makeWindow(
            title: "ClipBar",
            size: NSSize(width: 820, height: 580),
            style: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        let size = window.contentLayoutRect.size
        let controller = NSHostingController(rootView: EditorView(
            store: store,
            item: item,
            paste: { [weak self] item in
                self?.editorWindow?.orderOut(nil)
                self?.paste(item, direct: true)
            },
            close: { [weak self] in self?.editorWindow?.close() }
        ))
        controller.sizingOptions = [.minSize]
        window.contentViewController = controller
        window.setContentSize(size)
        editorWindow = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func openSettings() {
        hide(restoringFocus: false)
        if settingsWindow == nil {
            let window = makeWindow(title: "ClipBar Settings", size: NSSize(width: 460, height: 620), style: [.titled, .closable])
            window.contentViewController = NSHostingController(rootView: SettingsView { [weak self] includingPinned in
                self?.store.clear(includingPinned: includingPinned)
            })
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(title: String, size: NSSize, style: NSWindow.StyleMask) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.delegate = self
        window.center()
        return window
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Hand focus back once the last ClipBar window goes away.
        let others = [editorWindow, settingsWindow].compactMap { $0 }
            .filter { $0 !== notification.object as? NSWindow && $0.isVisible }
        if others.isEmpty && !panel.isVisible { restoreFocus() }
    }
}

final class Panel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .statusBar
        isFloatingPanel = true
        hasShadow = false // the card draws its own, rounded shadow
        isOpaque = false
        backgroundColor = .clear
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
