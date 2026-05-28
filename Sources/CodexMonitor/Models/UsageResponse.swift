import Foundation

struct UsageResponse: Codable {
    let planType: String
    let rateLimit: RateLimit?
    let credits: Credits?
    let rateLimitReachedType: RateLimitReached?
    
    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case credits
        case rateLimitReachedType = "rate_limit_reached_type"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Team plans may return plan_type as null or different casing
        planType = (try? container.decode(String.self, forKey: .planType)) ?? "unknown"
        rateLimit = try? container.decodeIfPresent(RateLimit.self, forKey: .rateLimit)
        credits = try? container.decodeIfPresent(Credits.self, forKey: .credits)
        rateLimitReachedType = try? container.decodeIfPresent(RateLimitReached.self, forKey: .rateLimitReachedType)
        
        // Debug: log what we decoded
        print("[CodexMonitor] Decoded UsageResponse: planType=\(planType), rateLimit=\(rateLimit != nil ? "present" : "nil"), credits=\(credits != nil ? "present" : "nil"), rateLimitReachedType=\(rateLimitReachedType != nil ? "present" : "nil")")
    }
}

struct RateLimitReached: Codable {
    let type: String
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? container.decode(String.self, forKey: .type)) ?? "unknown"
    }
}

struct RateLimit: Codable {
    let allowed: Bool
    let limitReached: Bool
    let primaryWindow: WindowUsage?
    let secondaryWindow: WindowUsage?
    
    enum CodingKeys: String, CodingKey {
        case allowed
        case limitReached = "limit_reached"
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        allowed = (try? container.decode(Bool.self, forKey: .allowed)) ?? true
        limitReached = (try? container.decode(Bool.self, forKey: .limitReached)) ?? false
        primaryWindow = try? container.decodeIfPresent(WindowUsage.self, forKey: .primaryWindow)
        secondaryWindow = try? container.decodeIfPresent(WindowUsage.self, forKey: .secondaryWindow)
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
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usedPercent = (try? container.decode(Int.self, forKey: .usedPercent)) ?? 0
        limitWindowSeconds = (try? container.decode(Int.self, forKey: .limitWindowSeconds)) ?? 0
        resetAfterSeconds = (try? container.decode(Int.self, forKey: .resetAfterSeconds)) ?? 0
        resetAt = (try? container.decode(Int.self, forKey: .resetAt)) ?? 0
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
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasCredits = (try? container.decode(Bool.self, forKey: .hasCredits)) ?? false
        unlimited = (try? container.decode(Bool.self, forKey: .unlimited)) ?? false
        balance = (try? container.decode(String.self, forKey: .balance)) ?? "unknown"
    }
}
