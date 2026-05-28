import Foundation

struct UsageResponse: Codable {
    let planType: String
    let rateLimit: RateLimit
    let credits: Credits
    let rateLimitReachedType: String?
    
    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case credits
        case rateLimitReachedType = "rate_limit_reached_type"
    }
}

struct RateLimit: Codable {
    let allowed: Bool
    let limitReached: Bool
    let primaryWindow: WindowUsage
    let secondaryWindow: WindowUsage
    
    enum CodingKeys: String, CodingKey {
        case allowed
        case limitReached = "limit_reached"
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

struct WindowUsage: Codable {
    let usedPercent: Int
    let limitWindowSeconds: Int
    let resetAfterSeconds: Int
    let resetAt: Int
    
    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAfterSeconds = "reset_after_seconds"
        case resetAt = "reset_at"
    }
}

struct Credits: Codable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: String
    
    enum CodingKeys: String, CodingKey {
        case hasCredits = "has_credits"
        case unlimited
        case balance
    }
}
