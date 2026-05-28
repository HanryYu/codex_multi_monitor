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

// MARK: - Compact Progress Bar (3px, Gemini Canvas style)

struct CompactProgressBar: View {
    let percentage: Int  // used percentage (0-100)
    var reversed: Bool = false

    private var gradientColors: [Color] {
        if percentage >= 90 {
            return [Color(hex: "ff3b30"), Color(hex: "ff453a")]
        } else if percentage >= 60 {
            return [Color(hex: "FF6B00"), Color(hex: "FF8A33")]
        } else {
            return [Color(hex: "34c759"), Color(hex: "30d158")]
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: reversed ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primary.opacity(0.06))

                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: reversed ? .trailing : .leading,
                            endPoint: reversed ? .leading : .trailing
                        )
                    )
                    .frame(width: geometry.size.width * CGFloat(percentage) / 100)
                    .animation(.easeInOut(duration: 0.7), value: percentage)
            }
        }
        .frame(height: 3)
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

// MARK: - QuotaCardView (single quota card — Gemini Canvas style)

struct QuotaCardView: View {
    let label: String
    let displayPercent: Int   // what to show (remaining or used, depending on displayMode)
    let usedPercent: Int      // raw used percentage (for progress bar)
    let displayMode: DisplayMode

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Label
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.secondary)
                .tracking(0.4)

            Spacer(minLength: 4)

            // Percentage (compact — readable but not oversized)
            Text("\(displayPercent)%")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.primary)
                .tracking(-0.5)
                .lineLimit(1)
                .monospacedDigit()

            // Spacer placeholder (no label text)
            Spacer(minLength: 0)

            Spacer(minLength: 6)

            // Progress bar at bottom
            CompactProgressBar(percentage: usedPercent)
        }
        .padding(12)
        .frame(height: 108)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - QuotaCardsGridView (two cards side by side)

struct QuotaCardsGridView: View {
    let usage: UsageResponse
    let displayMode: DisplayMode

    var body: some View {
        if let rateLimit = usage.rateLimit {
            HStack(spacing: 10) {
                if let primary = rateLimit.primaryWindow {
                    QuotaCardView(
                        label: formatWindowLabel(seconds: primary.limitWindowSeconds),
                        displayPercent: displayMode == .remaining
                            ? (100 - primary.usedPercent)
                            : primary.usedPercent,
                        usedPercent: primary.usedPercent,
                        displayMode: displayMode
                    )
                }

                if let secondary = rateLimit.secondaryWindow {
                    QuotaCardView(
                        label: formatWindowLabel(seconds: secondary.limitWindowSeconds),
                        displayPercent: displayMode == .remaining
                            ? (100 - secondary.usedPercent)
                            : secondary.usedPercent,
                        usedPercent: secondary.usedPercent,
                        displayMode: displayMode
                    )
                }
            }
        } else if let credits = usage.credits {
            // Team plan — show single card with credits info
            HStack(spacing: 10) {
                CreditsCardView(credits: credits)
            }
        } else if usage.rateLimitReachedType != nil {
            // Rate limit reached, no data
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                Text("限额已达")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        } else {
            HStack(spacing: 5) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Text("plan: \(usage.planType) — 无用量数据")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    func formatWindowLabel(seconds: Int) -> String {
        let hours = seconds / 3600
        if hours >= 168 {
            return "每周限额"
        } else if hours >= 24 {
            return "\(hours)小时限额"
        } else {
            return "\(hours)小时限额"
        }
    }
}

// MARK: - CreditsCardView (for Team plan accounts)

struct CreditsCardView: View {
    let credits: Credits

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Credits")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.secondary)
                .tracking(0.4)

            Spacer(minLength: 4)

            if credits.unlimited {
                Image(systemName: "infinity")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.green)
            } else if let balance = credits.balance {
                Text(balance)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .monospacedDigit()
            } else {
                Text("—")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Color.secondary)
            }

            // Spacer placeholder (no label text)
            Spacer(minLength: 0)

            Spacer(minLength: 6)

            // Status indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(credits.hasCredits ? Color.green : Color.red)
                    .frame(width: 5, height: 5)
                Text(credits.hasCredits ? "可用" : "已耗尽")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(credits.hasCredits ? .green : .red)
            }
        }
        .padding(12)
        .frame(height: 108)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - MenuBarView (Popover — Gemini Canvas style)

struct MenuBarView: View {
    @ObservedObject var accountStore: AccountStore
    @State private var displayMode: DisplayMode = .remaining

    var body: some View {
        VStack(spacing: 0) {
            // Content
            if accountStore.isLoading && accountStore.accounts.isEmpty {
                loadingPlaceholder
            } else if accountStore.accounts.isEmpty {
                emptyStateView
            } else {
                accountsQuotaView
            }

            Divider().opacity(0.5)

            // Footer
            footerView
        }
        .frame(width: 340)
        .frame(maxHeight: 520)
        .background(.ultraThinMaterial)
        .onAppear { loadDisplayMode() }
        .onReceive(NotificationCenter.default.publisher(for: .displayModeChanged)) { _ in
            loadDisplayMode()
        }
    }

