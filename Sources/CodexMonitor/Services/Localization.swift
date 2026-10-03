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

    static var dashboardShort: String {
        switch lang {
        case .en: return "Dashboard"
        case .ja: return "公式"
        case .zhHans: return "官网"
        case .zhHant: return "官網"
        }
    }

    static var cachedShort: String {
        switch lang {
        case .en: return "Cached"
        case .ja: return "キャッシュ"
        case .zhHans: return "缓存"
        case .zhHant: return "快取"
        }
    }

    static func compactQuotaWindow(seconds: Int) -> String {
        let hours = seconds / 3600
        if hours >= 24 * 28 {
            switch lang {
            case .en: return "Month"
            case .ja: return "月"
            case .zhHans: return "每月"
            case .zhHant: return "每月"
            }
        }
        if hours >= 168 {
            switch lang {
            case .en: return "Week"
            case .ja: return "週"
            case .zhHans: return "每周"
            case .zhHant: return "每週"
            }
        }
        return "\(hours)h"
    }

    static func resetRelative(_ time: RelativeResetTime) -> String {
        switch lang {
        case .en:
            return "Reset: \(time.compactDescription)"
        case .ja:
            return "リセット: \(time.compactDescription)"
        case .zhHans:
            return "重置: \(time.compactDescription)"
        case .zhHant:
            return "重置: \(time.compactDescription)"
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

    static func compactDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()

        switch lang {
        case .en:
            formatter.locale = Locale(identifier: "en_US")
            formatter.dateFormat = "M/d HH:mm"
        case .ja:
            formatter.locale = Locale(identifier: "ja_JP")
            formatter.dateFormat = "M月d日 HH:mm"
        case .zhHans:
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "M月d日 HH:mm"
        case .zhHant:
            formatter.locale = Locale(identifier: "zh_TW")
            formatter.dateFormat = "M月d日 HH:mm"
        }

        return formatter.string(from: date)
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
        case .en:    return "\(accountName)'s \(limitType) has reset"
        case .ja:    return "\(accountName)の\(limitType)がリセットされました"
        case .zhHans: return "\(accountName) 的 \(limitType) 已刷新，现在可用"
        case .zhHant: return "\(accountName) 的 \(limitType) 已刷新，現在可用"
        }
    }

    static var recoveryNotificationTitle: String {
        switch lang {
        case .en:    return "Codex Quota Restored"
        case .ja:    return "Codex 上限が回復しました"
        case .zhHans: return "Codex 额度已恢复"
        case .zhHant: return "Codex 額度已恢復"
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

    static func monthlyLimit() -> String {
        switch lang {
        case .en:    return "Monthly Limit"
        case .ja:    return "月間上限"
        case .zhHans: return "每月限额"
        case .zhHant: return "每月限額"
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

    static var exportBackup: String {
        switch lang {
        case .en:    return "Export Backup"
        case .ja:    return "バックアップ書き出し"
        case .zhHans: return "导出备份"
        case .zhHant: return "匯出備份"
        }
    }

    static var importBackup: String {
        switch lang {
        case .en:    return "Import Backup"
        case .ja:    return "バックアップ取り込み"
        case .zhHans: return "导入备份"
        case .zhHant: return "匯入備份"
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

    // MARK: - Reset Credits

    static func resetCreditsAvailable(count: Int) -> String {
        switch lang {
        case .en:    return count == 1 ? "1 reset available" : "\(count) resets available"
        case .ja:    return "リセット \(count) 回利用可"
        case .zhHans: return "\(count) 次重置可用"
        case .zhHant: return "\(count) 次重置可用"
        }
    }

    static func resetCreditGranted(date: String) -> String {
        switch lang {
        case .en:    return "Granted \(date)"
        case .ja:    return "付与 \(date)"
        case .zhHans: return "授予 \(date)"
        case .zhHant: return "授予 \(date)"
        }
    }

    static func resetCreditExpires(date: String) -> String {
        switch lang {
        case .en:    return "Expires \(date)"
        case .ja:    return "期限 \(date)"
        case .zhHans: return "到期 \(date)"
        case .zhHant: return "到期 \(date)"
        }
    }

    static var resetCreditDatesUnavailable: String {
        switch lang {
        case .en:    return "Dates unavailable"
        case .ja:    return "日時不明"
        case .zhHans: return "暂无日期"
        case .zhHant: return "暫無日期"
        }
    }

    static func resetCreditsMore(count: Int) -> String {
        switch lang {
        case .en:    return "+\(count) more"
        case .ja:    return "ほか \(count) 件"
        case .zhHans: return "另有 \(count) 次"
        case .zhHant: return "另有 \(count) 次"
        }
    }

    static var claudeResetCreditsUsagePage: String {
        localized("View in Claude", "Claude で確認", "前往 Claude 查看", "前往 Claude 查看")
    }

    static var resetCreditRequiresLimit: String {
        localized("Use after reaching a limit", "上限到達後に利用可", "达到限额后可使用", "達到限額後可使用")
    }

    static func resetCreditScope(_ resetType: String?) -> String {
        let windows = Set((resetType ?? "").split(separator: ",").map(String.init))
        var scopes: [String] = []
        if windows.contains("five_hour") {
            scopes.append(localized("5-hour", "5時間", "5 小时", "5 小時"))
        }
        if windows.contains("seven_day") {
            scopes.append(localized("weekly", "週間", "每周", "每週"))
        } else {
            for (key, label) in [("seven_day_opus", "Opus"), ("seven_day_sonnet", "Sonnet"),
                                 ("seven_day_cowork", "Cowork"), ("seven_day_oauth_apps", "OAuth apps")] {
                if windows.contains(key) { scopes.append(label) }
            }
        }
        return scopes.joined(separator: " / ")
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

    static var settingsTabAccounts: String {
        switch lang {
        case .en:    return "Accounts"
        case .ja:    return "アカウント"
        case .zhHans: return "账号"
        case .zhHant: return "帳號"
        }
    }

    static var settingsTabPreferences: String {
        switch lang {
        case .en:    return "Settings"
        case .ja:    return "設定"
        case .zhHans: return "设置"
        case .zhHant: return "設定"
        }
    }

    static var settingsTabAbout: String {
        switch lang {
        case .en:    return "About"
        case .ja:    return "情報"
        case .zhHans: return "关于"
        case .zhHant: return "關於"
        }
    }

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

    static func aboutVersion(version: String) -> String {
        switch lang {
        case .en:    return "Version \(version)"
        case .ja:    return "バージョン \(version)"
        case .zhHans: return "版本 \(version)"
        case .zhHant: return "版本 \(version)"
        }
    }

    static var aboutCopyright: String {
        switch lang {
        case .en:    return "© Ryan Hansen. All rights reserved."
        case .ja:    return "© Ryan Hansen. All rights reserved."
        case .zhHans: return "© Ryan Hansen。保留所有权利。"
        case .zhHant: return "© Ryan Hansen。保留所有權利。"
        }
    }

    static var aboutGitHub: String {
        switch lang {
        case .en:    return "GitHub"
        case .ja:    return "GitHub"
        case .zhHans: return "GitHub 主页"
        case .zhHant: return "GitHub 主頁"
        }
    }

    static var aboutLicense: String {
        switch lang {
        case .en:    return "License"
        case .ja:    return "ライセンス"
        case .zhHans: return "开源协议"
        case .zhHant: return "開源協議"
        }
    }

    static var aboutX: String {
        switch lang {
        case .en:    return "X"
        case .ja:    return "X"
        case .zhHans: return "X 主页"
        case .zhHant: return "X 主頁"
        }
    }

    static var aboutFeedback: String {
        switch lang {
        case .en:    return "Email Feedback"
        case .ja:    return "メールでフィードバック"
        case .zhHans: return "邮件反馈"
        case .zhHant: return "郵件回饋"
        }
    }

    static var aboutAcknowledgements: String {
        switch lang {
        case .en:    return "Acknowledgements"
        case .ja:    return "謝辞"
        case .zhHans: return "致谢"
        case .zhHant: return "致謝"
        }
    }

    static var aboutCodexResetAcknowledgement: String {
        switch lang {
        case .en:
            return "Thanks to Codex Reset Observatory, an independent community project, for the public API used for reset forecasts and Tibo's public signals. Codex Reset Observatory is not affiliated with OpenAI."
        case .ja:
            return "リセット予測と Tibo の公開シグナルに使用する公開 API を提供している、独立したコミュニティプロジェクト Codex Reset Observatory に感謝します。Codex Reset Observatory は OpenAI とは提携していません。"
        case .zhHans:
            return "感谢独立社区项目 Codex Reset Observatory 提供用于重置预测和 Tibo 公开信号的公共 API。Codex Reset Observatory 与 OpenAI 无隶属或合作关系。"
        case .zhHant:
            return "感謝獨立社群專案 Codex Reset Observatory 提供用於重置預測與 Tibo 公開訊號的公開 API。Codex Reset Observatory 與 OpenAI 無隸屬或合作關係。"
        }
    }

    static var aboutReferences: String {
        switch lang {
        case .en:    return "API references"
        case .ja:    return "API 参照"
        case .zhHans: return "API 引用"
        case .zhHant: return "API 引用"
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

    static var accountActions: String {
        localized("Account settings", "アカウント設定", "账号设置", "帳號設定")
    }

    static var hideAccount: String {
        localized("Hide Account", "アカウントを非表示", "隐藏账号", "隱藏帳號")
    }

    static var showAccount: String {
        localized("Show Account", "アカウントを表示", "显示账号", "顯示帳號")
    }

    static var accountHidden: String {
        localized("Hidden from menu bar", "メニューバーで非表示", "已从菜单栏隐藏", "已從選單列隱藏")
    }

    static var allAccountsHidden: String {
        localized("All accounts are hidden", "すべてのアカウントが非表示です", "所有账号均已隐藏", "所有帳號均已隱藏")
    }

    static var manageAccounts: String {
        localized("Manage Accounts", "アカウントを管理", "管理账号", "管理帳號")
    }

    static var dragAccountToReorder: String {
        localized("Drag to reorder", "ドラッグして並べ替え", "拖动调整顺序", "拖動調整順序")
    }

    static func deleteAccountConfirmation(accountName: String) -> String {
        localized(
            "Delete \"\(accountName)\"? Saved credentials and local quota data for this account will also be removed. This cannot be undone.",
            "「\(accountName)」を削除しますか？保存された認証情報とローカルのクォータデータも削除されます。この操作は取り消せません。",
            "确定删除“\(accountName)”吗？该账号保存的凭证和本地额度数据也会一并删除，此操作无法撤销。",
            "確定刪除「\(accountName)」嗎？該帳號儲存的憑證和本機額度資料也會一併刪除，此操作無法復原。"
        )
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
        case .en:    return "Periodically fetch latest cloud quota usage. Refreshing too often may trigger rate limits."
        case .ja:    return "クラウドの最新使用量を定期的に取得します。更新頻度が高すぎるとレート制限される場合があります。"
        case .zhHans: return "定期静默拉取最新云端配额用量，刷新过于频繁可能触发限流。"
        case .zhHant: return "定期靜默拉取最新雲端配額用量，重新整理過於頻繁可能觸發限流。"
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

    static var showResetRadar: String {
        switch lang {
        case .en:    return "Show Codex Reset Radar"
        case .ja:    return "Codex Reset Radarを表示"
        case .zhHans: return "显示 Codex Reset Radar"
        case .zhHant: return "顯示 Codex Reset Radar"
        }
    }

    static var showResetRadarDesc: String {
        switch lang {
        case .en:    return "Show the community reset forecast above account quotas"
        case .ja:    return "アカウントの利用枠の上にコミュニティのリセット予測を表示"
        case .zhHans: return "在账户额度上方显示社区重置概率预测"
        case .zhHant: return "在帳戶額度上方顯示社群重置機率預測"
        }
    }

    static var showQuotaAllowanceSummary: String {
        switch lang {
        case .en: return "Show weekly allowance conversion"
        case .ja: return "週間残量の5時間枠換算を表示"
        case .zhHans: return "显示周额度换算提示"
        case .zhHant: return "顯示週額度換算提示"
        }
    }

    static var showQuotaAllowanceSummaryDesc: String {
        switch lang {
        case .en: return "Show the remaining number of complete 5-hour allowances inside the weekly quota"
        case .ja: return "週間クォータ内に、完全な5時間枠の残り回数を表示します"
        case .zhHans: return "在周额度内部显示还相当于多少个完整的 5 小时额度"
        case .zhHant: return "在週額度內部顯示還相當於多少個完整的 5 小時額度"
        }
    }

    static func quotaAllowanceSummary(_ summary: QuotaAllowanceSummary) -> String {
        guard let equivalents = summary.remainingFiveHourEquivalents else {
            switch lang {
            case .en: return "Calibrating"
            case .ja: return "調整中"
            case .zhHans: return "校准中"
            case .zhHant: return "校準中"
            }
        }
        let value = String(format: "%.1f", equivalents)
        switch lang {
        case .en, .ja, .zhHans, .zhHant: return "≈\(value)×5h"
        }
    }

    static func quotaAllowanceHelp(summary: QuotaAllowanceSummary) -> String {
        if summary.source == .calibrating {
            switch lang {
            case .en: return "The approximate ratio appears after the first measurable paired usage change, then keeps correcting itself."
            case .ja: return "最初の測定可能な同時利用変化の後に概算比率を表示し、その後も継続して補正します。"
            case .zhHans: return "首次观察到可测量的成对用量变化后即显示近似倍数，之后会持续自动修正。"
            case .zhHant: return "首次觀察到可測量的成對用量變化後即顯示近似倍數，之後會持續自動修正。"
            }
        }

        let value = String(format: "%.2f", summary.remainingFiveHourEquivalents ?? 0)
        let ratio = String(format: "%.2f", summary.capacityRatio ?? 0)
        switch (lang, summary.source) {
        case (.en, .exactOpenCodeGo): return "OpenCode Go: $30 weekly ÷ $12 per 5h = 2.5×. At \(summary.weeklyRemainingPercent)% weekly remaining, about \(value) complete 5h allowances remain."
        case (.en, .estimatedBaseline): return "Uses an initial full-5h capacity baseline of \(ratio)×. Current 5h remaining is not part of the calculation; account observations will refine the ratio automatically."
        case (.en, .learned): return "This account's observed weekly-to-5h capacity ratio is about \(ratio)×. At \(summary.weeklyRemainingPercent)% weekly remaining, about \(value) complete 5h allowances remain."
        case (.ja, .exactOpenCodeGo): return "OpenCode Go: 週$30 ÷ 5時間$12 = 2.5倍。週間残量\(summary.weeklyRemainingPercent)%は、完全な5時間枠約\(value)回分です。"
        case (.ja, .estimatedBaseline): return "完全な5時間枠を基準に、初期容量比\(ratio)倍で計算します。現在の5時間残量は計算に含めず、実測後に自動補正します。"
        case (.ja, .learned): return "このアカウントで観測した週/5時間容量比は約\(ratio)倍です。週間残量\(summary.weeklyRemainingPercent)%は、完全な5時間枠約\(value)回分です。"
        case (.zhHans, .exactOpenCodeGo): return "OpenCode Go：每周 $30 ÷ 每 5 小时 $12 = 2.5 倍。当前周余 \(summary.weeklyRemainingPercent)%，约等于 \(value) 个完整 5 小时额度。"
        case (.zhHans, .estimatedBaseline): return "按完整 100% 的 5 小时额度，以 \(ratio) 倍初始容量比计算；当前 5 小时剩余不参与计算，获得账号实测数据后会自动修正。"
        case (.zhHans, .learned): return "根据该账号实际消耗校准，周/5 小时容量比约为 \(ratio) 倍。当前周余 \(summary.weeklyRemainingPercent)%，约等于 \(value) 个完整 5 小时额度。"
        case (.zhHant, .exactOpenCodeGo): return "OpenCode Go：每週 $30 ÷ 每 5 小時 $12 = 2.5 倍。目前週餘 \(summary.weeklyRemainingPercent)%，約等於 \(value) 個完整 5 小時額度。"
        case (.zhHant, .estimatedBaseline): return "按完整 100% 的 5 小時額度，以 \(ratio) 倍初始容量比計算；目前 5 小時剩餘不參與計算，取得帳戶實測資料後會自動修正。"
        case (.zhHant, .learned): return "根據該帳戶實際消耗校準，週/5 小時容量比約為 \(ratio) 倍。目前週餘 \(summary.weeklyRemainingPercent)%，約等於 \(value) 個完整 5 小時額度。"
        case (_, .calibrating): return ""
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

    static var agentType: String {
        switch lang {
        case .en: return "Agent Type"
        case .ja: return "エージェント種類"
        case .zhHans: return "Agent 类型"
        case .zhHant: return "Agent 類型"
        }
    }

    static func accountSheetTitle(provider: AccountProvider, editing: Bool) -> String {
        switch lang {
        case .en: return "\(editing ? "Edit" : "Add") \(provider.displayName) Account"
        case .ja: return "\(provider.displayName) アカウントを\(editing ? "編集" : "追加")"
        case .zhHans: return "\(editing ? "编辑" : "添加") \(provider.displayName) 账户"
        case .zhHant: return "\(editing ? "編輯" : "新增") \(provider.displayName) 帳戶"
        }
    }

    static func providerAccountName(_ provider: AccountProvider) -> String {
        "\(provider.displayName) \(accountName)"
    }

    static func providerAccountNamePlaceholder(_ provider: AccountProvider) -> String {
        switch lang {
        case .en: return "e.g., Work \(provider.displayName)"
        case .ja: return "例: 仕事用 \(provider.displayName)"
        case .zhHans: return "例如：工作 \(provider.displayName)"
        case .zhHant: return "例如：工作 \(provider.displayName)"
        }
    }

    static func providerAccountEmail(_ provider: AccountProvider) -> String {
        "\(provider.displayName) Email"
    }

    static func credentialLabel(_ provider: AccountProvider) -> String {
        switch provider {
        case .codex: return "ChatGPT Bearer Token"
        case .claude: return "Claude OAuth Token / Auth JSON"
        case .grok: return "Grok Token / Cookie / Auth JSON"
        case .openCodeGo: return "OpenCode Go Session Cookie"
        }
    }

    static func credentialPlaceholder(_ provider: AccountProvider) -> String {
        switch provider {
        case .codex: return "Bearer eyJ..."
        case .claude: return "sk-ant-oat01-... or Claude auth JSON"
        case .grok: return "Bearer token, Cookie header, or Grok auth JSON"
        case .openCodeGo: return "Fe26.2**… or auth=Fe26.2**…"
        }
    }

    static func claudeUsageRateLimited(retryAt: Date) -> String {
        let time = retryAt.formatted(date: .abbreviated, time: .shortened)
        switch lang {
        case .en: return "Claude usage requests are temporarily limited. Retry after \(time)."
        case .ja: return "Claude の使用量取得が一時的に制限されています。\(time) 以降に再試行します。"
        case .zhHans: return "Claude 用量查询暂时受限，将在 \(time) 后重试。"
        case .zhHant: return "Claude 用量查詢暫時受限，將在 \(time) 後重試。"
        }
    }

    static func cachedUsageAsOf(_ fetchedAt: Date) -> String {
        let time = fetchedAt.formatted(date: .abbreviated, time: .shortened)
        switch lang {
        case .en: return "Showing saved usage from \(time)."
        case .ja: return "\(time) に取得した使用量を表示しています。"
        case .zhHans: return "当前显示 \(time) 获取的上次数据。"
        case .zhHant: return "目前顯示 \(time) 取得的上次資料。"
        }
    }

    static func credentialHint(_ provider: AccountProvider) -> String {
        switch (lang, provider) {
        case (.en, .codex): return "Copy the Bearer token from the ChatGPT usage request."
        case (.en, .claude): return "Paste a Claude Bearer token or auth JSON. Local login is imported when accessible without a password prompt."
        case (.en, .grok): return "Paste a Grok token/auth JSON, or the full Cookie header from GetGrokCreditsConfig."
        case (.en, .openCodeGo): return "Copy auth or __Host-auth from an opencode.ai request in your browser DevTools."
        case (.ja, .codex): return "ChatGPT の使用量リクエストから Bearer トークンをコピーします。"
        case (.ja, .claude): return "Claude のトークンまたは auth JSON を貼り付けます。パスワード入力なしで読み取れるローカルログインは自動インポートされます。"
        case (.ja, .grok): return "Grok のトークン/auth JSON、または GetGrokCreditsConfig の Cookie を貼り付けます。"
        case (.ja, .openCodeGo): return "ブラウザの DevTools で opencode.ai リクエストの auth または __Host-auth をコピーします。"
        case (.zhHans, .codex): return "从 ChatGPT 用量请求中复制 Bearer Token。"
        case (.zhHans, .claude): return "粘贴 Claude Token 或 auth JSON；可免密码提示读取的本地登录会自动导入。"
        case (.zhHans, .grok): return "粘贴 Grok Token/auth JSON，或 GetGrokCreditsConfig 的完整 Cookie。"
        case (.zhHans, .openCodeGo): return "从浏览器开发者工具中的 opencode.ai 请求复制 auth 或 __Host-auth。"
        case (.zhHant, .codex): return "從 ChatGPT 用量請求中複製 Bearer Token。"
        case (.zhHant, .claude): return "貼上 Claude Token 或 auth JSON；可免密碼提示讀取的本機登入會自動匯入。"
        case (.zhHant, .grok): return "貼上 Grok Token/auth JSON，或 GetGrokCreditsConfig 的完整 Cookie。"
        case (.zhHant, .openCodeGo): return "從瀏覽器開發者工具中的 opencode.ai 請求複製 auth 或 __Host-auth。"
        }
    }

    static var openCodeWorkspaceID: String {
        switch lang {
        case .en: return "Workspace ID (Optional)"
        case .ja: return "Workspace ID（任意）"
        case .zhHans: return "Workspace ID（可选）"
        case .zhHant: return "Workspace ID（選填）"
        }
    }

    static var openCodeWorkspacePlaceholder: String {
        "wrk_… / wk_…"
    }

    static var openCodeWorkspaceHint: String {
        switch lang {
        case .en: return "Leave blank for automatic lookup. If needed, copy it from /workspace/wrk_…/go."
        case .ja: return "通常は空欄。自動検出に失敗した場合は /workspace/wrk_…/go からコピーします。"
        case .zhHans: return "通常留空自动获取；失败时从 /workspace/wrk_…/go 地址中复制。"
        case .zhHant: return "通常留空自動取得；失敗時從 /workspace/wrk_…/go 網址中複製。"
        }
    }

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

    static var accountEmail: String {
        switch lang {
        case .en:    return "Codex Account Email"
        case .ja:    return "Codex アカウントのメール"
        case .zhHans: return "Codex 账号邮箱"
        case .zhHant: return "Codex 帳號信箱"
        }
    }

    static var accountEmailPlaceholder: String {
        switch lang {
        case .en:    return "email@example.com"
        case .ja:    return "email@example.com"
        case .zhHans: return "email@example.com"
        case .zhHant: return "email@example.com"
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

    static var refresh10Minutes: String {
        switch lang {
        case .en:    return "10 Minutes"
        case .ja:    return "10分"
        case .zhHans: return "10 分钟"
        case .zhHant: return "10 分鐘"
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

    static var refresh20Minutes: String {
        switch lang {
        case .en:    return "20 Minutes"
        case .ja:    return "20分"
        case .zhHans: return "20 分钟"
        case .zhHant: return "20 分鐘"
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
        case .en:    return "Monitor ~/.codex/auth.json changes, including cc-switch, and save full login bundles for all-account weekly activation"
        case .ja:    return "cc-switch を含む ~/.codex/auth.json の変更を監視し、全アカウントの週間サイクル開始に必要なログイン情報を保存"
        case .zhHans: return "监听 ~/.codex/auth.json 变化，包括 cc-switch 切换，并保存用于全账号周额度刷新的完整登录凭证"
        case .zhHant: return "監聽 ~/.codex/auth.json 變化，包括 cc-switch 切換，並保存用於全帳戶週額度刷新的完整登入憑證"
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

    static var notificationTestAccountName: String {
        switch lang {
        case .en:    return "Codex account"
        case .ja:    return "Codex アカウント"
        case .zhHans: return "Codex 账户"
        case .zhHant: return "Codex 帳戶"
        }
    }

    // MARK: - Quota Activation

    static var quotaAutomationSection: String { localized("Quota Automation (Beta)", "クォータ自動化 (Beta)", "额度自动刷新 (Beta)", "額度自動重新整理 (Beta)") }
    static var fiveHourRefreshLabel: String { localized("Refresh the 5-hour quota at a fixed time", "固定時刻に5時間クォータを更新", "在固定时间刷新 5 小时额度", "在固定時間重新整理 5 小時額度") }
    static var fiveHourRefreshDesc: String { localized("Start the first 5-hour window before work, so more complete quota windows fit into your day", "仕事前に最初の5時間枠を開始し、1日に使える完全な枠を増やします", "在工作前提前开启首个 5 小时窗口，让一天内能衔接更多完整额度周期", "在工作前提前開啟首個 5 小時視窗，讓一天內能銜接更多完整額度週期") }
    static var refreshTimeLabel: String { localized("Daily refresh time", "毎日の更新時刻", "每日刷新时间", "每日重新整理時間") }
    static var refreshTimeDesc: String { localized("For example, refresh at 5:00 before starting work at 8:00", "例：8時に仕事を始める前の5時に更新", "例如 8 点开始工作，可设为 5 点提前刷新", "例如 8 點開始工作，可設為 5 點提前重新整理") }
    static var advancedSettingsLabel: String { localized("Advanced settings", "詳細設定", "高级设置", "進階設定") }
    static var advancedSettingsDesc: String { localized("Per-account time and model", "アカウント別時刻とモデル", "按账号设置时间和模型", "按帳戶設定時間和模型") }
    static var refreshModelLabel: String { localized("Request model", "リクエストモデル", "自动请求模型", "自動請求模型") }
    static var refreshModelDesc: String { localized("Loaded live from Codex", "Codexからリアルタイム取得", "从 Codex 实时获取", "從 Codex 即時取得") }
    static var modelCacheUnavailable: String { localized("No models loaded", "モデル未取得", "未获取到模型", "未取得模型") }
    static var refreshModels: String { localized("Refresh", "更新", "刷新", "重新整理") }
    static var loadingModels: String { localized("Loading…", "取得中…", "获取中…", "取得中…") }
    static var wakeMacLabel: String { localized("Wake Mac automatically", "Macを自動的に起動解除", "自动唤醒 Mac", "自動喚醒 Mac") }
    static var wakeMacDesc: String { localized("Required for reliable refresh while the Mac is asleep", "Macのスリープ中も確実に更新するため必須", "必须开启，否则 Mac 睡眠时可能无法发送刷新请求", "必須開啟，否則 Mac 睡眠時可能無法傳送重新整理請求") }
    static var wakeScheduleFailed: String { localized("Automatic wake was not enabled", "自動起動解除を有効にできませんでした", "未能启用自动唤醒", "未能啟用自動喚醒") }
    static var wakeRequiredFailed: String { localized("Automatic wake is required to enable this feature", "この機能には自動起動解除が必要です", "启用此功能必须先开启自动唤醒", "啟用此功能必須先開啟自動喚醒") }
    static var wakeScheduleCancelFailed: String {
        localized("Refresh is off, but the system wake schedule could not be removed. Retry and authorize the change.", "更新はオフですが、システムの起動予約を解除できませんでした。再試行して変更を許可してください。", "定时刷新已停止，但系统唤醒定时未能关闭，请重试并允许系统授权。", "定時重新整理已停止，但系統喚醒排程未能關閉，請重試並允許系統授權。")
    }
    static var wakeScheduleCleanupNeeded: String {
        localized("A saved wake schedule still needs cleanup.", "保存された起動予約の解除が必要です。", "仍有已保存的系统唤醒定时需要清理。", "仍有已儲存的系統喚醒排程需要清理。")
    }
    static var cancelWakeSchedule: String {
        localized("Remove system wake schedule", "システムの起動予約を解除", "关闭系统定时", "關閉系統排程")
    }
    static var modelsLoadedLive: String { localized("Live model list", "リアルタイムモデル一覧", "实时模型列表", "即時模型列表") }
    static var modelsLoadedFromCache: String { localized("Using Codex's last synced model list", "Codexの最終同期モデル一覧を使用", "正在使用 Codex 最近同步的模型列表", "正在使用 Codex 最近同步的模型列表") }
    static var modelsUnavailable: String { localized("Open Codex once, then refresh", "Codexを一度開いてから更新してください", "请先打开一次 Codex，然后刷新", "請先開啟一次 Codex，然後重新整理") }
    static var fiveHourRefreshScopeNote: String { localized("CodexMonitor must be running. Auto Account Sync is required to refresh saved accounts; the request is exactly “Reply only: hi”.", "CodexMonitorの起動が必要です。保存済みアカウントには自動同期が必要です。リクエストは「Reply only: hi」のみです。", "CodexMonitor 需保持运行；刷新已保存账号需开启自动账号同步。请求内容固定为“Reply only: hi”。", "CodexMonitor 需保持執行；重新整理已儲存帳戶需開啟自動帳戶同步。請求內容固定為「Reply only: hi」。") }
    static var fiveHourRefreshFailureTitle: String { localized("Quota refresh failed", "クォータ更新に失敗", "额度刷新失败", "額度重新整理失敗") }
    static func fiveHourRefreshFailureBody(accountName: String, reason: String) -> String {
        localized(
            "\(accountName): \(reason)",
            "\(accountName)：\(reason)",
            "\(accountName)：\(reason)",
            "\(accountName)：\(reason)"
        )
    }
    static var reconnectAccount: String {
        localized("Reconnect account", "アカウントを再接続", "重新连接账号", "重新連接帳戶")
    }
    static func reconnectAccountRunning(provider: String) -> String {
        localized(
            "Complete the \(provider) sign-in in your browser…",
            "ブラウザで \(provider) のサインインを完了してください…",
            "请在浏览器中完成 \(provider) 登录…",
            "請在瀏覽器中完成 \(provider) 登入…"
        )
    }
    static var reconnectAccountSucceeded: String {
        localized("Account reconnected", "アカウントを再接続しました", "账号已重新连接", "帳戶已重新連接")
    }

    private static func localized(_ en: String, _ ja: String, _ zhHans: String, _ zhHant: String) -> String {
        switch lang { case .en: en; case .ja: ja; case .zhHans: zhHans; case .zhHant: zhHant }
    }

    static var quotaActivationSection: String {
        switch lang {
        case .en:    return "Weekly Quota Cycle"
        case .ja:    return "週間上限サイクル"
        case .zhHans: return "每周额度周期"
        case .zhHant: return "每週額度週期"
        }
    }

    static var quotaActivationLabel: String {
        switch lang {
        case .en:    return "Start a new cycle after weekly quota recovery"
        case .ja:    return "週間上限の回復後に新しいサイクルを開始"
        case .zhHans: return "每周额度恢复后启动新周期"
        case .zhHant: return "每週額度恢復後啟動新週期"
        }
    }

    static var quotaActivationDesc: String {
        switch lang {
        case .en:    return "Checks at least hourly and sends one short request only when the weekly quota is 100% remaining"
        case .ja:    return "少なくとも1時間ごとに確認し、週間クォータが 100% 残っている場合のみ短いリクエストを1回送信します"
        case .zhHans: return "至少每小时检查一次，仅在周额度剩余 100% 时发送一次简短请求"
        case .zhHant: return "至少每小時檢查一次，僅在每週額度剩餘 100% 時傳送一次簡短請求"
        }
    }

    static var quotaActivationScopeNote: String {
        switch lang {
        case .en:    return "After a successful request, that account is scheduled again in 7 days. Auto Import Local Accounts is required to retain every switched login."
        case .ja:    return "成功後、そのアカウントは7日後に再度確認されます。切り替えたログインを保持するにはローカルアカウント自動インポートが必要です。"
        case .zhHans: return "请求成功后会固定在 7 天后再次检查该账号；需开启“自动导入本地账户”以保留每次切换的完整登录凭证。"
        case .zhHant: return "請求成功後會固定在 7 天後再次檢查該帳戶；需開啟「自動匯入本地帳戶」以保留每次切換的完整登入憑證。"
        }
    }

    static var quotaActivationCodexNotFound: String {
        switch lang {
        case .en:    return "Codex CLI was not found on this Mac."
        case .ja:    return "この Mac に Codex CLI が見つかりません。"
        case .zhHans: return "本机未找到 Codex CLI。"
        case .zhHant: return "本機未找到 Codex CLI。"
        }
    }

    static var manualWeeklyRefreshLabel: String {
        localized(
            "Refresh full weekly quotas now",
            "週間クォータが満量のアカウントを今すぐ更新",
            "手动刷新周额度",
            "手動重新整理每週額度"
        )
    }

    static var manualWeeklyRefreshDesc: String {
        localized(
            "Send one short request only for Codex accounts with 100% weekly quota remaining",
            "週間クォータが 100% 残っている Codex アカウントにのみ短いリクエストを1回送信します",
            "仅向周额度剩余 100% 的 Codex 账号发送一次简短请求",
            "僅向每週額度剩餘 100% 的 Codex 帳戶傳送一次簡短請求"
        )
    }

    static var manualWeeklyRefreshButton: String {
        localized("Refresh 100% accounts", "100% のアカウントを更新", "刷新 100% 账号", "重新整理 100% 帳戶")
    }

    static var manualWeeklyRefreshRunning: String {
        localized("Refreshing…", "更新中…", "正在刷新…", "正在重新整理…")
    }

    static var manualWeeklyRefreshNone: String {
        localized(
            "No Codex account currently has 100% weekly quota remaining",
            "週間クォータが 100% 残っている Codex アカウントはありません",
            "当前没有周额度剩余 100% 的 Codex 账号",
            "目前沒有每週額度剩餘 100% 的 Codex 帳戶"
        )
    }

    static func manualWeeklyRefreshSucceeded(_ count: Int) -> String {
        localized(
            "Refreshed \(count) account(s)",
            "\(count) 件のアカウントを更新しました",
            "已刷新 \(count) 个账号",
            "已重新整理 \(count) 個帳戶"
        )
    }

    static func manualWeeklyRefreshPartial(succeeded: Int, total: Int) -> String {
        localized(
            "Refreshed \(succeeded) of \(total) accounts; the rest lacked complete credentials or the request failed",
            "\(total) 件中 \(succeeded) 件を更新しました。残りは完全な認証情報がないか、リクエストに失敗しました",
            "已刷新 \(succeeded)/\(total) 个账号，其余账号缺少完整凭证或请求失败",
            "已重新整理 \(succeeded)/\(total) 個帳戶，其餘帳戶缺少完整憑證或請求失敗"
        )
    }

    static var manualAccountWeeklyRefreshHelp: String {
        localized(
            "Force refresh this account's weekly quota, regardless of the displayed percentage",
            "表示されている割合に関係なく、このアカウントの週間クォータを強制更新",
            "忽略当前显示百分比，强制刷新此账号的周额度",
            "忽略目前顯示百分比，強制重新整理此帳戶的每週額度"
        )
    }

    static var manualAccountWeeklyRefreshRunning: String {
        localized("Refreshing this account…", "このアカウントを更新中…", "正在刷新此账号…", "正在重新整理此帳戶…")
    }

    static var manualAccountWeeklyRefreshQueued: String {
        localized(
            "Waiting for the current quota refresh to finish…",
            "実行中のクォータ更新が完了するまで待機しています…",
            "正在等待当前额度刷新完成…",
            "正在等待目前額度重新整理完成…"
        )
    }

    static var manualAccountWeeklyRefreshSucceeded: String {
        localized("Weekly quota refreshed", "週間クォータを更新しました", "周额度刷新成功", "每週額度重新整理成功")
    }

    static var manualAccountWeeklyRefreshFailed: String {
        localized("Refresh failed; try again or check the quota log", "更新に失敗しました。再試行するかクォータログを確認してください", "刷新失败，请重试或检查额度日志", "重新整理失敗，請重試或檢查額度日誌")
    }

    static var manualAccountWeeklyRefreshBusy: String {
        localized("Another quota refresh is already running", "別のクォータ更新が実行中です", "另一个额度刷新正在进行中", "另一個額度重新整理正在進行中")
    }

    static var manualAccountWeeklyRefreshMissingCredentials: String {
        localized("This account has no complete saved credentials", "このアカウントには完全な認証情報が保存されていません", "此账号没有保存完整凭证", "此帳戶沒有儲存完整憑證")
    }

    static var manualAccountWeeklyRefreshUnavailable: String {
        localized("This account cannot be refreshed", "このアカウントは更新できません", "此账号无法刷新", "此帳戶無法重新整理")
    }

    static var manualAccountWeeklyRefreshTimedOut: String {
        localized(
            "Refresh timed out after 2 minutes. Check the network and try again.",
            "2分後に更新がタイムアウトしました。ネットワークを確認して再試行してください。",
            "刷新请求在 2 分钟后超时，请检查网络后重试。",
            "重新整理請求在 2 分鐘後逾時，請檢查網路後重試。"
        )
    }

    static var manualAccountWeeklyRefreshLaunchFailed: String {
        localized(
            "Codex could not be launched. Check the quota log for details.",
            "Codex を起動できませんでした。詳細はクォータログを確認してください。",
            "无法启动 Codex，请查看额度日志了解详情。",
            "無法啟動 Codex，請查看額度日誌了解詳情。"
        )
    }

    static func manualAccountWeeklyRefreshCommandFailed(exitStatus: Int32) -> String {
        localized(
            "Codex exited with status \(exitStatus). Check credentials, network, or the quota log.",
            "Codex がステータス \(exitStatus) で終了しました。認証情報、ネットワーク、またはクォータログを確認してください。",
            "Codex 请求失败（退出码 \(exitStatus)），请检查凭证、网络或额度日志。",
            "Codex 請求失敗（結束碼 \(exitStatus)），請檢查憑證、網路或額度日誌。"
        )
    }

    static var manualAccountWeeklyRefreshUnexpectedReply: String {
        localized(
            "Codex returned an unexpected response, so the refresh was not recorded.",
            "Codex から予期しない応答が返されたため、更新は記録されませんでした。",
            "Codex 返回了非预期结果，本次刷新未记为成功。",
            "Codex 回傳了非預期結果，本次重新整理未記為成功。"
        )
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

    static var notificationsNotAllowed: String {
        switch lang {
        case .en:    return "macOS has not allowed notifications for this app. Open Notification Settings or reinstall the latest signed version."
        case .ja:    return "macOS がこのアプリの通知を許可していません。通知設定を開くか、最新の署名済みバージョンを再インストールしてください。"
        case .zhHans: return "macOS 尚未允许此应用发送通知。请打开通知设置，或重新安装最新的已签名版本。"
        case .zhHant: return "macOS 尚未允許此應用程式傳送通知。請開啟通知設定，或重新安裝最新的已簽名版本。"
        }
    }

    static var openNotificationSettingsButton: String {
        switch lang {
        case .en:    return "Notification Settings"
        case .ja:    return "通知設定"
        case .zhHans: return "通知设置"
        case .zhHant: return "通知設定"
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
        case .en:    return "Schedule a notification for the fixed 5-hour or weekly quota reset time"
        case .ja:    return "5時間または週間クォータの固定リセット時刻に通知"
        case .zhHans: return "按 5 小时或每周额度的固定重置时间发送系统通知"
        case .zhHant: return "按 5 小時或每週額度的固定重置時間傳送系統通知"
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
