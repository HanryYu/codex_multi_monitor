import Foundation
import SwiftUI
import AppKit

@MainActor
class AccountStore: ObservableObject {
    @Published var accounts: [Account] = []
    @Published var usageData: [UUID: Result<UsageResponse, APIError>] = [:]
    @Published var isLoading = false
    
    private let userDefaults = UserDefaults.standard
    private let accountsKey = "saved_accounts"
    
    enum OverallStatus {
        case healthy, warning, critical, noAccounts
    }
    
    var overallStatus: OverallStatus {
        guard !accounts.isEmpty else { return .noAccounts }
        
        var hasCritical = false
        var hasWarning = false
        
        for account in accounts {
            if case .success(let usage) = usageData[account.id] {
                if let rateLimit = usage.rateLimit {
                    let primaryUsed = rateLimit.primaryWindow?.usedPercent ?? 0
                    let secondaryUsed = rateLimit.secondaryWindow?.usedPercent ?? 0
                    let maxUsed = max(primaryUsed, secondaryUsed)
                    
                    if rateLimit.limitReached {
                        hasCritical = true
                    } else if maxUsed >= 80 {
                        hasWarning = true
                    }
                } else if usage.rateLimitReachedType != nil {
                    // rate_limit 为 null 但 rate_limit_reached_type 有值，视为限额已达
                    hasCritical = true
                }
            }
        }
        
        if hasCritical { return .critical }
        if hasWarning { return .warning }
        return .healthy
    }
    
    /// Returns the top 2 primary_window.usedPercent values from all accounts, sorted descending
    var topUsagePercentages: [Int] {
        guard !accounts.isEmpty else { return [] }
        
        var percentages: [Int] = []
        for account in accounts {
            if case .success(let usage) = usageData[account.id],
               let primaryPercent = usage.rateLimit?.primaryWindow?.usedPercent {
                percentages.append(primaryPercent)
            }
        }
        
        return percentages.sorted(by: >).prefix(2).map { $0 }
    }
    
    init() {
        loadAccounts()
    }
    
    func loadAccounts() {
        guard let data = userDefaults.data(forKey: accountsKey) else { return }
        
        do {
            let decoder = JSONDecoder()
            accounts = try decoder.decode([Account].self, from: data)
            
            // Load tokens from Keychain
            for i in 0..<accounts.count {
                if let token = KeychainHelper.load(key: "token_\(accounts[i].id.uuidString)") {
                    accounts[i].authToken = token
                }
            }
        } catch {
            print("Failed to load accounts: \(error)")
        }
    }
    
    func saveAccounts() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(accounts)
            userDefaults.set(data, forKey: accountsKey)
            
            // Save tokens to Keychain
            for account in accounts {
                KeychainHelper.save(key: "token_\(account.id.uuidString)", value: account.authToken)
            }
        } catch {
            print("Failed to save accounts: \(error)")
        }
    }
    
    func addAccount(_ account: Account) {
        accounts.append(account)
        saveAccounts()
    }
    
    func updateAccount(_ account: Account) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
            saveAccounts()
        }
    }
    
    func deleteAccount(at offsets: IndexSet) {
        for index in offsets {
            let account = accounts[index]
            KeychainHelper.delete(key: "token_\(account.id.uuidString)")
            usageData.removeValue(forKey: account.id)
        }
        accounts.remove(atOffsets: offsets)
        saveAccounts()
    }
    
    func deleteAccount(id: UUID) {
        if let index = accounts.firstIndex(where: { $0.id == id }) {
            KeychainHelper.delete(key: "token_\(id.uuidString)")
            usageData.removeValue(forKey: id)
            accounts.remove(at: index)
            saveAccounts()
        }
    }
    
    func refreshAll() async {
        guard !accounts.isEmpty else { return }
        
        isLoading = true
        
        await withTaskGroup(of: (UUID, Result<UsageResponse, APIError>).self) { group in
            for account in accounts {
                group.addTask {
                    do {
                        let usage = try await APIService.shared.fetchUsage(authToken: account.authToken)
                        return (account.id, .success(usage))
                    } catch let error as APIError {
                        return (account.id, .failure(error))
                    } catch {
                        return (account.id, .failure(.invalidResponse))
                    }
                }
            }
            
            for await (id, result) in group {
                usageData[id] = result
            }
        }
        
        isLoading = false
        
        // Update status bar icon
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.updateStatusBarIcon()
        }
    }
}
