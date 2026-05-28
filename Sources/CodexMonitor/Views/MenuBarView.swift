import SwiftUI

// MARK: - Shimmer Loading Animation

struct ShimmerView: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        LinearGradient(
            colors: [
                Color.primary.opacity(0.04),
                Color.primary.opacity(0.10),
                Color.primary.opacity(0.04)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .mask(
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, .white, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .offset(x: phase)
        )
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                phase = 200
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Gradient Progress Bar

struct GradientProgressBar: View {
    let percentage: Int

    private var gradientColors: [Color] {
        if percentage >= 90 {
            return [.red, .red.opacity(0.8)]
        } else if percentage >= 70 {
            return [.orange, .red.opacity(0.6)]
        } else if percentage >= 50 {
            return [.yellow, .orange]
        } else {
            return [.green, .green.opacity(0.7)]
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.primary.opacity(0.06))

                // Fill
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * CGFloat(percentage) / 100)
                    .animation(.easeInOut(duration: 0.6), value: percentage)
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Glass Card Modifier

struct GlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
    }
}

extension View {
    func glassCard() -> some View {
        modifier(GlassCardModifier())
    }
}

// MARK: - MenuBarView (Popover — read-only display only)

struct MenuBarView: View {
    @ObservedObject var accountStore: AccountStore

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider().opacity(0.5)

            // Content
            if accountStore.isLoading && accountStore.accounts.isEmpty {
                loadingPlaceholder
            } else if accountStore.accounts.isEmpty {
                emptyStateView
            } else {
                accountsScrollView
            }

            Divider().opacity(0.5)

            // Footer
            footerView
        }
        .frame(width: 340)
        .frame(maxHeight: 520)
        .background(.ultraThinMaterial)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Label("CodexMonitor", systemImage: "gauge.medium")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            Button(action: {
                Task { await accountStore.refreshAll() }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(accountStore.isLoading ? 360 : 0))
                    .animation(
                        accountStore.isLoading
                            ? .linear(duration: 1).repeatForever(autoreverses: false)
                            : .default,
                        value: accountStore.isLoading
                    )
            }
            .buttonStyle(.plain)
            .disabled(accountStore.isLoading)
            .help("Refresh all accounts")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Loading Placeholder

    private var loadingPlaceholder: some View {
        VStack(spacing: 12) {
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        ShimmerView().frame(width: 100, height: 14)
                        Spacer()
                        ShimmerView().frame(width: 50, height: 14)
                    }
                    ShimmerView().frame(height: 4)
                    ShimmerView().frame(width: 120, height: 10)
                }
                .padding(14)
                .glassCard()
            }
        }
        .padding(16)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)

            VStack(spacing: 4) {
                Text("No accounts added")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Add a Codex account to monitor usage")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }

            Button(action: {
                openAccountManagementWindow(accountStore: accountStore)
            }) {
                Label("Add Account", systemImage: "plus")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.vertical, 32)
    }

    // MARK: - Accounts Scroll View (read-only display)

    private var accountsScrollView: some View {
        ScrollView {
            VStack(spacing: 10) {
                // Loading indicator at top when refreshing
                if accountStore.isLoading {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Refreshing...")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                ForEach(accountStore.accounts) { account in
                    AccountCardReadOnly(
                        account: account,
                        usageResult: accountStore.usageData[account.id]
                    )
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.95)),
                        removal: .opacity.combined(with: .scale(scale: 0.95))
                    ))
                }
            }
            .padding(16)
            .animation(.easeInOut(duration: 0.3), value: accountStore.accounts.count)
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Button(action: { openPreferencesWindow() }) {
                Label("Preferences", systemImage: "gear")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: {
                openAccountManagementWindow(accountStore: accountStore)
            }) {
                Label("Manage Accounts...", systemImage: "person.2")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: { NSApp.terminate(nil) }) {
                Text("Quit")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - AccountCardReadOnly (popover display — no edit/delete buttons)

struct AccountCardReadOnly: View {
    let account: Account
    let usageResult: Result<UsageResponse, APIError>?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(alignment: .center) {
                // Account icon
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)

                Text(account.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                if let usage = try? usageResult?.get() {
                    Text(usage.planType.localizedCapitalized)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            Divider().opacity(0.4)

            // Usage content
            if let usageResult = usageResult {
                switch usageResult {
                case .success(let usage):
                    UsageContentView(usage: usage)
                case .failure(let error):
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                        Text(error.localizedDescription)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Text("No data")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(14)
        .glassCard()
    }
}

// MARK: - UsageContentView

struct UsageContentView: View {
    let usage: UsageResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WindowUsageRow(
                icon: "clock",
                label: formatWindowLabel(seconds: usage.rateLimit.primaryWindow.limitWindowSeconds),
                usedPercent: usage.rateLimit.primaryWindow.usedPercent,
                resetAt: usage.rateLimit.primaryWindow.resetAt,
                isLimitReached: usage.rateLimit.limitReached
            )

            WindowUsageRow(
                icon: "calendar",
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

// MARK: - WindowUsageRow

struct WindowUsageRow: View {
    let icon: String
    let label: String
    let usedPercent: Int
    let resetAt: Int
    let isLimitReached: Bool

    var remainingPercent: Int { 100 - usedPercent }

    var statusColor: Color {
        if isLimitReached { return .red }
        if usedPercent >= 80 { return .orange }
        if usedPercent >= 60 { return .yellow }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Label row
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(statusColor)
                    .frame(width: 12)

                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)

                Text("·")
                    .foregroundStyle(.tertiary)

                Text("\(usedPercent)%")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(statusColor)

                Spacer()

                Text("Resets \(formatResetTime(resetAt: resetAt))")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            // Gradient progress bar
            GradientProgressBar(percentage: usedPercent)
        }
        .padding(.vertical, 2)
    }

    func formatResetTime(resetAt: Int) -> String {
        let resetDate = Date(timeIntervalSince1970: TimeInterval(resetAt))
        let calendar = Calendar.current
        let now = Date()

        if calendar.isDate(resetDate, inSameDayAs: now) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: resetDate)
        } else if calendar.isDate(resetDate, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: now)!) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return "tmr \(formatter.string(from: resetDate))"
        } else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "E HH:mm"
            return formatter.string(from: resetDate)
        }
    }
}

