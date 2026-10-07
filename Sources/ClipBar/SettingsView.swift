import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case general, pasting, screenshots, privacy, history, about

        var id: Self { self }

        var title: String {
            switch self {
            case .general: "General"
            case .pasting: "Pasting"
            case .screenshots: "Screenshots"
            case .privacy: "Privacy"
            case .history: "History"
            case .about: "About"
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape.fill"
            case .pasting: "doc.on.clipboard.fill"
            case .screenshots: "camera.viewfinder"
            case .privacy: "hand.raised.fill"
            case .history: "clock.arrow.circlepath"
            case .about: "info.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .general: .gray
            case .pasting: .blue
            case .screenshots: .purple
            case .privacy: .indigo
            case .history: .orange
            case .about: .teal
            }
        }

        var summary: String {
            switch self {
            case .general: "Startup and the shortcut that opens ClipBar."
            case .pasting: "Send the chosen item straight into the app you were using."
            case .screenshots: "Every screenshot you take lands in your history, ready to paste."
            case .privacy: "Keep passwords and secrets out of your history."
            case .history: "How long items are kept, and how many."
            case .about: ""
            }
        }
    }

    @ObservedObject var store: ClipStore
    @ObservedObject private var settings = Settings.shared

    @State private var pane: Pane? = .general
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var canPaste = Clipboard.canPaste
    @State private var confirmingClear = false

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    SymbolTile(symbol: pane.symbol, tint: pane.tint, size: 22)
                }
                .tag(pane)
            }
            .navigationSplitViewColumnWidth(200)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail(pane ?? .general)
                .navigationTitle((pane ?? .general).title)
        }
        .frame(width: 720, height: 520)
        .confirmationDialog("Clear clipboard history?", isPresented: $confirmingClear) {
            Button("Clear Unpinned Items", role: .destructive) { store.clear(includingPinned: false) }
            Button("Clear Everything", role: .destructive) { store.clear(includingPinned: true) }
        } message: {
            Text("This can't be undone.")
        }
        .task {
            // Accessibility access is granted in System Settings, so keep checking while open.
            while !Task.isCancelled {
                canPaste = Clipboard.canPaste
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    @ViewBuilder
    private func detail(_ pane: Pane) -> some View {
        if pane == .about {
            about
        } else {
            Form {
                Section {
                    PaneHeader(pane: pane)
                }
                switch pane {
                case .general: general
                case .pasting: pasting
                case .screenshots: screenshots
                case .privacy: privacy
                case .history: history
                case .about: EmptyView()
                }
            }
            .formStyle(.grouped)
        }
    }

    // MARK: - Panes

    @ViewBuilder
    private var general: some View {
        Section {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
            Toggle(isOn: $store.paused) {
                Text("Pause capturing")
                Text("New copies aren't recorded while paused.")
            }
        }
        Section {
            LabeledContent {
                ShortcutRecorder(shortcut: $settings.shortcut)
            } label: {
                Text("Open ClipBar")
                Text("Click the shortcut, then press a new one.")
            }
        }
    }

    @ViewBuilder
    private var pasting: some View {
        Section {
            Toggle(isOn: $settings.autoPaste) {
                Text("Paste into the active app")
                Text("↩ and click copy the item, switch back and press ⌘V. ⌥↩ only copies.")
            }
        }
        Section("Permission") {
            LabeledContent {
                if canPaste {
                    Label("Allowed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button("Allow Access…", action: Clipboard.requestPastePermission)
                }
            } label: {
                Text("Accessibility")
                Text(canPaste
                     ? "ClipBar can press ⌘V for you."
                     : "Needed to paste for you. If ClipBar is already listed but this still says missing, remove it with − and add it again.")
            }
        }
    }

    @ViewBuilder
    private var screenshots: some View {
        Section {
            Toggle(isOn: $settings.captureScreenshots) {
                Text("Add new screenshots to history")
                Text("Works with ⇧⌘3, ⇧⌘4 and ⇧⌘5.")
            }
            Toggle(isOn: $settings.copyScreenshots) {
                Text("Copy them to the clipboard")
                Text("Paste a screenshot right after taking it.")
            }
            .disabled(!settings.captureScreenshots)
        }
        Section {
            Label {
                Text("For instant results, open ⇧⌘5 → Options and turn off **Show Floating Thumbnail**. Otherwise macOS saves the file about five seconds later.")
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "lightbulb.fill").foregroundStyle(.yellow)
            }
            .font(.system(size: 12))
        }
    }

    @ViewBuilder
    private var privacy: some View {
        Section {
            Toggle(isOn: $settings.skipSensitive) {
                Text("Ignore passwords and secrets")
                Text("Skips content password managers mark as confidential, private keys, API tokens and card numbers.")
            }
        }
        Section {
            Label("Everything stays on this Mac. Nothing is sent anywhere.", systemImage: "lock.fill")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var history: some View {
        Section {
            Stepper(value: $settings.keepDays, in: 1...365) {
                LabeledContent("Keep items for", value: settings.keepDays == 1 ? "1 day" : "\(settings.keepDays) days")
            }
            Stepper(value: $settings.maxItems, in: 50...2000, step: 50) {
                LabeledContent("Keep at most", value: "\(settings.maxItems) items")
            }
            Toggle("Clean up pinned items too", isOn: $settings.cleanPinned)
        }
        Section {
            LabeledContent("Items", value: "\(store.items.count)")
            LabeledContent("Pinned", value: "\(store.items.filter(\.pinned).count)")
            LabeledContent("Storage", value: storageSize)
            LabeledContent {
                Button("Clear History…", role: .destructive) { confirmingClear = true }
            } label: {
                Text("Clear history")
            }
        }
    }

    private var about: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
            Text("ClipBar")
                .font(.system(size: 26, weight: .bold))
            Text("Version \(version)")
                .foregroundStyle(.secondary)
            Text("A fast, private clipboard history for your menu bar.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                if let url = URL(string: "https://github.com/SajjadMohabati/clipbar-mac") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("View on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .buttonStyle(.glass)
            .padding(.top, 6)
            Spacer()
            Text("Made by Sajjad Mohabati")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private var storageSize: String {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: Paths.images, includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
        let total = (urls + [Paths.history]).reduce(0) {
            $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return Int64(total).formatted(.byteCount(style: .file))
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            try on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - Building blocks

struct SymbolTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: .rect(cornerRadius: size * 0.26, style: .continuous))
    }
}

private struct PaneHeader: View {
    let pane: SettingsView.Pane

    var body: some View {
        HStack(spacing: 14) {
            SymbolTile(symbol: pane.symbol, tint: pane.tint, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(pane.title)
                    .font(.system(size: 17, weight: .semibold))
                Text(pane.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Shows the shortcut as key caps; click to record a new one.
private struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut
    @State private var monitor: Any?

    private var recording: Bool { monitor != nil }

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            HStack(spacing: 4) {
                if recording {
                    Text("Press keys…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 8)
                } else {
                    ForEach(Array(shortcut.keys.enumerated()), id: \.offset) { _, key in
                        KeyCap(key: key, size: .large)
                    }
                }
            }
            .frame(minWidth: 96, minHeight: 28)
            .padding(.horizontal, 4)
            .background(Color.primary.opacity(recording ? 0.04 : 0), in: .rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(recording ? Color.accentColor : .clear, lineWidth: 1.5)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Click, then press the new shortcut. Esc cancels.")
        .onDisappear(perform: stop)
    }

    private func start() {
        // Free the current shortcut so pressing it again can be recorded.
        HotKey.shared.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stop()
            } else if let recorded = Shortcut(event: event) {
                shortcut = recorded
                stop()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        HotKey.shared.register(shortcut)
    }
}
