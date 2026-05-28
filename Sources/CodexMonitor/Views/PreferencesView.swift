import SwiftUI
import AppKit

// MARK: - Refresh Interval

enum RefreshInterval: Int, CaseIterable, Identifiable {
    case off = 0
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1800

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .off: return "Off"
        case .oneMinute: return "1 Minute"
        case .fiveMinutes: return "5 Minutes"
        case .fifteenMinutes: return "15 Minutes"
        case .thirtyMinutes: return "30 Minutes"
        }
    }
}

// MARK: - Preferences Keys

enum PreferencesKeys {
    static let refreshInterval = "refresh_interval_seconds"
    static let launchAtLogin = "launch_at_login"
    static let bundleIdentifier = "CodexMonitor.bundle_identifier"
}

// MARK: - Default Binary Path

private func defaultBinaryPath() -> String {
    if Bundle.main.bundlePath.hasSuffix(".app") {
        return Bundle.main.bundlePath
    }
    return CommandLine.arguments[0]
}

private func defaultBundleIdentifier() -> String {
    let saved = UserDefaults.standard.string(forKey: PreferencesKeys.bundleIdentifier)
    return saved ?? "com.henry.CodexMonitor"
}

// MARK: - LaunchAgent Plist

private func launchAgentPlistURL(bundleID: String) -> URL {
    let fileName = "\(bundleID).plist"
    return FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/\(fileName)")
}

private func readLaunchAgentPlist(bundleID: String) -> [String: Any]? {
    let url = launchAgentPlistURL(bundleID: bundleID)
    guard let data = try? Data(contentsOf: url),
          let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    else { return nil }
    return plist
}

private func writeLaunchAgentPlist(bundleID: String, binaryPath: String, enable: Bool) -> Bool {
    let url = launchAgentPlistURL(bundleID: bundleID)
    let dir = url.deletingLastPathComponent()

    if enable {
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "Label": bundleID,
            "ProgramArguments": [binaryPath],
            "RunAtLoad": true,
        ]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else {
            return false
        }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            print("Failed to write LaunchAgent plist: \(error)")
            return false
        }
    } else {
        // Remove plist file
        try? FileManager.default.removeItem(at: url)
        return true
    }
}

// MARK: - PreferencesView

struct PreferencesView: View {
    @State private var refreshInterval: RefreshInterval = .fiveMinutes
    @State private var launchAtLogin: Bool = false
    @State private var bundleIdentifier: String = ""
    @State private var binaryPath: String = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("Preferences")
                .font(.headline)

            // Refresh Interval
            VStack(alignment: .leading, spacing: 4) {
                Text("Auto Refresh Interval")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Picker("", selection: $refreshInterval) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(interval.label).tag(interval)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: refreshInterval) { _, newValue in
                    UserDefaults.standard.set(newValue.rawValue, forKey: PreferencesKeys.refreshInterval)
                    NotificationCenter.default.post(name: .refreshIntervalChanged, object: nil)
                }
            }

            Divider()

            // Launch at Login
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        toggleLaunchAtLogin(enable: newValue)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Bundle ID: \(bundleIdentifier)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("Binary: \(binaryPath)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done") {
                    closeWindow()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 380)
        .onAppear {
            loadPreferences()
        }
    }

    private func loadPreferences() {
        // Refresh interval
        let saved = UserDefaults.standard.integer(forKey: PreferencesKeys.refreshInterval)
        if saved == 0 && !UserDefaults.standard.bool(forKey: "has_set_refresh_interval") {
            // Default to 5 minutes
            refreshInterval = .fiveMinutes
            UserDefaults.standard.set(RefreshInterval.fiveMinutes.rawValue, forKey: PreferencesKeys.refreshInterval)
            UserDefaults.standard.set(true, forKey: "has_set_refresh_interval")
        } else {
            refreshInterval = RefreshInterval(rawValue: saved) ?? .fiveMinutes
        }

        // Bundle ID & binary path
        bundleIdentifier = defaultBundleIdentifier()
        binaryPath = defaultBinaryPath()

        // Launch at login — check if plist exists
        let plist = readLaunchAgentPlist(bundleID: bundleIdentifier)
        launchAtLogin = plist != nil
    }

    private func toggleLaunchAtLogin(enable: Bool) {
        UserDefaults.standard.set(bundleIdentifier, forKey: PreferencesKeys.bundleIdentifier)
        _ = writeLaunchAgentPlist(bundleID: bundleIdentifier, binaryPath: binaryPath, enable: enable)
    }

    private func closeWindow() {
        if let window = NSApp.windows.first(where: { $0.title == "CodexMonitor Preferences" }) {
            window.close()
        }
    }
}

// MARK: - Open Preferences Window

func openPreferencesWindow() {
    // Reuse existing window if present
    if let existing = NSApp.windows.first(where: { $0.title == "CodexMonitor Preferences" }) {
        existing.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return
    }

    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    window.title = "CodexMonitor Preferences"
    window.contentView = NSHostingView(rootView: PreferencesView())
    window.center()
    window.isReleasedWhenClosed = false
    window.level = .floating
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
}

// MARK: - Notification Name

extension Notification.Name {
    static let refreshIntervalChanged = Notification.Name("CodexMonitor.refreshIntervalChanged")
}