    private func loadDisplayMode() {
        let modeString = UserDefaults.standard.string(forKey: PreferencesKeys.displayMode) ?? DisplayMode.remaining.rawValue
        displayMode = DisplayMode(rawValue: modeString) ?? .remaining
    }

    // MARK: - Loading Placeholder

    private var loadingPlaceholder: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ShimmerView().frame(height: 108)
                ShimmerView().frame(height: 108)
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

    // MARK: - Accounts Quota View (Gemini Canvas style — cards grid)

    private var accountsQuotaView: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Loading indicator when refreshing
                if accountStore.isLoading {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Refreshing...")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                ForEach(accountStore.accounts) { account in
                    VStack(spacing: 0) {
                        // Account header: name + plan badge + refresh time
                        HStack(alignment: .center) {
                            Text(account.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.secondary)
                                .lineLimit(1)

                            if let usageResult = accountStore.usageData[account.id],
                               case .success(let usage) = usageResult {
                                Text(usage.planType.localizedCapitalized)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(Color.orange)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.orange.opacity(0.12))
                                    .clipShape(Capsule())
                            }

                            Spacer()

                            Button(action: {
                                Task { await accountStore.refreshAll() }
                            }) {
                                HStack(spacing: 4) {
                                    Text(formattedRefreshTime)
                                        .font(.system(size: 10).monospacedDigit())
                                        .foregroundStyle(Color.secondary.opacity(0.7))

                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(Color.secondary.opacity(0.7))
                                        .rotationEffect(.degrees(accountStore.isLoading ? 360 : 0))
                                        .animation(
                                            accountStore.isLoading
                                                ? .linear(duration: 0.6).repeatForever(autoreverses: false)
                                                : .default,
                                            value: accountStore.isLoading
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(accountStore.isLoading)
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                        .padding(.bottom, 6)

                        Divider().opacity(0.4)
                            .padding(.horizontal, 14)

                        // Quota cards content
                        if let usageResult = accountStore.usageData[account.id] {
                            switch usageResult {
                            case .success(let usage):
                                QuotaCardsGridView(usage: usage, displayMode: displayMode)
                            case .failure(let error):
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.red)
                                    Text(error.localizedDescription)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.red)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
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
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                    }
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
                }
            }
            .padding(16)
            .animation(.easeInOut(duration: 0.3), value: accountStore.accounts.count)
        }
    }

    private var formattedRefreshTime: String {
        if let time = accountStore.lastRefreshTime {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: time) + " 更新"
        }
        return "--:-- 更新"
    }

    // MARK: - Footer (Gemini Canvas style)

    private var footerView: some View {
        HStack {
            Button(action: { openPreferencesWindow() }) {
                Text("偏好设置…")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: {
                openAccountManagementWindow(accountStore: accountStore)
            }) {
                Text("管理账户…")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.01))
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

            // Account list
            if accountStore.accounts.isEmpty {
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
                                Text(maskedToken(account.authToken))
                                    .font(.system(size: 11).monospaced())
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            // Status indicator
                            if let result = accountStore.usageData[account.id] {
                                switch result {
                                case .success(let usage):
                                    if let percent = usage.rateLimit?.primaryWindow?.usedPercent {
                                        Text("\(percent)%")
                                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                                            .foregroundStyle(percent >= 80 ? .orange : .green)
                                    } else if let credits = usage.credits {
                                        if credits.unlimited {
                                            Text("∞")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(.green)
                                        } else if let balance = credits.balance {
                                            Text(balance)
                                                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                                                .foregroundStyle(credits.hasCredits ? .green : .red)
                                        } else {
                                            Text("—")
                                                .font(.system(size: 12))
                                                .foregroundStyle(.secondary)
                                        }
                                    } else if usage.rateLimitReachedType != nil {
                                        Text("限额已达")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(.red)
                                    } else {
                                        Text("—")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.tertiary)
                                    }
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
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 420, height: 380)
        .background(.ultraThinMaterial)
        .sheet(isPresented: $showingAddForm) {
            AddAccountSheet(accountStore: accountStore, isPresented: $showingAddForm)
        }
        .sheet(item: $editingAccount) { account in
            EditAccountSheetWrapper(accountStore: accountStore, account: account, editingAccount: $editingAccount)
        }
    }
    func maskedToken(_ token: String) -> String {
        guard token.count > 12 else { return "••••••••" }
        let prefix = token.prefix(8)
        let suffix = token.suffix(4)
        return "\(prefix)••••\(suffix)"
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

// MARK: - Color Hex Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
