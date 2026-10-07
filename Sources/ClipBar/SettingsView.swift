import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared
    let clearHistory: (_ includingPinned: Bool) -> Void

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var canPaste = Clipboard.canPaste
    @State private var confirmingClear = false

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                LabeledContent("Open ClipBar") {
                    ShortcutRecorder(shortcut: $settings.shortcut)
                }
            }

            Section {
                Toggle("Paste into the active app", isOn: $settings.autoPaste)
                if settings.autoPaste && !canPaste {
                    LabeledContent {
                        Button("Grant Access…", action: Clipboard.requestPastePermission)
                    } label: {
                        Label("Needs Accessibility access", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            } header: {
                Text("Pasting")
            } footer: {
                Text("Choosing an item copies it, switches back to the app you were using and presses ⌘V. Use ⌥↩ to copy without pasting.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Ignore passwords and secrets", isOn: $settings.skipSensitive)
            } header: {
                Text("Privacy")
            } footer: {
                Text("Skips anything password managers mark as confidential, plus private keys, API tokens and card numbers.")
                    .foregroundStyle(.secondary)
            }

            Section("History") {
                Stepper(value: $settings.keepDays, in: 1...365) {
                    LabeledContent("Keep items for", value: "\(settings.keepDays) days")
                }
                Stepper(value: $settings.maxItems, in: 50...2000, step: 50) {
                    LabeledContent("Keep at most", value: "\(settings.maxItems) items")
                }
                Toggle("Clean up pinned items too", isOn: $settings.cleanPinned)
                LabeledContent("Stored history") {
                    Button("Clear History…", role: .destructive) { confirmingClear = true }
                }
            }

            Section {
            } footer: {
                Text("ClipBar \(version) · Made by Sajjad Mohabati")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 620)
        .confirmationDialog("Clear clipboard history?", isPresented: $confirmingClear) {
            Button("Clear Unpinned Items", role: .destructive) { clearHistory(false) }
            Button("Clear Everything", role: .destructive) { clearHistory(true) }
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

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            try on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

private struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut
    @State private var monitor: Any?

    var body: some View {
        Button {
            monitor == nil ? start() : stop()
        } label: {
            Text(monitor == nil ? shortcut.display : "Press a shortcut…")
                .font(.system(size: 12, weight: .medium))
                .frame(minWidth: 110)
        }
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
