import Foundation

enum MenuBarQuotaL10n {
    private static var language: AppLanguage { LocaleManager.shared.currentLanguage }

    static var menuBarSection: String {
        switch language {
        case .en: return "Menu Bar"
        case .zhHans: return "菜单栏"
        case .zhHant: return "選單列"
        case .ja: return "メニューバー"
        }
    }

    static var menuBarStyleSection: String {
        switch language {
        case .en: return "Menu Bar Style"
        case .zhHans: return "菜单栏样式"
        case .zhHant: return "選單列樣式"
        case .ja: return "メニューバーのスタイル"
        }
    }

    static var accountsSection: String {
        switch language {
        case .en: return "Accounts"
        case .zhHans: return "账号"
        case .zhHant: return "帳號"
        case .ja: return "アカウント"
        }
    }

    static var appearancePreview: String {
        switch language {
        case .en: return "Preview"
        case .zhHans: return "预览"
        case .zhHant: return "預覽"
        case .ja: return "プレビュー"
        }
    }

    static func previewRemaining(_ percentage: Int) -> String {
        switch language {
        case .en: return "Remaining \(percentage)%"
        case .zhHans: return "剩余 \(percentage)%"
        case .zhHant: return "剩餘 \(percentage)%"
        case .ja: return "残り \(percentage)%"
        }
    }

    static var numberPosition: String {
        switch language {
        case .en: return "Number position"
        case .zhHans: return "数字位置"
        case .zhHant: return "數字位置"
        case .ja: return "数字の位置"
        }
    }

    static var numberLeading: String {
        switch language {
        case .en: return "Left"
        case .zhHans: return "左侧"
        case .zhHant: return "左側"
        case .ja: return "左"
        }
    }

    static var numberInside: String {
        switch language {
        case .en: return "Inside"
        case .zhHans: return "环内"
        case .zhHant: return "環內"
        case .ja: return "内側"
        }
    }

    static var numberTrailing: String {
        switch language {
        case .en: return "Right"
        case .zhHans: return "右侧"
        case .zhHant: return "右側"
        case .ja: return "右"
        }
    }

    static var insideNumberHelp: String {
        switch language {
        case .en: return "Ring numbers omit % to fit inside the icon."
        case .zhHans: return "数字显示在圆环内时会省略 %，以便清晰显示。"
        case .zhHant: return "數字顯示在圓環內時會省略 %，以便清楚呈現。"
        case .ja: return "リング内の数字は読みやすさのため % を省略します。"
        }
    }

    static var colorMode: String {
        switch language {
        case .en: return "Ring color"
        case .zhHans: return "圆环颜色"
        case .zhHant: return "圓環顏色"
        case .ja: return "リングの色"
        }
    }

    static var colorByQuota: String {
        switch language {
        case .en: return "Multicolor"
        case .zhHans: return "多色"
        case .zhHant: return "多色"
        case .ja: return "マルチカラー"
        }
    }

    static var colorSingle: String {
        switch language {
        case .en: return "Single color"
        case .zhHans: return "单色"
        case .zhHant: return "單色"
        case .ja: return "単色"
        }
    }

    static var iconStyle: String {
        switch language {
        case .en: return "Icon style"
        case .zhHans: return "图标样式"
        case .zhHant: return "圖示樣式"
        case .ja: return "アイコンのスタイル"
        }
    }

    static var ringIcon: String {
        switch language {
        case .en: return "Ring"
        case .zhHans: return "圆环"
        case .zhHant: return "圓環"
        case .ja: return "リング"
        }
    }

    static var standardIcon: String {
        switch language {
        case .en: return "Standard"
        case .zhHans: return "标准"
        case .zhHant: return "標準"
        case .ja: return "標準"
        }
    }

    static var quotaDisplay: String {
        switch language {
        case .en: return "Quota shown"
        case .zhHans: return "额度显示"
        case .zhHant: return "額度顯示"
        case .ja: return "表示する使用量"
        }
    }

    static var showPercent: String {
        switch language {
        case .en: return "Show percentage"
        case .zhHans: return "显示百分比"
        case .zhHant: return "顯示百分比"
        case .ja: return "パーセンテージを表示"
        }
    }