// MARK: - Account Management Window

struct AccountManagementView: View {
    @ObservedObject var accountStore: AccountStore
    @State private var showingAddForm = false
    @State private var editingAccount: Account?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Manage Accounts", systemImage: "person.2")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Button(action: { showingAddForm = true }) {
                    Label("Add", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().opacity(0.5)

            // Content: inline form OR account list
            if showingAddForm {
                AddAccountSheet(accountStore: accountStore, isPresented: $showingAddForm)
            } else if let editing = editingAccount {
                EditAccountSheetWrapper(accountStore: accountStore, account: editing, editingAccount: $editingAccount)
            } else if accountStore.accounts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("No accounts yet")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Button("Add Account") { showingAddForm = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(accountStore.accounts) { account in
                        HStack(spacing: 12) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.primary)
                                Text(account.authToken)
                                    .font(.system(size: 11).monospaced())
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            // Status indicator
                            if let result = accountStore.usageData[account.id] {
                                switch result {
                                case .success(let usage):
                                    let percent = usage.rateLimit.primaryWindow.usedPercent
                                    Text("\(percent)%")
                                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                                        .foregroundStyle(percent >= 80 ? .orange : .green)
                                case .failure:
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.red)
                                }
                            }

                            Button(action: {
                                editingAccount = account
                            }) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Edit account")

                            Button(action: {
                                accountStore.deleteAccount(id: account.id)
                            }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                            .help("Delete account")
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.inset)
            }

            Divider().opacity(0.5)

            // Footer
            HStack {
                Spacer()
                Button("Done") {
                    WindowManager.shared.closeAccountManagementWindow()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 420, height: 380)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Edit Account Sheet Wrapper (fixes Cancel binding issue)

struct EditAccountSheetWrapper: View {
    @ObservedObject var accountStore: AccountStore
    let account: Account
    @Binding var editingAccount: Account?
    @State private var isPresented: Bool = true

    var body: some View {
        AddAccountSheet(accountStore: accountStore, isPresented: $isPresented, editingAccount: account)
            .onChange(of: isPresented) { _, newValue in
                if !newValue {
                    editingAccount = nil
                }
            }
    }
}

// MARK: - Account Management Window (managed by WindowManager.shared)

func openAccountManagementWindow(accountStore: AccountStore) {
    WindowManager.shared.accountStore = accountStore
    WindowManager.shared.openAccountManagementWindow()
}

func closeAccountManagementWindow() {
    WindowManager.shared.closeAccountManagementWindow()
}
