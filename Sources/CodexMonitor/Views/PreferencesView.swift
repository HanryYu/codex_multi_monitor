import SwiftUI
import AppKit

// MARK: - Display Mode

enum DisplayMode: String {
    case remaining
    case used
}
// MARK: - Reset Time Format

enum ResetTimeFormat: String {
    case relative
    case absolute
}


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
        case .off: return L10n.refreshOff
        case .oneMinute: return L10n.refresh1Minute
        case .fiveMinutes: return L10n.refresh5Minutes
        case .fifteenMinutes: return L10n.refresh15Minutes
        case .thirtyMinutes: return L10n.refresh30Minutes
        }
    }

    var icon: String {
        switch self {
        case .off: return "pause.circle"
        case .oneMinute: return "clock.arrow.1"
        case .fiveMinutes: return "clock"
        case .fifteenMinutes: return "clock.badge"
        case .thirtyMinutes: return "clock.badge.2"
        }
    }
}

// MARK: - Preferences Keys

enum PreferencesKeys {
    static let refreshInterval = "refresh_interval_seconds"
    static let launchAtLogin = "launch_at_login"
    static let bundleIdentifier = "CodexMonitor.bundle_identifier"
    static let displayMode = "displayMode"
    static let alertThreshold = "alertThreshold"
    static let showMenuBarText = "showMenuBarText"
    static let resetTimeFormat = "resetTimeFormat"
    static let autoImportEnabled = "auto_import_enabled"
    static let usageAlertEnabled = "usageAlertEnabled"
    static let recoveryNotificationEnabled = "recoveryNotificationEnabled"
}

// MARK: - Default Binary Path

func defaultBinaryPath() -> String {
    if Bundle.main.bundlePath.hasSuffix(".app") {
        return Bundle.main.bundlePath
    }
    return CommandLine.arguments[0]
}

func defaultBundleIdentifier() -> String {
    let saved = UserDefaults.standard.string(forKey: PreferencesKeys.bundleIdentifier)
    return saved ?? "com.henry.CodexMonitor"
}

// MARK: - LaunchAgent Plist

func launchAgentPlistURL(bundleID: String) -> URL {
    let fileName = "\(bundleID).plist"
    return FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/\(fileName)")
}

func readLaunchAgentPlist(bundleID: String) -> [String: Any]? {
    let url = launchAgentPlistURL(bundleID: bundleID)
    guard let data = try? Data(contentsOf: url),
          let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    else { return nil }
    return plist
}

