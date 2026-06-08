import Foundation

// MARK: - Language Detection

enum AppLanguage: String {
    case en
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case ja

    var displayName: String {
        switch self {
        case .en:     return "English"
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .ja:     return "日本語"
        }
    }
}

enum LanguageOption: Hashable {
    case system
    case manual(AppLanguage)

    static var allCases: [LanguageOption] {
        [.system, .manual(.zhHans), .manual(.zhHant), .manual(.en), .manual(.ja)]
    }

    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .manual(let lang): return lang.displayName
        }
    }

    var rawValue: String {
        switch self {
        case .system: return ""
        case .manual(let lang): return lang.rawValue
        }
    }

    static func from(saved: String?) -> LanguageOption {
        guard let saved, !saved.isEmpty, let lang = AppLanguage(rawValue: saved) else {
            return .system
        }
        return .manual(lang)
    }
}

class LocaleManager: ObservableObject {
    static let shared = LocaleManager()

    @Published private(set) var currentLanguage: AppLanguage

    private init() {
        currentLanguage = LocaleManager.resolveLanguage()
    }

    func setLanguage(_ option: LanguageOption) {
        switch option {
        case .system:
            UserDefaults.standard.removeObject(forKey: "app_language")
        case .manual(let lang):
            UserDefaults.standard.set(lang.rawValue, forKey: "app_language")
        }
        currentLanguage = LocaleManager.resolveLanguage()
    }

    var currentLanguageOption: LanguageOption {
        let saved = UserDefaults.standard.string(forKey: "app_language") ?? ""
        if saved.isEmpty { return .system }
        guard let lang = AppLanguage(rawValue: saved) else { return .system }
        return .manual(lang)
    }

    private static func resolveLanguage() -> AppLanguage {
        let saved = UserDefaults.standard.string(forKey: "app_language") ?? ""
        if !saved.isEmpty, let manual = AppLanguage(rawValue: saved) {
            return manual
        }
        let locale = Locale.current
        let identifier = locale.identifier
        let langCode = locale.language.languageCode?.identifier ?? "en"
        let region = locale.language.region?.identifier ?? ""
        if langCode == "ja" {
            return .ja
        } else if langCode == "zh" {
            if identifier.contains("Hant") || identifier.contains("TW") || identifier.contains("HK") || identifier.contains("MO") || region == "TW" || region == "HK" || region == "MO" {
                return .zhHant
            }
            return .zhHans
        }
        return .en
    }
}

// MARK: - L10n (All Localized Strings)

enum L10n {
    private static var lang: AppLanguage { LocaleManager.shared.currentLanguage }

    // MARK: - Quota Card Labels

    static var remaining: String {
        switch lang {
        case .en:    return "remaining"
        case .ja:    return "残り"
        case .zhHans: return "剩余"
        case .zhHant: return "剩餘"
        }
    }

    static var used: String {
        switch lang {
        case .en:    return "used"
        case .ja:    return "使用済"
        case .zhHans: return "已用"
        case .zhHant: return "已用"
        }
    }

    static func resetRelative(hours: Int, minutes: Int) -> String {
        switch lang {
        case .en:
            if hours > 0 {
                return "Reset: \(hours)h\(minutes > 0 ? " \(minutes)m" : "")"
            }
            return "Reset: \(minutes)m"
        case .ja:
            if hours > 0 {
                return "リセット: \(hours)h\(minutes > 0 ? " \(minutes)m" : "")"
            }
            return "リセット: \(minutes)m"
        case .zhHans:
            if hours > 0 {
                return "重置: \(hours)h\(minutes > 0 ? " \(minutes)m" : "")"
            }
            return "重置: \(minutes)m"
        case .zhHant:
            if hours > 0 {
                return "重置: \(hours)h\(minutes > 0 ? " \(minutes)m" : "")"
            }
            return "重置: \(minutes)m"
        }
    }

    static func resetAbsoluteTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        let resetWord: String

        switch lang {
        case .en:
            formatter.locale = Locale(identifier: "en_US")
            formatter.dateFormat = "M/d HH:mm"
            resetWord = "reset"
        case .ja:
            formatter.locale = Locale(identifier: "ja_JP")
            formatter.dateFormat = "M月d日 HH:mm"
            resetWord = "リセット"
        case .zhHans:
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "M月d日 HH:mm"
            resetWord = "重置"
        case .zhHant:
            formatter.locale = Locale(identifier: "zh_TW")
            formatter.dateFormat = "M月d日 HH:mm"
            resetWord = "重置"
        }

