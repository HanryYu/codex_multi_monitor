import Foundation

struct Account: Codable, Identifiable {
    let id: UUID
    var name: String
    var authToken: String
    let createdAt: Date
    
    init(id: UUID = UUID(), name: String, authToken: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.authToken = authToken
        self.createdAt = createdAt
    }
}
