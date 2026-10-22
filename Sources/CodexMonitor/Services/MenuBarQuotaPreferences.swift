import Foundation

enum MenuBarIconStyle: String, Hashable {
    case ring
    case standard
}

enum MenuBarQuotaPreferences {
    static let iconStyleKey = "CodexMonitor.menuBarIconStyle"
    static let accountIDsKey = "CodexMonitor.menuBarQuotaAccountIDs"
    private static let quotaWindowsKey = "CodexMonitor.menuBarAccountQuotaWindows"
    private static let legacyQuotaWindowKey = "CodexMonitor.menuBarAppearance.quotaWindow"

    static func quotaWindow(for accountID: UUID, defaults: UserDefaults = .standard) -> MenuBarQuotaWindow {
        let saved = defaults.dictionary(forKey: quotaWindowsKey)?[accountID.uuidString] as? String
        return saved.flatMap(MenuBarQuotaWindow.init(rawValue:)) ?? .fiveHour
    }

    static func setQuotaWindow(_ window: MenuBarQuotaWindow, for accountID: UUID, defaults: UserDefaults = .standard) {
        var windows = defaults.dictionary(forKey: quotaWindowsKey) ?? [:]
        windows[accountID.uuidString] = window.rawValue
        defaults.set(windows, forKey: quotaWindowsKey)
        NotificationCenter.default.post(name: .menuBarTextChanged, object: nil)
    }

    /// Preserve the old global choice for existing rings once, then retire that setting.
    /// New accounts always start with 5h; changing one account never changes another.
    static func migrateLegacyQuotaWindow(for accountIDs: [UUID], defaults: UserDefaults = .standard) {
        guard !accountIDs.isEmpty,
              let legacy = defaults.string(forKey: legacyQuotaWindowKey) else { return }
        let window = MenuBarQuotaWindow(rawValue: legacy) ?? .fiveHour
        var windows = defaults.dictionary(forKey: quotaWindowsKey) ?? [:]
        for id in accountIDs where windows[id.uuidString] == nil {
            windows[id.uuidString] = window.rawValue
        }
        defaults.set(windows, forKey: quotaWindowsKey)
        defaults.removeObject(forKey: legacyQuotaWindowKey)
    }

    static func iconStyle(defaults: UserDefaults = .standard) -> MenuBarIconStyle {
        guard let rawValue = defaults.string(forKey: iconStyleKey) else { return .ring }
        return MenuBarIconStyle(rawValue: rawValue) ?? .ring
    }

    /// Returns configured IDs in saved order, restricted to currently available accounts.
    /// An unsaved preference defaults to the only available account, but stays empty when the
    /// user has multiple accounts so the app never chooses one on their behalf.
    static func selectedAccountIDs(available: [UUID], defaults: UserDefaults = .standard) -> [UUID] {
        guard defaults.object(forKey: accountIDsKey) != nil else {
            return available.count == 1 ? [available[0]] : []
        }

        guard let encodedIDs = defaults.string(forKey: accountIDsKey),
              let data = encodedIDs.data(using: .utf8),
              let savedIDs = try? JSONDecoder().decode([UUID].self, from: data)
        else {
            return []
        }

        let availableIDs = Set(available)
        var seen = Set<UUID>()
        return savedIDs.filter { availableIDs.contains($0) && seen.insert($0).inserted }
    }

    static func saveAccountIDs(_ ids: [UUID], defaults: UserDefaults = .standard) {
        var seen = Set<UUID>()
        let uniqueIDs = ids.filter { seen.insert($0).inserted }
        let data = (try? JSONEncoder().encode(uniqueIDs)) ?? Data("[]".utf8)
        defaults.set(String(decoding: data, as: UTF8.self), forKey: accountIDsKey)
        NotificationCenter.default.post(name: .menuBarTextChanged, object: nil)
    }
}
