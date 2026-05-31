import Foundation

// MARK: - Account Source

enum AccountSource: String, Codable {
    case manual      // 手动添加
    case localAuth   // 本地 auth.json 导入
}

struct Account: Codable, Identifiable {
    let id: UUID
    var name: String
    var authToken: String
    let createdAt: Date
    var source: AccountSource
    /// auth.json 中的 key，用于去重和匹配（仅 localAuth 账户使用）
    var accountID: String?
    /// 本地认证文件是否已失效（文件被删除时标记）
    var localAuthInvalid: Bool

    init(
        id: UUID = UUID(),
        name: String,
        authToken: String,
        createdAt: Date = Date(),
        source: AccountSource = .manual,
        accountID: String? = nil,
        localAuthInvalid: Bool = false
    ) {
        self.id = id
        self.name = name
        self.authToken = authToken
        self.createdAt = createdAt
        self.source = source
        self.accountID = accountID
        self.localAuthInvalid = localAuthInvalid
    }
}