func writeLaunchAgentPlist(bundleID: String, binaryPath: String, enable: Bool) -> Bool {
    let url = launchAgentPlistURL(bundleID: bundleID)
    let dir = url.deletingLastPathComponent()

    if enable {
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
    @State private var displayMode: DisplayMode = .remaining
    @State private var alertThreshold: Double = 80
    @State private var showMenuBarText: Bool = false
    @State private var resetTimeFormat: ResetTimeFormat = .relative

    var body: some View {
        VStack(spacing: 24) {
            // Title
            Label(L10n.preferences, systemImage: "gear")
                .font(.system(size: 16, weight: .semibold))
                .padding(.top, 4)

            // Sections
            VStack(spacing: 20) {
                // Refresh Interval
                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.autoRefresh, systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Picker("", selection: $refreshInterval) {
                        ForEach(RefreshInterval.allCases) { interval in
                            Label(interval.label, systemImage: interval.icon)
                                .tag(interval)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: refreshInterval) { _, newValue in
                        UserDefaults.standard.set(newValue.rawValue, forKey: PreferencesKeys.refreshInterval)
                        NotificationCenter.default.post(name: .refreshIntervalChanged, object: nil)
                    }
                }

                Divider().opacity(0.4)

                // Display Mode Toggle
                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.displayModeLabel, systemImage: "eye")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Picker("", selection: $displayMode) {
                        Text(L10n.showRemaining).tag(DisplayMode.remaining)
                        Text(L10n.showUsed).tag(DisplayMode.used)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: displayMode) { _, newValue in
                        UserDefaults.standard.set(newValue.rawValue, forKey: PreferencesKeys.displayMode)
                        NotificationCenter.default.post(name: .displayModeChanged, object: nil)
                    }
                }

                Divider().opacity(0.4)

                // Reset Time Format
                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.resetTimeFormat, systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text(L10n.resetTimeFormatDesc)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    Picker("", selection: $resetTimeFormat) {
                        Text(L10n.relativeTime).tag(ResetTimeFormat.relative)
                        Text(L10n.absoluteTime).tag(ResetTimeFormat.absolute)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: resetTimeFormat) { _, newValue in
                        UserDefaults.standard.set(newValue.rawValue, forKey: PreferencesKeys.resetTimeFormat)
                        NotificationCenter.default.post(name: .resetTimeFormatChanged, object: nil)
                    }
                }

                Divider().opacity(0.4)

                // Menu Bar Text Toggle
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(L10n.showQuotaInMenuBar, systemImage: "text.alignleft")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Toggle("", isOn: $showMenuBarText)
                            .labelsHidden()
                    }
                    .onChange(of: showMenuBarText) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: PreferencesKeys.showMenuBarText)
                        NotificationCenter.default.post(name: .menuBarTextChanged, object: nil)
                    }

                    Text(L10n.showUsageSummaryText)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                Divider().opacity(0.4)

                // Alert Threshold
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(L10n.usageAlert, systemImage: "bell.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(alertThreshold))%")
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: $alertThreshold, in: 50...95, step: 5)
                        .onChange(of: alertThreshold) { _, newValue in
                            UserDefaults.standard.set(Int(newValue), forKey: PreferencesKeys.alertThreshold)
                        }

                    Text(L10n.notifyWhenExceedsThreshold)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                Divider().opacity(0.4)

                // Launch at Login
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label(L10n.launchAtLogin, systemImage: "power")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Toggle("", isOn: $launchAtLogin)
                            .labelsHidden()
                    }
                    .onChange(of: launchAtLogin) { _, newValue in
                        toggleLaunchAtLogin(enable: newValue)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Text(L10n.bundleIdLabel)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                            Text(bundleIdentifier)
                                .font(.system(size: 10).monospaced())
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        HStack(spacing: 4) {
                            Text(L10n.binaryLabel)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                            Text(binaryPath)
                                .font(.system(size: 10).monospaced())
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .padding(.leading, 2)
                }
            }

            Spacer()

            // Done button
            HStack {
                Spacer()
                Button(L10n.done) {
                    closeWindow()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 380)
        .background(.ultraThinMaterial)
        .onAppear {
            loadPreferences()
        }
    }

    private func loadPreferences() {
        let saved = UserDefaults.standard.integer(forKey: PreferencesKeys.refreshInterval)
        if saved == 0 && !UserDefaults.standard.bool(forKey: "has_set_refresh_interval") {
            refreshInterval = .fiveMinutes
            UserDefaults.standard.set(RefreshInterval.fiveMinutes.rawValue, forKey: PreferencesKeys.refreshInterval)
            UserDefaults.standard.set(true, forKey: "has_set_refresh_interval")
        } else {
            refreshInterval = RefreshInterval(rawValue: saved) ?? .fiveMinutes
        }

        bundleIdentifier = defaultBundleIdentifier()
        binaryPath = defaultBinaryPath()

        let plist = readLaunchAgentPlist(bundleID: bundleIdentifier)
        launchAtLogin = plist != nil

        // Load display mode
        let modeString = UserDefaults.standard.string(forKey: PreferencesKeys.displayMode) ?? DisplayMode.remaining.rawValue
        displayMode = DisplayMode(rawValue: modeString) ?? .remaining

        // Load alert threshold
        let savedThreshold = UserDefaults.standard.integer(forKey: PreferencesKeys.alertThreshold)
        alertThreshold = savedThreshold > 0 ? Double(savedThreshold) : 80

        // Load menu bar text toggle
        showMenuBarText = UserDefaults.standard.bool(forKey: PreferencesKeys.showMenuBarText)

        // Load reset time format
        let formatString = UserDefaults.standard.string(forKey: PreferencesKeys.resetTimeFormat) ?? ResetTimeFormat.relative.rawValue
        resetTimeFormat = ResetTimeFormat(rawValue: formatString) ?? .relative
    }

    private func toggleLaunchAtLogin(enable: Bool) {
        UserDefaults.standard.set(bundleIdentifier, forKey: PreferencesKeys.bundleIdentifier)
        _ = writeLaunchAgentPlist(bundleID: bundleIdentifier, binaryPath: binaryPath, enable: enable)
    }

    private func closeWindow() {
        if let window = NSApp.windows.first(where: { $0.title.contains("CodexMonitor") || $0.title.contains("Codex Monitor") }) {
            window.close()
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let refreshIntervalChanged = Notification.Name("CodexMonitor.refreshIntervalChanged")
    static let displayModeChanged = Notification.Name("CodexMonitor.displayModeChanged")
    static let menuBarTextChanged = Notification.Name("CodexMonitor.menuBarTextChanged")
    static let resetTimeFormatChanged = Notification.Name("CodexMonitor.resetTimeFormatChanged")
    static let autoImportChanged = Notification.Name("CodexMonitor.autoImportChanged")
    static let usageAlertEnabledChanged = Notification.Name("CodexMonitor.usageAlertEnabledChanged")
    static let recoveryNotificationEnabledChanged = Notification.Name("CodexMonitor.recoveryNotificationEnabledChanged")
}
