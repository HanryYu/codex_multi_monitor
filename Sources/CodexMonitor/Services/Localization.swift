import Foundation

// MARK: - Language Detection

enum AppLanguage: String {
    case en
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case ja
}

struct LocaleManager {
    static let shared = LocaleManager()

    let currentLanguage: AppLanguage

    private init() {
        let locale = Locale.current
        let identifier = locale.identifier  // e.g. "zh-Hans_CN", "zh_TW", "ja_JP"
        let langCode = locale.language.languageCode?.identifier ?? "en"
        let region = locale.language.region?.identifier ?? ""

        if langCode == "ja" {
            currentLanguage = .ja
        } else if langCode == "zh" {
            // Determine Simplified vs Traditional by identifier or region
            if identifier.contains("Hant") || identifier.contains("TW") || identifier.contains("HK") || identifier.contains("MO") || region == "TW" || region == "HK" || region == "MO" {
                currentLanguage = .zhHant
            } else {
                currentLanguage = .zhHans
            }
        } else {
            currentLanguage = .en
        }
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
}
