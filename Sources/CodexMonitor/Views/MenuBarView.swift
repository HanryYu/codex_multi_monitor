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
    var isLimited: Bool = false
    var resetAfterSeconds: Int = 0
    var resetAt: Int = 0
    var resetTimeFormat: ResetTimeFormat = .relative

    private var resetTimeText: String {
        if resetTimeFormat == .relative {
            // Relative: countdown format
            let seconds: Int
            if resetAfterSeconds > 0 {
                seconds = resetAfterSeconds
            } else if resetAt > 0 {
                seconds = max(0, resetAt - Int(Date().timeIntervalSince1970))
            } else {
                return ""
            }
            guard seconds > 0 else { return "" }
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            return L10n.resetRelative(hours: hours, minutes: minutes)
        } else {
            // Absolute: date+time format
            let targetDate: Date
            if resetAt > 0 {
                targetDate = Date(timeIntervalSince1970: TimeInterval(resetAt))
            } else if resetAfterSeconds > 0 {
                targetDate = Date().addingTimeInterval(TimeInterval(resetAfterSeconds))
            } else {
                return ""
            }
            return L10n.resetAbsoluteTime(targetDate)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Label
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.secondary)

            Spacer(minLength: 2)

            // Percentage + sublabel on one line
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(displayPercent)%")
                    .font(.system(size: isLimited ? 13 : 15, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .monospacedDigit()

                Text(displayMode == .remaining ? L10n.remaining : L10n.used)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.secondary.opacity(0.7))
                    .tracking(0.2)
            }

            Spacer(minLength: 0)

            // Progress bar
            CompactProgressBar(percentage: usedPercent)
                .opacity(isLimited ? 0.4 : 1.0)

            // Reset time
            if !resetTimeText.isEmpty {
                Spacer(minLength: 3)
                Text(resetTimeText)
                    .font(.system(size: 9, weight: .regular).monospacedDigit())
                    .foregroundStyle(Color.secondary.opacity(0.55))
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(height: 82)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isLimited ? 0.55 : 1.0)
        .saturation(isLimited ? 0.2 : 1.0)
        .background(isLimited ? Color.red.opacity(0.03) : Color.primary.opacity(0.03))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isLimited ? Color.red.opacity(0.12) : Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - QuotaCardsGridView (two cards side by side)

struct QuotaCardsGridView: View {
    let usage: UsageResponse
    let displayMode: DisplayMode
    var isLimited: Bool = false
    var resetTimeFormat: ResetTimeFormat = .relative

    var body: some View {
        if let rateLimit = usage.rateLimit {
            HStack(spacing: 8) {
                if let primary = rateLimit.primaryWindow {
                    QuotaCardView(
                        label: formatWindowLabel(seconds: primary.limitWindowSeconds),
                        displayPercent: displayMode == .remaining
                            ? (100 - primary.usedPercent)
                            : primary.usedPercent,
                        usedPercent: primary.usedPercent,
                        displayMode: displayMode,
                        isLimited: isLimited,
                        resetAfterSeconds: primary.resetAfterSeconds,
                        resetAt: primary.resetAt,
                        resetTimeFormat: resetTimeFormat
                    )
                }

                if let secondary = rateLimit.secondaryWindow {
                    QuotaCardView(
                        label: formatWindowLabel(seconds: secondary.limitWindowSeconds),
                        displayPercent: displayMode == .remaining
                            ? (100 - secondary.usedPercent)
                            : secondary.usedPercent,
                        usedPercent: secondary.usedPercent,
                        displayMode: displayMode,
                        isLimited: isLimited,
                        resetAfterSeconds: secondary.resetAfterSeconds,
                        resetAt: secondary.resetAt,
                        resetTimeFormat: resetTimeFormat
                    )
                }
            }
        } else if let credits = usage.credits {
            // Team plan — show single card with credits info
            HStack(spacing: 8) {
                CreditsCardView(credits: credits, isLimited: isLimited)
            }
        } else if usage.rateLimitReachedType != nil {
            // Rate limit reached with no detailed data — show placeholder cards
            HStack(spacing: 8) {
                QuotaCardView(
                    label: L10n.limitReached,
                    displayPercent: 0,
                    usedPercent: 100,
                    displayMode: displayMode,
                    isLimited: true
                )
                QuotaCardView(
                    label: L10n.unavailable,
                    displayPercent: 0,
                    usedPercent: 100,
                    displayMode: displayMode,
                    isLimited: true
                )
            }
        } else {
            HStack(spacing: 5) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Text(L10n.noUsageData(planType: usage.planType))
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
            return L10n.weeklyLimit()
        } else if hours >= 24 {
            return L10n.hourlyLimit(hours: hours)
        } else {
            return L10n.hourlyLimit(hours: hours)
        }
    }
}

// MARK: - CreditsCardView (for Team plan accounts)

struct CreditsCardView: View {
    let credits: Credits
    var isLimited: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.credits)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.secondary)

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

            Text(credits.unlimited ? L10n.unlimited : L10n.balance)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Color.secondary.opacity(0.7))
                .tracking(0.2)
                .padding(.top, 2)

            Spacer(minLength: 4)

            // Status indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(credits.hasCredits ? Color.green : Color.red)
                    .frame(width: 5, height: 5)
                Text(credits.hasCredits ? L10n.available : L10n.exhausted)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(credits.hasCredits ? .green : .red)
            }
        }
        .padding(10)
        .frame(height: 82)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isLimited ? 0.55 : 1.0)
        .saturation(isLimited ? 0.2 : 1.0)
        .background(isLimited ? Color.red.opacity(0.03) : Color.primary.opacity(0.03))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isLimited ? Color.red.opacity(0.12) : Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - MenuBarView (Popover — Gemini Canvas style)

