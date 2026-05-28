import SwiftUI

struct MenuBarView: View {
    @ObservedObject var accountStore: AccountStore
    @State private var showingAddSheet = false
    @State private var editingAccount: Account?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with refresh and add buttons
            HStack {
                Text("CodexMonitor")
                    .font(.headline)
                
                Spacer()
                
                Button(action: {
                    Task {
                        await accountStore.refreshAll()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(accountStore.isLoading)
                .help("Refresh")
                
                Button(action: {
                    showingAddSheet = true
                }) {
                    Image(systemName: "plus.circle")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("Add Account")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            Divider()
            
            // Loading indicator
            if accountStore.isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Refreshing...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }
            
            // Accounts list
            if accountStore.accounts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    
                    Text("No accounts added")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Button("Add Account") {
                        showingAddSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.vertical, 24)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(accountStore.accounts) { account in
                            AccountCard(
                                account: account,
                                usageResult: accountStore.usageData[account.id],
                                onEdit: {
                                    editingAccount = account
                                },
                                onDelete: {
                                    accountStore.deleteAccount(id: account.id)
                                }
                            )
                        }
                    }
                    .padding(16)
                }
            }
            
            Divider()
            
            // Footer with preferences and quit buttons
            HStack {
                Button("Preferences...") {
                    openPreferencesWindow()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .font(.caption)
                
                Spacer()
                
                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .font(.caption)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 320)
        .frame(maxHeight: 500)
        .sheet(isPresented: $showingAddSheet) {
            AddAccountSheet(accountStore: accountStore, isPresented: $showingAddSheet)
        }
        .sheet(item: $editingAccount) { account in
            AddAccountSheet(accountStore: accountStore, isPresented: .constant(true), editingAccount: account)
        }
    }
}

struct AccountCard: View {
    let account: Account
    let usageResult: Result<UsageResponse, APIError>?
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text(account.name)
                    .font(.system(size: 13, weight: .semibold))
                
                Spacer()
                
                if let usage = try? usageResult?.get() {
                    Text(usage.planType.capitalized)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2))
                        .cornerRadius(4)
                }
                
                Menu {
                    Button("Edit") { onEdit() }
                    Button("Delete", role: .destructive) { onDelete() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .menuStyle(.borderlessButton)
                .frame(width: 20)
            }
            
            Divider()
            
            // Usage content
            if let usageResult = usageResult {
                switch usageResult {
                case .success(let usage):
                    UsageContentView(usage: usage)
                case .failure(let error):
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.red)
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            } else {
                HStack {
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(.secondary)
                    Text("No data")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct UsageContentView: View {
    let usage: UsageResponse
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Primary window (5-hour limit)
            WindowUsageRow(
                icon: "⏱",
                label: formatWindowLabel(seconds: usage.rateLimit.primaryWindow.limitWindowSeconds),
                usedPercent: usage.rateLimit.primaryWindow.usedPercent,
                resetAt: usage.rateLimit.primaryWindow.resetAt,
                isLimitReached: usage.rateLimit.limitReached
            )
            
            // Secondary window (weekly limit)
            WindowUsageRow(
                icon: "📅",
                label: formatWindowLabel(seconds: usage.rateLimit.secondaryWindow.limitWindowSeconds),
                usedPercent: usage.rateLimit.secondaryWindow.usedPercent,
                resetAt: usage.rateLimit.secondaryWindow.resetAt,
                isLimitReached: usage.rateLimit.limitReached
            )
        }
    }
    
    func formatWindowLabel(seconds: Int) -> String {
        let hours = seconds / 3600
        if hours >= 168 {
            return "Weekly"
        } else if hours >= 24 {
            return "\(hours / 24) days"
        } else {
            return "\(hours) hours"
        }
    }
}

struct WindowUsageRow: View {
    let icon: String
    let label: String
    let usedPercent: Int
    let resetAt: Int
    let isLimitReached: Bool
    
    var remainingPercent: Int {
        100 - usedPercent
    }
    
    var statusColor: Color {
        if isLimitReached {
            return .red
        } else if usedPercent >= 80 {
            return .orange
        } else if usedPercent >= 60 {
            return .yellow
        } else {
            return .green
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(icon)
                    .font(.system(size: 11))
                Text(label + ":")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                
                Text("Used \(usedPercent)%")
                    .font(.system(size: 11))
                    .foregroundColor(statusColor)
                
                Text("·")
                    .foregroundColor(.secondary)
                
                Text("Remaining \(remainingPercent)%")
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
            }
            
            HStack {
                Text(" ")
                    .font(.system(size: 11))
                Text(" ")
                    .font(.system(size: 11))
                Text("Resets:")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                Text(formatResetTime(resetAt: resetAt))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    func formatResetTime(resetAt: Int) -> String {
        let resetDate = Date(timeIntervalSince1970: TimeInterval(resetAt))
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDate(resetDate, inSameDayAs: now) {
            // Today - show time only
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: resetDate)
        } else if calendar.isDate(resetDate, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: now)!) {
            // Tomorrow
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return "Tomorrow \(formatter.string(from: resetDate))"
        } else {
            // Other days - show weekday and time
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "EEEE HH:mm"
            return formatter.string(from: resetDate)
        }
    }
}