        return "\(formatter.string(from: date)) \(resetWord)"
    }

    // MARK: - Credits Card

    static var credits: String { "Credits" }

    static var unlimited: String {
        switch lang {
        case .en:    return "Unlimited"
        case .ja:    return "無制限"
        case .zhHans: return "无限"
        case .zhHant: return "無限"
        }
    }

    static var balance: String {
        switch lang {
        case .en:    return "Balance"
        case .ja:    return "残高"
        case .zhHans: return "余额"
        case .zhHant: return "餘額"
        }
    }

    static var available: String {
        switch lang {
        case .en:    return "Available"
        case .ja:    return "利用可"
        case .zhHans: return "可用"
        case .zhHant: return "可用"
        }
    }

    static var exhausted: String {
        switch lang {
        case .en:    return "Exhausted"
        case .ja:    return "枯渇"
        case .zhHans: return "已耗尽"
        case .zhHant: return "已耗盡"
        }
    }

    // MARK: - Rate Limit / Quota Status

    static var limitReached: String {
        switch lang {
        case .en:    return "Limit Reached"
        case .ja:    return "上限到達"
        case .zhHans: return "限额已达"
        case .zhHant: return "限額已達"
        }
    }

    static func fiveHourLimitReached() -> String {
        switch lang {
        case .en:    return "5-Hour Limit Reached"
        case .ja:    return "5時間上限到達"
        case .zhHans: return "5小时限额已达"
        case .zhHant: return "5小時限額已達"
        }
    }

    static func weeklyLimitReached() -> String {
        switch lang {
        case .en:    return "Weekly Limit Reached"
        case .ja:    return "週間上限到達"
        case .zhHans: return "每周限额已达"
        case .zhHant: return "每週限額已達"
        }
    }

    static func limitRecovered(accountName: String, limitType: String) -> String {
        switch lang {
        case .en:    return "\(accountName)'s \(limitType) limit has reset"
        case .ja:    return "\(accountName)の\(limitType)上限がリセットされました"
        case .zhHans: return "\(accountName) 的 \(limitType) 限额已刷新，现在可用"
        case .zhHant: return "\(accountName) 的 \(limitType) 限額已刷新，現在可用"
        }
    }

    static var creditsLimitReached: String {
        switch lang {
        case .en:    return "Credits Limit Reached"
        case .ja:    return "クレジット上限到達"
        case .zhHans: return "额度已用尽"
        case .zhHant: return "額度已用盡"
        }
    }

    static var spendLimitReached: String {
        switch lang {
        case .en:    return "Spend Limit Reached"
        case .ja:    return "支出上限到達"
        case .zhHans: return "消费限额已达"
        case .zhHant: return "消費限額已達"
        }
    }

    static func usageWarningNotification(
        accountName: String,
        limitType: String,
        usedPercent: Int,
        resetTime: String?
    ) -> String {
        switch lang {
        case .en:
            if let resetTime {
                return "\(accountName)'s \(limitType) usage reached \(usedPercent)%. Resets at \(resetTime)."
            }
            return "\(accountName)'s \(limitType) usage reached \(usedPercent)%."
        case .ja:
            if let resetTime {
                return "\(accountName)の\(limitType)使用量が\(usedPercent)%に達しました。\(resetTime)にリセットされます。"
            }
            return "\(accountName)の\(limitType)使用量が\(usedPercent)%に達しました。"
        case .zhHans:
            if let resetTime {
                return "\(accountName) 的 \(limitType) 已使用 \(usedPercent)%，将在 \(resetTime) 重置。"
            }
            return "\(accountName) 的 \(limitType) 已使用 \(usedPercent)%."
        case .zhHant:
            if let resetTime {
                return "\(accountName) 的 \(limitType) 已使用 \(usedPercent)%，將在 \(resetTime) 重置。"
            }
            return "\(accountName) 的 \(limitType) 已使用 \(usedPercent)%."
        }
    }

    static func limitReachedNotification(accountName: String, limitType: String, resetTime: String?) -> String {
        switch lang {
        case .en:
            if let resetTime {
                return "\(accountName)'s \(limitType) is exhausted. Resets at \(resetTime)."
            }
            return "\(accountName)'s \(limitType) is exhausted."
        case .ja:
            if let resetTime {
                return "\(accountName)の\(limitType)が上限に達しました。\(resetTime)にリセットされます。"
            }
            return "\(accountName)の\(limitType)が上限に達しました。"
        case .zhHans:
            if let resetTime {
                return "\(accountName) 的 \(limitType) 已用尽，将在 \(resetTime) 重置。"
            }
            return "\(accountName) 的 \(limitType) 已用尽。"
        case .zhHant:
            if let resetTime {
                return "\(accountName) 的 \(limitType) 已用盡，將在 \(resetTime) 重置。"
            }
            return "\(accountName) 的 \(limitType) 已用盡。"
        }
    }

    static var unavailable: String {
        switch lang {
        case .en:    return "Unavailable"
        case .ja:    return "利用不可"
        case .zhHans: return "不可使用"
        case .zhHant: return "不可使用"
        }
    }

    static func noUsageData(planType: String) -> String {
        switch lang {
        case .en:    return "plan: \(planType) — no usage data"
        case .ja:    return "plan: \(planType) — 利用データなし"
        case .zhHans: return "plan: \(planType) — 无用量数据"
        case .zhHant: return "plan: \(planType) — 無用量資料"
        }
    }

    static func weeklyLimit() -> String {
        switch lang {
        case .en:    return "Weekly Limit"
        case .ja:    return "週間上限"
        case .zhHans: return "每周限额"
        case .zhHant: return "每週限額"
        }
    }

    static func hourlyLimit(hours: Int) -> String {
        switch lang {
        case .en:    return "\(hours)h Limit"
        case .ja:    return "\(hours)時間上限"
        case .zhHans: return "\(hours)小时限额"
        case .zhHant: return "\(hours)小時限額"
        }
    }

    // MARK: - Empty States

    static var noAccountsAdded: String {
        switch lang {
        case .en:    return "No accounts added"
        case .ja:    return "アカウント未追加"
        case .zhHans: return "暂无账户"
        case .zhHant: return "暫無帳戶"
        }
    }

    static var addAccountToMonitor: String {
        switch lang {
        case .en:    return "Add a Codex account to monitor usage"
        case .ja:    return "Codexアカウントを追加して使用量を監視"
        case .zhHans: return "添加 Codex 账户以监控用量"
        case .zhHant: return "新增 Codex 帳戶以監控用量"
        }
    }

    static var addAccount: String {
        switch lang {
        case .en:    return "Add Account"
        case .ja:    return "アカウント追加"
        case .zhHans: return "添加账户"
        case .zhHant: return "新增帳戶"
        }
    }

    static var noAccountsYet: String {
        switch lang {
        case .en:    return "No accounts yet"
        case .ja:    return "アカウントがありません"
        case .zhHans: return "暂无账户"
        case .zhHant: return "暫無帳戶"
        }
    }

    static var refreshing: String {
        switch lang {
        case .en:    return "Refreshing..."
        case .ja:    return "更新中..."
        case .zhHans: return "刷新中..."
        case .zhHant: return "重新整理中..."
        }
    }

    static var noData: String {
        switch lang {
        case .en:    return "No data"
        case .ja:    return "データなし"
        case .zhHans: return "无数据"
        case .zhHant: return "無資料"
        }
    }

    // MARK: - Refresh Time (footer)

    static func updatedAt(time: String) -> String {
        switch lang {
        case .en:    return "\(time) updated"
        case .ja:    return "\(time) 更新"
        case .zhHans: return "\(time) 更新"
        case .zhHant: return "\(time) 更新"
        }
    }

    static var notYetUpdated: String {
        switch lang {
        case .en:    return "--:-- updated"
        case .ja:    return "--:-- 更新"
        case .zhHans: return "--:-- 更新"
        case .zhHant: return "--:-- 更新"
        }
    }

    // MARK: - Menu Bar Footer

    static var settings: String {
        switch lang {
        case .en:    return "Settings…"
        case .ja:    return "設定…"
        case .zhHans: return "设置…"
        case .zhHant: return "設定…"
        }
    }

    static var quitCodexMonitor: String {
        switch lang {
        case .en:    return "Quit Codex Monitor"
        case .ja:    return "Codex Monitor を終了"
        case .zhHans: return "退出 Codex Monitor"
        case .zhHant: return "結束 Codex Monitor"
        }
    }

    // MARK: - Status Bar Title

    static func percentLeft(_ percent: Int) -> String {
        switch lang {
        case .en:    return " \(percent)% left"
        case .ja:    return " 残り\(percent)%"
        case .zhHans: return " \(percent)%剩余"
        case .zhHant: return " \(percent)%剩餘"
        }
    }

    static func percentUsed(_ percent: Int) -> String {
        switch lang {
        case .en:    return " \(percent)% used"
        case .ja:    return " \(percent)%使用済"
        case .zhHans: return " \(percent)%已用"
        case .zhHant: return " \(percent)%已用"
        }
    }

    // MARK: - Settings Window Title

    static var codexMonitorSettings: String {
        switch lang {
        case .en:    return "Codex Monitor Settings"
        case .ja:    return "Codex Monitor 設定"
        case .zhHans: return "Codex Monitor 设置"
        case .zhHant: return "Codex Monitor 設定"
        }
    }

    // MARK: - Settings Tabs

    static var accountManagement: String {
        switch lang {
        case .en:    return "Accounts"
        case .ja:    return "アカウント"
        case .zhHans: return "账户管理"
        case .zhHant: return "帳戶管理"
        }
    }

    static var preferences: String {
        switch lang {
        case .en:    return "Preferences"
        case .ja:    return "設定"
        case .zhHans: return "偏好设置"
        case .zhHant: return "偏好設定"
        }
    }

    // MARK: - Account Management

    static var monitoredAccountList: String {
        switch lang {
        case .en:    return "Monitored Accounts"
        case .ja:    return "監視アカウント一覧"
        case .zhHans: return "监控账户列表"
        case .zhHant: return "監控帳戶列表"
        }
    }

    static var editAccount: String {
        switch lang {
        case .en:    return "Edit Account"
        case .ja:    return "アカウントを編集"
        case .zhHans: return "编辑账户"
        case .zhHant: return "編輯帳戶"
        }
    }

    static var deleteAccount: String {
        switch lang {
        case .en:    return "Delete Account"
        case .ja:    return "アカウントを削除"
        case .zhHans: return "删除账户"
        case .zhHant: return "刪除帳戶"
        }
    }

    // MARK: - Preferences / Settings

    static var dataRefreshInterval: String {
        switch lang {
        case .en:    return "Data Refresh Interval"
        case .ja:    return "データ更新間隔"
        case .zhHans: return "数据刷新间隔"
        case .zhHant: return "資料重新整理間隔"
        }
    }

    static var dataRefreshIntervalDesc: String {
        switch lang {
        case .en:    return "Periodically fetch latest cloud quota usage in the background"
        case .ja:    return "定期的にクラウドの最新使用量をバックグラウンドで取得"
        case .zhHans: return "定期静默拉取最新云端配额用量"
        case .zhHant: return "定期靜默拉取最新雲端配額用量"
        }
    }

    static var displayModeLabel: String {
        switch lang {
        case .en:    return "Display Mode"
        case .ja:    return "表示モード"
        case .zhHans: return "数值显示模式"
        case .zhHant: return "數值顯示模式"
        }
    }

    static var displayModeDesc: String {
        switch lang {
        case .en:    return "How the main value is displayed in menu bar and quota cards"
        case .ja:    return "メニューバーとカードの主要数値の表示方法"
        case .zhHans: return "菜单栏及主卡片所呈现的主数值模式"
        case .zhHant: return "選單列及主卡片所呈現的主數值模式"
        }
    }

    static var resetTimeFormat: String {
        switch lang {
        case .en:    return "Reset Time Format"
        case .ja:    return "リセット時刻形式"
        case .zhHans: return "重置时间格式"
        case .zhHant: return "重置時間格式"
        }
    }

    static var resetTimeFormatDesc: String {
        switch lang {
        case .en:    return "How the reset time is shown at the bottom of quota cards"
        case .ja:    return "カード下部のリセット時刻の表示形式"
        case .zhHans: return "卡片底部重置时间的显示维度"
        case .zhHant: return "卡片底部重置時間的顯示維度"
        }
    }

    static var relativeTime: String {
        switch lang {
        case .en:    return "Relative"
        case .ja:    return "相対"
        case .zhHans: return "相对时间"
        case .zhHant: return "相對時間"
        }
    }

    static var absoluteTime: String {
        switch lang {
        case .en:    return "Absolute"
        case .ja:    return "絶対"
        case .zhHans: return "绝对时间"
        case .zhHant: return "絕對時間"
        }
    }

    static var showTextInMenuBar: String {
        switch lang {
        case .en:    return "Show Text in Menu Bar"
        case .ja:    return "メニューバーにテキストを表示"
        case .zhHans: return "在系统菜单栏显示文本"
        case .zhHant: return "在系統選單列顯示文字"
        }
    }

    static var showTextInMenuBarDesc: String {
        switch lang {
        case .en:    return "When off, only the icon is shown in the menu bar"
        case .ja:    return "オフにするとメニューバーにはアイコンのみ表示"
        case .zhHans: return "关闭后将仅在菜单栏隐藏保留图标"
        case .zhHant: return "關閉後將僅在選單列隱藏保留圖示"
        }
    }

    static var usageAlertThreshold: String {
        switch lang {
        case .en:    return "Usage Alert Threshold"
        case .ja:    return "使用量アラート閾値"
        case .zhHans: return "用量预警提醒阈值"
        case .zhHant: return "用量預警提醒閾值"
        }
    }

    static var usageAlertThresholdDesc: String {
        switch lang {
        case .en:    return "Send a banner notification when any account exceeds this threshold"
        case .ja:    return "いずれかのアカウントがこの閾値を超えた場合にバナー通知を送信"
        case .zhHans: return "当任一监控限额使用率超过该额度时发送横幅通知"
        case .zhHant: return "當任一監控限額使用率超過該額度時發送橫幅通知"
        }
    }

    static var launchAtLogin: String {
        switch lang {
        case .en:    return "Launch at Login"
        case .ja:    return "ログイン時に起動"
        case .zhHans: return "开机自启"
        case .zhHant: return "開機自啟"
        }
    }

    static var bundleIdLabel: String {
        switch lang {
        case .en:    return "Bundle ID:"
        case .ja:    return "バンドルID:"
        case .zhHans: return "Bundle ID:"
        case .zhHant: return "Bundle ID:"
        }
    }

    static var binaryLabel: String {
        switch lang {
        case .en:    return "Binary:"
        case .ja:    return "バイナリ:"
        case .zhHans: return "Binary:"
        case .zhHant: return "Binary:"
        }
    }

    // MARK: - Add/Edit Account Sheet

    static var accountName: String {
        switch lang {
        case .en:    return "Account Name"
        case .ja:    return "アカウント名"
        case .zhHans: return "账户名称"
        case .zhHant: return "帳戶名稱"
        }
    }

    static var accountNamePlaceholder: String {
        switch lang {
        case .en:    return "e.g., Work, Personal"
        case .ja:    return "例: 仕事、個人"
        case .zhHans: return "例如：工作、个人"
        case .zhHant: return "例如：工作、個人"
        }
    }

    static var authToken: String {
        switch lang {
        case .en:    return "Authorization Token"
        case .ja:    return "認証トークン"
        case .zhHans: return "认证令牌"
        case .zhHant: return "認證權杖"
        }
    }

    static var authTokenPlaceholder: String {
        switch lang {
        case .en:    return "Bearer token from ChatGPT"
        case .ja:    return "ChatGPTから取得したBearerトークン"
        case .zhHans: return "从 ChatGPT 获取的 Bearer 令牌"
        case .zhHant: return "從 ChatGPT 取得的 Bearer 權杖"
        }
    }

    static var getAuthTokenHint: String {
        switch lang {
        case .en:    return "Get token from browser developer tools"
        case .ja:    return "ブラウザの開発者ツールからトークンを取得"
        case .zhHans: return "从浏览器开发者工具中获取令牌"
        case .zhHant: return "從瀏覽器開發者工具中取得權杖"
        }
    }

    static var tokenCannotBeEmpty: String {
        switch lang {
        case .en:    return "Token cannot be empty"
        case .ja:    return "トークンを入力してください"
        case .zhHans: return "令牌不能为空"
        case .zhHant: return "權杖不能為空"
        }
    }

    // MARK: - Buttons

    static var cancel: String {
        switch lang {
        case .en:    return "Cancel"
        case .ja:    return "キャンセル"
        case .zhHans: return "取消"
        case .zhHant: return "取消"
        }
    }

    static var save: String {
        switch lang {
        case .en:    return "Save"
        case .ja:    return "保存"
        case .zhHans: return "保存"
        case .zhHant: return "儲存"
        }
    }

    static var add: String {
        switch lang {
        case .en:    return "Add"
        case .ja:    return "追加"
        case .zhHans: return "添加"
        case .zhHant: return "新增"
        }
    }

    static var done: String {
        switch lang {
        case .en:    return "Done"
        case .ja:    return "完了"
        case .zhHans: return "完成"
        case .zhHant: return "完成"
        }
    }

    // MARK: - Refresh Interval Labels

    static var refreshOff: String {
        switch lang {
        case .en:    return "Off"
        case .ja:    return "オフ"
        case .zhHans: return "关闭"
        case .zhHant: return "關閉"
        }
    }

    static var refresh1Minute: String {
        switch lang {
        case .en:    return "1 Minute"
        case .ja:    return "1分"
        case .zhHans: return "1 分钟"
        case .zhHant: return "1 分鐘"
        }
    }

    static var refresh5Minutes: String {
        switch lang {
        case .en:    return "5 Minutes"
        case .ja:    return "5分"
        case .zhHans: return "5 分钟"
        case .zhHant: return "5 分鐘"
        }
    }

    static var refresh15Minutes: String {
        switch lang {
        case .en:    return "15 Minutes"
        case .ja:    return "15分"
        case .zhHans: return "15 分钟"
        case .zhHant: return "15 分鐘"
        }
    }

    static var refresh30Minutes: String {
        switch lang {
        case .en:    return "30 Minutes"
        case .ja:    return "30分"
        case .zhHans: return "30 分钟"
        case .zhHant: return "30 分鐘"
        }
    }

    // MARK: - Old PreferencesView (English)

    static var autoRefresh: String {
        switch lang {
        case .en:    return "Auto Refresh"
        case .ja:    return "自動更新"
        case .zhHans: return "自动刷新"
        case .zhHant: return "自動重新整理"
        }
    }

    static var showRemaining: String {
        switch lang {
        case .en:    return "Show Remaining"
        case .ja:    return "残りを表示"
        case .zhHans: return "显示剩余"
        case .zhHant: return "顯示剩餘"
        }
    }

    static var showUsed: String {
        switch lang {
        case .en:    return "Show Used"
        case .ja:    return "使用済みを表示"
        case .zhHans: return "显示已用"
        case .zhHant: return "顯示已用"
        }
    }

    static var showQuotaInMenuBar: String {
        switch lang {
        case .en:    return "Show Quota in Menu Bar"
        case .ja:    return "メニューバーに使用量を表示"
        case .zhHans: return "在菜单栏显示用量"
        case .zhHant: return "在選單列顯示用量"
        }
    }

    static var showUsageSummaryText: String {
        switch lang {
        case .en:    return "Show usage summary text next to the menu bar icon"
        case .ja:    return "メニューバーアイコンの横に使用量テキストを表示"
        case .zhHans: return "在菜单栏图标旁显示用量摘要文本"
        case .zhHant: return "在選單列圖示旁顯示用量摘要文字"
        }
    }

    static var usageAlert: String {
        switch lang {
        case .en:    return "Usage Alert"
        case .ja:    return "使用量アラート"
        case .zhHans: return "用量预警"
        case .zhHant: return "用量預警"
        }
    }

    static var notifyWhenExceedsThreshold: String {
        switch lang {
        case .en:    return "Notify when any account exceeds this threshold"
        case .ja:    return "アカウントがしきい値を超えた場合に通知"
        case .zhHans: return "当账户使用率超过此阈值时通知"
        case .zhHant: return "當帳戶使用率超過此閾值時通知"
        }
    }

    // MARK: - Language Picker

    static var language: String {
        switch lang {
        case .en:    return "Language"
        case .ja:    return "言語"
        case .zhHans: return "语言"
        case .zhHant: return "語言"
        }
    }

    static var languageDesc: String {
        switch lang {
        case .en:    return "Override the display language of the app"
        case .ja:    return "アプリの表示言語を手動で指定"
        case .zhHans: return "手动指定应用的显示语言"
        case .zhHant: return "手動指定應用的顯示語言"
        }
    }

    static var followSystem: String {
        switch lang {
        case .en:    return "Follow System"
        case .ja:    return "システムに従う"
        case .zhHans: return "跟随系统"
        case .zhHant: return "跟隨系統"
        }
    }

    // MARK: - Auto Import Local Accounts

    static var autoImportLocalAccounts: String {
        switch lang {
        case .en:    return "Auto Import Local Accounts"
        case .ja:    return "ローカルアカウント自動インポート"
        case .zhHans: return "自动导入本地账户"
        case .zhHant: return "自動匯入本地帳戶"
        }
    }

    static var autoImportLocalAccountsDesc: String {
        switch lang {
        case .en:    return "Monitor ~/.codex/auth.json for changes, automatically import and update accounts"
        case .ja:    return "~/.codex/auth.json の変更を監視し、アカウントを自動インポート・更新"
        case .zhHans: return "监听 ~/.codex/auth.json 变化，自动导入和更新账户"
        case .zhHant: return "監聽 ~/.codex/auth.json 變化，自動匯入和更新帳戶"
        }
    }

    static var sourceLocalBadge: String {
        switch lang {
        case .en:    return "Local"
        case .ja:    return "ローカル"
        case .zhHans: return "本地"
        case .zhHant: return "本地"
        }
    }

    static var localAuthInvalid: String {
        switch lang {
        case .en:    return "Local auth file missing"
        case .ja:    return "ローカル認証ファイルがありません"
        case .zhHans: return "本地认证文件已失效"
        case .zhHant: return "本地認證檔案已失效"
        }
    }

    static func localAccountImported(accountName: String) -> String {
        switch lang {
        case .en:    return "Imported local account: \(accountName)"
        case .ja:    return "ローカルアカウントをインポートしました: \(accountName)"
        case .zhHans: return "已自动导入本地账户: \(accountName)"
        case .zhHant: return "已自動匯入本地帳戶: \(accountName)"
        }
    }

    static var localAuthFileMissingNotification: String {
        switch lang {
        case .en:    return "~/.codex/auth.json is missing. Local accounts are marked unavailable."
        case .ja:    return "~/.codex/auth.json が見つかりません。ローカルアカウントを利用不可にしました。"
        case .zhHans: return "~/.codex/auth.json 已删除，本地导入账户已标记为失效"
        case .zhHant: return "~/.codex/auth.json 已刪除，本地匯入帳戶已標記為失效"
        }
    }

    // MARK: - Notification Toggles

    static var limitNotificationLabel: String {
        switch lang {
        case .en:    return "Limit Reached Alert"
        case .ja:    return "上限到達通知"
        case .zhHans: return "限额达到提醒"
        case .zhHant: return "限額達到提醒"
        }
    }

    static var limitNotificationDesc: String {
        switch lang {
        case .en:    return "Notify when a 5-hour, weekly, credit, or spend limit is exhausted"
        case .ja:    return "5時間、週間、クレジット、支出の上限到達時に通知"
        case .zhHans: return "当 5 小时、每周、额度或消费限额用尽时通知"
        case .zhHant: return "當 5 小時、每週、額度或消費限額用盡時通知"
        }
    }

    static var usageWarningNotificationLabel: String {
        switch lang {
        case .en:    return "Usage Warning Alert"
        case .ja:    return "使用量警告通知"
        case .zhHans: return "用量预警提醒"
        case .zhHant: return "用量預警提醒"
        }
    }

    static var usageWarningNotificationDesc: String {
        switch lang {
        case .en:    return "Notify when any account's usage exceeds the warning threshold"
        case .ja:    return "アカウントの使用量が警告閾値を超えた場合に通知"
        case .zhHans: return "当账户用量超过预警阈值时发送系统通知"
        case .zhHant: return "當帳戶用量超過預警閾值時發送系統通知"
        }
    }

    static var testNotificationButton: String {
        switch lang {
        case .en:    return "Send Test Alert"
        case .ja:    return "テスト通知を送信"
        case .zhHans: return "发送测试提醒"
        case .zhHant: return "發送測試提醒"
        }
    }

    static var testNotificationBody: String {
        switch lang {
        case .en:    return "This is how CodexMonitor usage alerts will appear."
        case .ja:    return "CodexMonitor の使用量通知はこのように表示されます。"
        case .zhHans: return "这是 CodexMonitor 用量提醒的显示效果。"
        case .zhHant: return "這是 CodexMonitor 用量提醒的顯示效果。"
        }
    }

    static var notificationTestSent: String {
        switch lang {
        case .en:    return "Sent"
        case .ja:    return "送信済み"
        case .zhHans: return "已发送"
        case .zhHant: return "已發送"
        }
    }

    static var notificationPermissionDenied: String {
        switch lang {
        case .en:    return "Notifications are disabled in System Settings"
        case .ja:    return "システム設定で通知が無効です"
        case .zhHans: return "系统设置中通知已关闭"
        case .zhHant: return "系統設定中通知已關閉"
        }
    }

    static func notificationTestFailed(error: String) -> String {
        switch lang {
        case .en:    return "Failed: \(error)"
        case .ja:    return "失敗: \(error)"
        case .zhHans: return "发送失败: \(error)"
        case .zhHant: return "發送失敗: \(error)"
        }
    }

    static var usageAlertEnabledLabel: String {
        switch lang {
        case .en:    return "Usage Alert"
        case .ja:    return "使用量アラート"
        case .zhHans: return "用量提醒"
        case .zhHant: return "用量提醒"
        }
    }

    static var usageAlertEnabledDesc: String {
        switch lang {
        case .en:    return "Notify when any account's usage exceeds the threshold"
        case .ja:    return "アカウントの使用量がしきい値を超えた場合に通知"
        case .zhHans: return "当账户用量超过预警阈值时发送系统通知"
        case .zhHant: return "當帳戶用量超過預警閾值時發送系統通知"
        }
    }

    static var recoveryNotificationLabel: String {
        switch lang {
        case .en:    return "Recovery Notification"
        case .ja:    return "復元通知"
        case .zhHans: return "额度恢复提醒"
        case .zhHant: return "額度恢復提醒"
        }
    }

    static var recoveryNotificationDesc: String {
        switch lang {
        case .en:    return "Notify when a rate-limited account becomes available again"
        case .ja:    return "レート制限が解除されたアカウントを通知"
        case .zhHans: return "当限额账户恢复可用时发送系统通知"
        case .zhHant: return "當限額帳戶恢復可用時發送系統通知"
        }
    }

    // MARK: - Updates

    static var updateSection: String {
        switch lang {
        case .en:    return "Updates"
        case .ja:    return "アップデート"
        case .zhHans: return "更新"
        case .zhHant: return "更新"
        }
    }

    static var automaticUpdates: String {
        switch lang {
        case .en:    return "Automatic Updates"
        case .ja:    return "自動アップデート"
        case .zhHans: return "自动检查更新"
        case .zhHant: return "自動檢查更新"
        }
    }

    static var checkForUpdatesButton: String {
        switch lang {
        case .en:    return "Check Now"
        case .ja:    return "今すぐ確認"
        case .zhHans: return "立即检查"
        case .zhHant: return "立即檢查"
        }
    }

    static var updateCheckingButton: String {
        switch lang {
        case .en:    return "Working"
        case .ja:    return "処理中"
        case .zhHans: return "处理中"
        case .zhHant: return "處理中"
        }
    }

    static var installUpdateButton: String {
        switch lang {
        case .en:    return "Install"
        case .ja:    return "インストール"
        case .zhHans: return "安装并重启"
        case .zhHant: return "安裝並重啟"
        }
    }

    static var updateStatusIdle: String {
        switch lang {
        case .en:    return "Current version: \(AppVersion.current)"
        case .ja:    return "現在のバージョン: \(AppVersion.current)"
        case .zhHans: return "当前版本: \(AppVersion.current)"
        case .zhHant: return "目前版本: \(AppVersion.current)"
        }
    }

    static var updateStatusChecking: String {
        switch lang {
        case .en:    return "Checking GitHub Releases..."
        case .ja:    return "GitHub Releases を確認中..."
        case .zhHans: return "正在检查 GitHub Releases..."
        case .zhHant: return "正在檢查 GitHub Releases..."
        }
    }

    static func updateStatusCurrent(version: String) -> String {
        switch lang {
        case .en:    return "You are on the latest version (\(version))."
        case .ja:    return "最新バージョンです（\(version)）。"
        case .zhHans: return "已是最新版本（\(version)）。"
        case .zhHant: return "已是最新版本（\(version)）。"
        }
    }

    static func updateStatusAvailable(version: String) -> String {
        switch lang {
        case .en:    return "Version \(version) is available."
        case .ja:    return "バージョン \(version) が利用可能です。"
        case .zhHans: return "发现新版本 \(version)。"
        case .zhHant: return "發現新版本 \(version)。"
        }
    }

    static func updateStatusDownloading(version: String) -> String {
        switch lang {
        case .en:    return "Downloading version \(version)..."
        case .ja:    return "バージョン \(version) をダウンロード中..."
        case .zhHans: return "正在下载 \(version)..."
        case .zhHant: return "正在下載 \(version)..."
        }
    }

    static func updateStatusDownloaded(version: String) -> String {
        switch lang {
        case .en:    return "Version \(version) is downloaded and ready to install."
        case .ja:    return "バージョン \(version) のダウンロードが完了しました。"
        case .zhHans: return "\(version) 已下载，可安装。"
        case .zhHant: return "\(version) 已下載，可安裝。"
        }
    }

    static var updateStatusNoAsset: String {
        switch lang {
        case .en:    return "Latest release has no DMG asset."
        case .ja:    return "最新リリースに DMG がありません。"
        case .zhHans: return "最新 Release 没有 DMG 文件。"
        case .zhHant: return "最新 Release 沒有 DMG 檔案。"
        }
    }

    static func updateStatusFailed(error: String) -> String {
        switch lang {
        case .en:    return "Update failed: \(error)"
        case .ja:    return "アップデート失敗: \(error)"
        case .zhHans: return "更新失败: \(error)"
        case .zhHant: return "更新失敗: \(error)"
        }
    }

    static func updateAvailableNotification(version: String) -> String {
        switch lang {
        case .en:    return "CodexMonitor \(version) is available."
        case .ja:    return "CodexMonitor \(version) が利用可能です。"
        case .zhHans: return "CodexMonitor \(version) 已发布。"
        case .zhHant: return "CodexMonitor \(version) 已發布。"
        }
    }

    static func updateReadyNotification(version: String) -> String {
        switch lang {
        case .en:    return "CodexMonitor \(version) has been downloaded."
        case .ja:    return "CodexMonitor \(version) のダウンロードが完了しました。"
        case .zhHans: return "CodexMonitor \(version) 已下载完成。"
        case .zhHant: return "CodexMonitor \(version) 已下載完成。"
        }
    }

    // MARK: - Section Headers

    static var displaySection: String {
        switch lang {
        case .en:    return "Display"
        case .ja:    return "表示"
        case .zhHans: return "显示"
        case .zhHant: return "顯示"
        }
    }

    static var notificationSection: String {
        switch lang {
        case .en:    return "Notifications"
        case .ja:    return "通知"
        case .zhHans: return "通知"
        case .zhHant: return "通知"
        }
    }

    static var generalSection: String {
        switch lang {
        case .en:    return "General"
        case .ja:    return "一般"
        case .zhHans: return "通用"
        case .zhHant: return "通用"
        }
    }
}