struct MenuBarView: View {
    @ObservedObject var accountStore: AccountStore
    @ObservedObject var localeManager = LocaleManager.shared
    @State private var displayMode: DisplayMode = .remaining
    @State private var resetTimeFormat: ResetTimeFormat = .relative

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
        .frame(width: 300)
        .frame(maxHeight: 600)
        .background(.ultraThinMaterial)
        .onAppear { loadDisplayMode(); loadResetTimeFormat() }
        .onReceive(NotificationCenter.default.publisher(for: .displayModeChanged)) { _ in
            loadDisplayMode()
        }
        .onReceive(NotificationCenter.default.publisher(for: .resetTimeFormatChanged)) { _ in
            loadResetTimeFormat()
        }
    }

    private func loadDisplayMode() {
        let modeString = UserDefaults.standard.string(forKey: PreferencesKeys.displayMode) ?? DisplayMode.remaining.rawValue
        displayMode = DisplayMode(rawValue: modeString) ?? .remaining
    }

    private func loadResetTimeFormat() {
        let formatString = UserDefaults.standard.string(forKey: PreferencesKeys.resetTimeFormat) ?? ResetTimeFormat.relative.rawValue
        resetTimeFormat = ResetTimeFormat(rawValue: formatString) ?? .relative
    }

    private func isRateLimited(_ usage: UsageResponse) -> Bool {
        if usage.rateLimitReachedType != nil { return true }
        if let rl = usage.rateLimit, rl.limitReached { return true }
        if let credits = usage.credits, credits.overageLimitReached { return true }
        return false
    }

    // MARK: - Loading Placeholder

    private var loadingPlaceholder: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ShimmerView().frame(height: 82)
                ShimmerView().frame(height: 82)
            }
        }
        .padding(12)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)

            VStack(spacing: 4) {
                Text(L10n.noAccountsAdded)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(L10n.addAccountToMonitor)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }

            Button(action: {
                WindowManager.shared.openSettingsWindow()
            }) {
                Label(L10n.addAccount, systemImage: "plus")
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
            VStack(spacing: 8) {
                // Loading indicator when refreshing
                if accountStore.isLoading {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text(L10n.refreshing)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                ForEach(accountStore.accounts) { account in
                    let usageResult = accountStore.usageData[account.id]
                    let limited = usageResult.flatMap { result -> Bool? in
                        if case .success(let u) = result { return isRateLimited(u) }
                        return nil
                    } ?? false

                    VStack(spacing: 0) {
                        // Account header: name + plan badge
                        HStack(alignment: .center) {
                            Text(account.name)
                                .font(.system(size: 11, weight: limited ? .semibold : .medium))
                                .foregroundStyle(limited ? Color.secondary.opacity(0.5) : Color.secondary)
                                .strikethrough(limited, color: Color.secondary.opacity(0.5))
                                .lineLimit(1)

                            if let usageResult, case .success(let usage) = usageResult {
                                Text(usage.planType.localizedCapitalized)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(limited ? Color.secondary.opacity(0.4) : Color.orange)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background((limited ? Color.secondary : Color.orange).opacity(limited ? 0.06 : 0.12))
                                    .clipShape(Capsule())
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                        Divider().opacity(0.4)
                            .padding(.horizontal, 14)

                        // Quota cards content
                        if let usageResult {
                            switch usageResult {
                            case .success(let usage):
                                QuotaCardsGridView(usage: usage, displayMode: displayMode, isLimited: limited, resetTimeFormat: resetTimeFormat)
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
                                Text(L10n.noData)
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
                    .overlay {
                        if limited {
                            ZStack {
                                // Semi-transparent overlay
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.ultraThinMaterial.opacity(0.7))

                                // Centered badge
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color(hex: "ff3b30"))
                                    Text(L10n.limitReached)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color(hex: "ff3b30"))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(Color(hex: "ff3b30").opacity(0.1))
                                .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
            .padding(12)
            .animation(.easeInOut(duration: 0.3), value: accountStore.accounts.count)
        }
    }

    private var formattedRefreshTime: String {
        if let time = accountStore.lastRefreshTime {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return L10n.updatedAt(time: formatter.string(from: time))
        }
        return L10n.notYetUpdated
    }

    // MARK: - Footer (Gemini Canvas style)

    private var footerView: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: {
                    WindowManager.shared.openSettingsWindow()
                }) {
                    Text(L10n.settings)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)

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

            Divider().opacity(0.3).padding(.top, 6)

            Button(action: {
                NSApp.terminate(nil)
            }) {
                Text(L10n.quitCodexMonitor)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.01))
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
