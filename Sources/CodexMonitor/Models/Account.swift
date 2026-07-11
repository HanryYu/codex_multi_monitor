import Foundation

// MARK: - Account Source

enum AccountSource: String, Codable {
    case manual      // 手动添加
    case localAuth   // 本地 auth.json 导入
}

enum AccountProvider: String, Codable, CaseIterable, Identifiable {
    case codex
    case claude
    case grok

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude"
        case .grok: return "Grok"
        }
    }

    var assetName: String {
        switch self {
        case .codex: return "ProviderCodex"
        case .claude: return "ProviderClaude"
        case .grok: return "ProviderGrok"
        }
    }
}

struct Account: Codable, Identifiable {
    let id: UUID
    var name: String
    var authToken: String
    let createdAt: Date
    var source: AccountSource
    /// auth.json 中的 key，用于去重和匹配（仅 localAuth 账户使用）
    var accountID: String?
    /// Codex 账号邮箱，用于把手动账户和本地 auth.json 账户对应起来
    var accountEmail: String?
    /// 本地认证文件是否已失效（文件被删除时标记）
    var localAuthInvalid: Bool
    var provider: AccountProvider

    init(
        id: UUID = UUID(),
        name: String,
        authToken: String,
        createdAt: Date = Date(),
        source: AccountSource = .manual,
        accountID: String? = nil,
        accountEmail: String? = nil,
        localAuthInvalid: Bool = false,
        provider: AccountProvider = .codex
    ) {
        self.id = id
        self.name = name
        self.authToken = authToken
        self.createdAt = createdAt
        self.source = source
        self.accountID = accountID
        self.accountEmail = AuthTokenIdentityParser.normalizedEmail(accountEmail)
        self.localAuthInvalid = localAuthInvalid
        self.provider = provider
    }

    // Custom decoder for backward compatibility with v0.4.x JSON
    // that lacks `source` and `localAuthInvalid` fields.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        authToken = try container.decode(String.self, forKey: .authToken)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        source = try container.decodeIfPresent(AccountSource.self, forKey: .source) ?? .manual
        accountID = try container.decodeIfPresent(String.self, forKey: .accountID)
        accountEmail = AuthTokenIdentityParser.normalizedEmail(try container.decodeIfPresent(String.self, forKey: .accountEmail))
        localAuthInvalid = try container.decodeIfPresent(Bool.self, forKey: .localAuthInvalid) ?? false
        provider = try container.decodeIfPresent(AccountProvider.self, forKey: .provider) ?? .codex
    }
}
