import Foundation

enum MenuBarQuotaColorMode: String, Hashable {
    case quota
    case monochrome
}

enum MenuBarQuotaNumberPosition: String, Hashable {
    case leading
    case inside
    case trailing
}

enum MenuBarQuotaWindow: String, Hashable {
    case fiveHour
    case weekly

    func matches(seconds: Int) -> Bool {
        switch self {
        case .fiveHour: return (4 * 60 * 60)...(6 * 60 * 60) ~= seconds
        case .weekly: return (6 * 24 * 60 * 60)...(8 * 24 * 60 * 60) ~= seconds
        }
    }
}

struct MenuBarQuotaAppearance: Equatable {
    var colorMode: MenuBarQuotaColorMode = .quota
    var numberPosition: MenuBarQuotaNumberPosition = .trailing
    private static let prefix = "CodexMonitor.menuBarAppearance."

    static func load(defaults: UserDefaults = .standard) -> Self {
        var result = Self()
        let savedColorMode = defaults.string(forKey: prefix + "colorMode")
        // The previous single-color option stored "custom". It now always means white.
        result.colorMode = savedColorMode == "custom" ? .monochrome
            : savedColorMode.flatMap(MenuBarQuotaColorMode.init(rawValue:)) ?? .quota
        result.numberPosition = defaults.string(forKey: prefix + "numberPosition")
            .flatMap(MenuBarQuotaNumberPosition.init(rawValue:)) ?? .trailing
        return result
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(colorMode.rawValue, forKey: Self.prefix + "colorMode")
        defaults.set(numberPosition.rawValue, forKey: Self.prefix + "numberPosition")
        for key in ["customColor", "healthyColor", "warningColor", "criticalColor"] {
            defaults.removeObject(forKey: Self.prefix + key)
        }
        NotificationCenter.default.post(name: .menuBarTextChanged, object: nil)
    }

    func effectiveNumberPosition(iconStyle: MenuBarIconStyle) -> MenuBarQuotaNumberPosition {
        iconStyle == .standard && numberPosition == .inside ? .trailing : numberPosition
    }

}