    static var showPercentDescription: String {
        switch language {
        case .en: return "Show the selected quota percentage as a number."
        case .zhHans: return "显示所选额度的百分比数字。"
        case .zhHant: return "顯示所選額度的百分比數字。"
        case .ja: return "選択した使用量のパーセンテージを数字で表示します。"
        }
    }

    static var accountRings: String {
        switch language {
        case .en: return "Account rings"
        case .zhHans: return "账号圆环"
        case .zhHant: return "帳號圓環"
        case .ja: return "アカウントリング"
        }
    }

    static func accountRing(_ index: Int) -> String {
        switch language {
        case .en: return "Ring \(index)"
        case .zhHans: return "圆环 \(index)"
        case .zhHant: return "圓環 \(index)"
        case .ja: return "リング \(index)"
        }
    }

    static var selectAccount: String {
        switch language {
        case .en: return "Select account"
        case .zhHans: return "选择账号"
        case .zhHant: return "選擇帳號"
        case .ja: return "アカウントを選択"
        }
    }

    static var addAccountRing: String {
        switch language {
        case .en: return "Add account ring"
        case .zhHans: return "添加账号圆环"
        case .zhHant: return "新增帳號圓環"
        case .ja: return "アカウントリングを追加"
        }
    }

    static var removeAccountRing: String {
        switch language {
        case .en: return "Remove ring"
        case .zhHans: return "删除圆环"
        case .zhHant: return "刪除圓環"
        case .ja: return "リングを削除"
        }
    }

    static var noAvailableAccounts: String {
        switch language {
        case .en: return "Add a visible account to create a quota ring."
        case .zhHans: return "添加一个未隐藏的账号即可创建额度圆环。"
        case .zhHant: return "新增未隱藏的帳號即可建立額度圓環。"
        case .ja: return "表示可能なアカウントを追加すると、使用量リングを作成できます。"
        }
    }

    static var accountSelectionHelp: String {
        switch language {
        case .en: return "Choose an account and quota period for each ring."
        case .zhHans: return "每个圆环可独立选择账号和额度周期。"
        case .zhHant: return "每個圓環可獨立選擇帳號和額度週期。"
        case .ja: return "リングごとにアカウントと使用量の期間を選択できます。"
        }
    }

    static var quotaPeriod: String {
        switch language {
        case .en: return "Quota period"
        case .zhHans: return "额度周期"
        case .zhHant: return "額度週期"
        case .ja: return "使用量の期間"
        }
    }

    static func windowLabel(_ window: MenuBarQuotaWindow) -> String {
        switch language {
        case .en: return window == .fiveHour ? "5 hours" : "Weekly"
        case .zhHans: return window == .fiveHour ? "5 小时" : "周额度"
        case .zhHant: return window == .fiveHour ? "5 小時" : "週額度"
        case .ja: return window == .fiveHour ? "5時間" : "週間"
        }
    }

    static var quotaWindowHelp: String {
        switch language {
        case .en: return "If weekly quota is unavailable, the ring shows the 5-hour quota."
        case .zhHans: return "选择周额度时，若账号只有 5 小时额度，将显示 5 小时额度。"
        case .zhHant: return "選擇週額度時，若帳號只有 5 小時額度，將顯示 5 小時額度。"
        case .ja: return "週間の使用量がない場合は、5時間の使用量を表示します。"
        }
    }

    static var colorLegend: String {
        switch language {
        case .en: return "Remaining quota: green above 50%, orange at 21–50%, red at 20% or less. Missing data is gray."
        case .zhHans: return "剩余高于 50% 为绿色，21–50% 为橙色，20% 及以下为红色；无数据时为灰色。"
        case .zhHant: return "剩餘高於 50% 為綠色，21–50% 為橘色，20% 及以下為紅色；無資料時為灰色。"
        case .ja: return "残量が50%超は緑、21～50%はオレンジ、20%以下は赤です。データなしはグレーです。"
        }
    }

    static var monochromeColorLegend: String {
        switch language {
        case .en: return "The ring is always white."
        case .zhHans: return "圆环固定显示为白色。"
        case .zhHant: return "圓環固定顯示為白色。"
        case .ja: return "リングは常に白色で表示されます。"
        }
    }

    static var noUsage: String {
        switch language {
        case .en: return "No usage data"
        case .zhHans: return "暂无用量数据"
        case .zhHant: return "尚無用量資料"
        case .ja: return "使用量データがありません"
        }
    }
}
