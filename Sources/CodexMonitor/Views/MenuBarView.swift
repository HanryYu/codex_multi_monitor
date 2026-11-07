import SwiftUI

enum MenuBarPanelStyle {
    static let width: CGFloat = 360
    static let maximumHeight: CGFloat = 640

    static let background = adaptiveColor(light: "F1F3F5", dark: "1B242B")
    static let card = adaptiveColor(light: "FFFFFF", dark: "2B353D")
    static let inset = adaptiveColor(light: "F1F3F5", dark: "222C33")
    static let border = Color.primary.opacity(0.06)

    private static func adaptiveColor(light: String, dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(Color(hex: isDark ? dark : light))
        })
    }
}

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

// MARK: - Compact Progress Bar

struct CompactProgressBar: View {
    let percentage: Int  // used percentage (0-100)
    var reversed: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var barColor: Color {
        if percentage >= 90 {
            return .red
        } else if percentage >= 60 {
            return .orange
        } else {
            return .green
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: reversed ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primary.opacity(0.06))

                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        barColor
                    )
                    .frame(width: geometry.size.width * CGFloat(min(100, max(0, percentage))) / 100)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: percentage)
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
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
            }
    }
}

extension View {
    func glassCard() -> some View {
        modifier(GlassCardModifier())
    }
}

// MARK: - Quota Card

struct QuotaCardView: View {
    let label: String
    @ObservedObject var localeManager = LocaleManager.shared

    let displayPercent: Int   // what to show (remaining or used, depending on displayMode)
    let usedPercent: Int      // raw used percentage (for progress bar)
    let displayMode: DisplayMode
    var isLimited: Bool = false
    var resetAfterSeconds: Int = 0
    var resetAt: Int = 0
    var resetTimeFormat: ResetTimeFormat = .relative
    var allowanceSummary: QuotaAllowanceSummary? = nil

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
            let relativeTime = RelativeResetTime(seconds: seconds)
            return L10n.resetRelative(relativeTime)
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
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 2)

                if let allowanceSummary {
                    QuotaAllowanceInlineView(summary: allowanceSummary)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(displayPercent)")
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .monospacedDigit()

                Text("%")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Text(displayMode == .remaining ? L10n.remaining : L10n.used)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            CompactProgressBar(percentage: usedPercent)
                .opacity(isLimited ? 0.65 : 1.0)
                .padding(.top, 2)

            if !resetTimeText.isEmpty {
                Text(resetTimeText)
                    .font(.system(size: 10, weight: .regular).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(resetTimeText)
            }
        }
        .padding(12)
        .frame(height: 130, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isLimited ? 0.78 : 1.0)
        .saturation(isLimited ? 0.6 : 1.0)
        .background(isLimited ? Color.red.opacity(0.04) : MenuBarPanelStyle.inset)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - QuotaCardsGridView (two cards side by side)

struct QuotaCardsGridView: View {
    let usage: UsageResponse
    let displayMode: DisplayMode
    let allowanceSummary: QuotaAllowanceSummary?
    var isLimited: Bool = false
    var resetTimeFormat: ResetTimeFormat = .relative

    var body: some View {
        if let rateLimit = usage.rateLimit {
            let reachedType = usage.rateLimitReachedType?.type.lowercased()
            let primaryUsed = rateLimit.primaryWindow?.usedPercent ?? -1
            let secondaryUsed = rateLimit.secondaryWindow?.usedPercent ?? -1
            let tertiaryUsed = rateLimit.tertiaryWindow?.usedPercent ?? -1
            let maxUsed = max(primaryUsed, secondaryUsed, tertiaryUsed)

            HStack(spacing: 8) {
                if let primary = rateLimit.primaryWindow {
                    let primaryLimited = isWindowLimited(
                        window: primary, rateLimit: rateLimit,
                        reachedType: reachedType, preferredType: "primary",
                        maxUsedPercent: maxUsed
                    )
                    QuotaCardView(
                        label: L10n.compactQuotaWindow(seconds: primary.limitWindowSeconds),
                        displayPercent: displayMode == .remaining
                            ? (100 - primary.usedPercent)
                            : primary.usedPercent,
                        usedPercent: primary.usedPercent,
                        displayMode: displayMode,
                        isLimited: primaryLimited,
                        resetAfterSeconds: primary.resetAfterSeconds,
                        resetAt: primary.resetAt,
                        resetTimeFormat: resetTimeFormat,
                        allowanceSummary: isWeeklyWindow(primary) ? allowanceSummary : nil
                    )
                }

                if let secondary = rateLimit.secondaryWindow {
                    let secondaryLimited = isWindowLimited(
                        window: secondary, rateLimit: rateLimit,
                        reachedType: reachedType, preferredType: "secondary",
                        maxUsedPercent: maxUsed
                    )
                    QuotaCardView(
                        label: L10n.compactQuotaWindow(seconds: secondary.limitWindowSeconds),
                        displayPercent: displayMode == .remaining
                            ? (100 - secondary.usedPercent)
                            : secondary.usedPercent,
                        usedPercent: secondary.usedPercent,
                        displayMode: displayMode,
                        isLimited: secondaryLimited,
                        resetAfterSeconds: secondary.resetAfterSeconds,
                        resetAt: secondary.resetAt,
                        resetTimeFormat: resetTimeFormat,
                        allowanceSummary: isWeeklyWindow(secondary) ? allowanceSummary : nil
                    )
                }

                if let tertiary = rateLimit.tertiaryWindow {
                    QuotaCardView(
                        label: L10n.compactQuotaWindow(seconds: tertiary.limitWindowSeconds),
                        displayPercent: displayMode == .remaining
                            ? (100 - tertiary.usedPercent)
                            : tertiary.usedPercent,
                        usedPercent: tertiary.usedPercent,
                        displayMode: displayMode,
                        isLimited: tertiary.usedPercent >= 100,
                        resetAfterSeconds: tertiary.resetAfterSeconds,
                        resetAt: tertiary.resetAt,
                        resetTimeFormat: resetTimeFormat,
                        allowanceSummary: isWeeklyWindow(tertiary) ? allowanceSummary : nil
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
                Text(L10n.noUsageData(planType: usage.displayPlanType))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    private func isWeeklyWindow(_ window: WindowUsage) -> Bool {
        (6 * 24 * 60 * 60)...(8 * 24 * 60 * 60) ~= window.limitWindowSeconds
    }

    private func isWindowLimited(
        window: WindowUsage,
        rateLimit: RateLimit,
        reachedType: String?,
        preferredType: String,
        maxUsedPercent: Int
    ) -> Bool {
        guard rateLimit.limitReached else { return false }

        if let reachedType {
            if preferredType == "primary" {
                return reachedType == "primary"
                    || reachedType.contains("5h")
                    || reachedType.contains("5hour")
                    || reachedType.contains("hour")
            } else {
                return reachedType == "secondary"
                    || reachedType.contains("weekly")
                    || reachedType.contains("7d")
                    || reachedType.contains("week")
            }
        }

        return window.usedPercent >= 100
    }
}

// MARK: - OpenCode Go Compact Quota Panel

struct OpenCodeGoQuotaView: View {
    let usage: UsageResponse
    let displayMode: DisplayMode
    let allowanceSummary: QuotaAllowanceSummary?
    var isLimited: Bool = false
    var resetTimeFormat: ResetTimeFormat = .relative

    var body: some View {
        if let rateLimit = usage.rateLimit {
            VStack(spacing: 0) {
                if let window = rateLimit.primaryWindow {
                    quotaRow(window)
                }
                if let window = rateLimit.secondaryWindow {
                    compactDivider
                    quotaRow(window)
                }
                if let window = rateLimit.tertiaryWindow {
                    compactDivider
                    quotaRow(window)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(MenuBarPanelStyle.inset)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(isLimited ? 0.78 : 1)
        }
    }

    private var compactDivider: some View {
        Divider()
            .opacity(0.18)
            .padding(.leading, 42)
    }

    private func quotaRow(_ window: WindowUsage) -> some View {
        let displayPercent = displayMode == .remaining
            ? 100 - window.usedPercent
            : window.usedPercent

        return VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(L10n.compactQuotaWindow(seconds: window.limitWindowSeconds))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 37, alignment: .leading)

                Text("\(displayPercent)%")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()

                Text(displayMode == .remaining ? L10n.remaining : L10n.used)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.72))

                if isWeeklyWindow(window), let allowanceSummary {
                    QuotaAllowanceInlineView(summary: allowanceSummary)
                }

                Spacer(minLength: 4)

                if let resetText = resetText(for: window) {
                    Text(resetText)
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.secondary.opacity(0.72))
                        .lineLimit(1)
                }
            }

            CompactProgressBar(percentage: window.usedPercent)
                .padding(.leading, 42)
        }
        .padding(.vertical, 5)
    }

    private func resetText(for window: WindowUsage) -> String? {
        let targetDate: Date
        if window.resetAt > 0 {
            targetDate = Date(timeIntervalSince1970: TimeInterval(window.resetAt))
        } else if window.resetAfterSeconds > 0 {
            targetDate = Date().addingTimeInterval(TimeInterval(window.resetAfterSeconds))
        } else {
            return nil
        }

        if resetTimeFormat == .absolute {
            return L10n.compactDateTime(targetDate)
        }
        let seconds = max(0, Int(targetDate.timeIntervalSinceNow))
        guard seconds > 0 else { return nil }
        return RelativeResetTime(seconds: seconds).compactDescription
    }

    private func isWeeklyWindow(_ window: WindowUsage) -> Bool {
        (6 * 24 * 60 * 60)...(8 * 24 * 60 * 60) ~= window.limitWindowSeconds
    }
}

// MARK: - Weekly Quota Allowance Hint

struct QuotaAllowanceInlineView: View {
    let summary: QuotaAllowanceSummary
    @ObservedObject var localeManager = LocaleManager.shared

    var body: some View {
        Text(L10n.quotaAllowanceSummary(summary))
            .font(.system(size: 9, weight: .medium).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .foregroundStyle(.secondary)
            .help(L10n.quotaAllowanceHelp(summary: summary))
            .accessibilityLabel(L10n.quotaAllowanceHelp(summary: summary))
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
        .padding(12)
        .frame(height: 130)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isLimited ? 0.78 : 1.0)
        .saturation(isLimited ? 0.6 : 1.0)
        .background(isLimited ? Color.red.opacity(0.04) : MenuBarPanelStyle.inset)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Reset Credits Compact Row

struct ResetCreditsCompactView: View {
    let credits: RateLimitResetCredits
    let provider: AccountProvider
    let resetTimeFormat: ResetTimeFormat
    @ObservedObject var localeManager = LocaleManager.shared
    @State private var isExpanded = false

    private var visibleCredits: [RateLimitResetCredit] {
        Array(credits.displayCredits.prefix(4))
    }

    private var hiddenCreditCount: Int {
        credits.displayCredits.dropFirst(visibleCredits.count).reduce(0) { $0 + ($1.remainingCount ?? 1) }
    }

    private var isExpiringSoon: Bool {
        guard let date = credits.nearestExpirationDate else { return false }
        return date.timeIntervalSinceNow < 72 * 60 * 60
    }

    private var tint: Color {
        isExpiringSoon ? Color.orange : Color.accentColor
    }

    private var helpText: String {
        var lines = [L10n.resetCreditsAvailable(count: credits.availableCount)]
        let detailLines = credits.displayCredits.map { credit in
            dateLine(for: credit)
        }
        lines.append(contentsOf: detailLines)
        return lines.joined(separator: "\n")
    }

    var body: some View {
        if credits.availableCount > 0 {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.counterclockwise.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(tint)

                        Text(L10n.resetCreditsAvailable(count: credits.availableCount))
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Color.primary.opacity(0.85))
                            .lineLimit(1)

                        Spacer(minLength: 6)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Color.secondary.opacity(0.7))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    if visibleCredits.isEmpty {
                        Text(L10n.resetCreditExpirationUnavailable)
                            .font(.system(size: 9.5, weight: .regular))
                            .foregroundStyle(Color.secondary)
                            .lineLimit(1)
                    } else {
                        ForEach(Array(visibleCredits.enumerated()), id: \.offset) { _, credit in
                            Text(dateLine(for: credit))
                                .font(.system(size: 9.5, weight: .regular).monospacedDigit())
                                .foregroundStyle(isExpiringSoon ? Color.orange.opacity(0.85) : Color.secondary)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                                .minimumScaleFactor(0.85)
                        }

                        if hiddenCreditCount > 0 {
                            Text(L10n.resetCreditsMore(count: hiddenCreditCount))
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(Color.secondary)
                                .lineLimit(1)
                        }
                    }
                    if provider == .claude {
                        Link(L10n.claudeResetCreditsUsagePage, destination: URL(string: "https://claude.ai/settings/usage")!)
                            .font(.system(size: 9.5))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 8)
            .help(helpText)
        }
    }

    private func dateLine(for credit: RateLimitResetCredit) -> String {
        var parts = [expirationText(for: credit.expiresDate)]
        let scope = L10n.resetCreditScope(credit.resetType)
        if !scope.isEmpty { parts.append(scope) }
        if let count = credit.remainingCount, count > 1 {
            parts.append(L10n.resetCreditsAvailable(count: count))
        }
        if credit.requiresLimit == true { parts.append(L10n.resetCreditRequiresLimit) }
        return parts.joined(separator: " · ")
    }

    private func expirationText(for date: Date?) -> String {
        guard let date else { return L10n.resetCreditExpirationUnavailable }

        switch resetTimeFormat {
        case .relative:
            let seconds = date.timeIntervalSinceNow
            guard seconds > 0 else { return L10n.resetCreditExpired }
            return L10n.resetCreditExpires(in: RelativeResetTime(seconds: Int(seconds)))
        case .absolute:
            return L10n.resetCreditExpires(date: L10n.compactDateTime(date, includesTime: false))
        }
    }
}

// MARK: - Limit Overlay View (traditional frosted glass over quota progress only)

struct LimitOverlayView: View {
    let usage: UsageResponse
    var resetTimeFormat: ResetTimeFormat = .relative
    @ObservedObject var localeManager = LocaleManager.shared

    private var limitLabels: [String] {
        var labels: [String] = []
        // From rate_limit windows that reached 100%
        if let rl = usage.rateLimit {
            if let p = rl.primaryWindow, p.usedPercent >= 100 {
                labels.append(limitLabel(seconds: p.limitWindowSeconds))
            }
            if let s = rl.secondaryWindow, s.usedPercent >= 100 {
                let label = limitLabel(seconds: s.limitWindowSeconds)
                if !labels.contains(label) { labels.append(label) }
            }
            if rl.limitReached && labels.isEmpty {
                // Use reachedType to show specific limit label
                if let reachedType = usage.rateLimitReachedType {
                    let type = reachedType.type.lowercased()
                    if type.contains("weekly") || type.contains("7d") || type.contains("week") || type == "secondary" {
                        labels.append(L10n.weeklyLimitReached())
                    } else if type.contains("5h") || type.contains("5hour") || type.contains("hour") || type == "primary" {
                        labels.append(L10n.fiveHourLimitReached())
                    } else {
                        labels.append(L10n.limitReached)
                    }
                } else {
                    labels.append(L10n.limitReached)
                }
            }
        }
        // From rate_limit_reached_type
        if labels.isEmpty, let reachedType = usage.rateLimitReachedType {
            let type = reachedType.type.lowercased()
            if type.contains("5h") || type.contains("5hour") || type.contains("hour") {
                labels.append(L10n.fiveHourLimitReached())
            } else if type.contains("weekly") || type.contains("7d") || type.contains("week") {
                labels.append(L10n.weeklyLimitReached())
            } else {
                labels.append(L10n.limitReached)
            }
        }
        return labels
    }

    private var resetTimeText: String? {
        // Collect all reset times from limited windows
        var resetTimes: [(afterSeconds: Int, resetAt: Int)] = []
        if let rl = usage.rateLimit {
            if let p = rl.primaryWindow, p.usedPercent >= 100 {
                resetTimes.append((p.resetAfterSeconds, p.resetAt))
            }
            if let s = rl.secondaryWindow, s.usedPercent >= 100 {
                resetTimes.append((s.resetAfterSeconds, s.resetAt))
            }
        }
        // Pick the soonest reset
        guard let soonest = resetTimes.min(by: { a, b in
            let aSec = a.afterSeconds > 0 ? a.afterSeconds : max(0, a.resetAt - Int(Date().timeIntervalSince1970))
            let bSec = b.afterSeconds > 0 ? b.afterSeconds : max(0, b.resetAt - Int(Date().timeIntervalSince1970))
            return aSec < bSec
        }) else { return nil }

        if resetTimeFormat == .relative {
            let seconds: Int
            if soonest.afterSeconds > 0 {
                seconds = soonest.afterSeconds
            } else if soonest.resetAt > 0 {
                seconds = max(0, soonest.resetAt - Int(Date().timeIntervalSince1970))
            } else {
                return nil
            }
            guard seconds > 0 else { return nil }
            let relativeTime = RelativeResetTime(seconds: seconds)
            return L10n.resetRelative(relativeTime)
        } else {
            let targetDate: Date
            if soonest.resetAt > 0 {
                targetDate = Date(timeIntervalSince1970: TimeInterval(soonest.resetAt))
            } else if soonest.afterSeconds > 0 {
                targetDate = Date().addingTimeInterval(TimeInterval(soonest.afterSeconds))
            } else {
                return nil
            }
            return L10n.resetAbsoluteTime(targetDate)
        }
    }

    private func limitLabel(seconds: Int) -> String {
        let hours = seconds / 3600
        if hours >= 168 {
            return L10n.weeklyLimitReached()
        } else {
            return L10n.fiveHourLimitReached()
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            ForEach(limitLabels, id: \.self) { label in
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "ff3b30"))
                    Text(label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: "ff3b30"))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color(hex: "ff3b30").opacity(0.1))
                .clipShape(Capsule())
            }

            if let resetText = resetTimeText {
                Text(resetText)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color(hex: "ff3b30").opacity(0.7))
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            MenuBarPanelStyle.inset,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(MenuBarPanelStyle.border, lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Menu Bar Panel

struct MenuBarView: View {
    @ObservedObject var accountStore: AccountStore
    @ObservedObject var localeManager = LocaleManager.shared
    @ObservedObject var codexResetService: CodexResetService
    @ObservedObject var accountNavigation: MenuBarAccountNavigation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayMode: DisplayMode = .remaining
    @State private var resetTimeFormat: ResetTimeFormat = .relative
    @State private var showResetRadar = true
    @State private var showQuotaAllowanceSummary = true

    private var visibleAccounts: [Account] {
        accountStore.accounts.filter { !$0.isHidden }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView

            if showResetRadar {
                CodexResetRadarView(
                    service: codexResetService,
                    resetTimeFormat: resetTimeFormat
                )
                    .padding(.horizontal, 12)
                    .padding(.top, 2)
            }

            // Content
            if accountStore.isLoading && accountStore.accounts.isEmpty {
                loadingPlaceholder
            } else if accountStore.accounts.isEmpty {
                emptyStateView
            } else if visibleAccounts.isEmpty {
                hiddenAccountsEmptyState
            } else {
                accountsQuotaView
            }

            // Footer
            footerView
        }
        .frame(width: MenuBarPanelStyle.width)
        .frame(maxHeight: MenuBarPanelStyle.maximumHeight, alignment: .top)
        .background {
            Rectangle().fill(.ultraThinMaterial)
            MenuBarPanelStyle.background.opacity(0.88)
        }
        .onAppear {
            loadDisplayMode()
            loadResetTimeFormat()
            loadResetRadarVisibility()
            loadQuotaAllowanceSummaryVisibility()
        }
        .onReceive(NotificationCenter.default.publisher(for: .displayModeChanged)) { _ in
            loadDisplayMode()
        }
        .onReceive(NotificationCenter.default.publisher(for: .resetTimeFormatChanged)) { _ in
            loadResetTimeFormat()
        }
        .onReceive(NotificationCenter.default.publisher(for: .resetRadarVisibilityChanged)) { _ in
            loadResetRadarVisibility()
        }
        .onReceive(NotificationCenter.default.publisher(for: .quotaAllowanceSummaryVisibilityChanged)) { _ in
            loadQuotaAllowanceSummaryVisibility()
        }
    }

    private var headerView: some View {
        HStack(spacing: 9) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                .resizable()
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)

            Text("Codex Monitor")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            Button {
                Task { await accountStore.refreshAll() }
            } label: {
                Group {
                    if accountStore.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .frame(width: 28, height: 28)
            }
            .disabled(accountStore.isLoading)
            .help(L10n.refreshModels)
            .accessibilityLabel(L10n.refreshModels)

            Button {
                WindowManager.shared.openSettingsWindow(initialTab: .preferences)
            } label: {
                Image(systemName: "gearshape")
                    .frame(width: 28, height: 28)
            }
            .help(L10n.settings)
            .accessibilityLabel(L10n.settings)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.secondary)
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private func loadDisplayMode() {
        let modeString = UserDefaults.standard.string(forKey: PreferencesKeys.displayMode) ?? DisplayMode.remaining.rawValue
        displayMode = DisplayMode(rawValue: modeString) ?? .remaining
    }

    private func loadResetTimeFormat() {
        let formatString = UserDefaults.standard.string(forKey: PreferencesKeys.resetTimeFormat) ?? ResetTimeFormat.relative.rawValue
        resetTimeFormat = ResetTimeFormat(rawValue: formatString) ?? .relative
    }

    private func loadResetRadarVisibility() {
        showResetRadar = (UserDefaults.standard.object(forKey: PreferencesKeys.showResetRadar) as? Bool) ?? true
    }

    private func loadQuotaAllowanceSummaryVisibility() {
        showQuotaAllowanceSummary = (UserDefaults.standard.object(
            forKey: PreferencesKeys.showQuotaAllowanceSummary
        ) as? Bool) ?? true
    }

    private func isRateLimited(_ usage: UsageResponse) -> Bool {
        if usage.rateLimitReachedType != nil { return true }
        if let rl = usage.rateLimit, rl.limitReached { return true }
        if let credits = usage.credits, credits.overageLimitReached { return true }
        return false
    }

    private func resetCredits(for accountID: UUID) -> RateLimitResetCredits? {
        guard case .success(let credits) = accountStore.resetCreditsData[accountID],
              credits.availableCount > 0
        else { return nil }
        return credits
    }

    // MARK: - Loading Placeholder

    private var loadingPlaceholder: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ShimmerView().frame(height: 130)
                ShimmerView().frame(height: 130)
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
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
                WindowManager.shared.openSettingsWindow(initialTab: .accounts)
            }) {
                Label(L10n.addAccount, systemImage: "plus")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hiddenAccountsEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "eye.slash")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)

            Text(L10n.allAccountsHidden)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Button(L10n.manageAccounts) {
                WindowManager.shared.openSettingsWindow(initialTab: .accounts)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 30)
    }

    // MARK: - Account Cards

    private var accountsQuotaView: some View {
        AccountFocusScrollView(navigation: accountNavigation) {
            VStack(spacing: 10) {
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

                ForEach(visibleAccounts) { account in
                    let usageResult = accountStore.usageData[account.id]
                    let resetCredits = resetCredits(for: account.id)
                    let limited = usageResult.flatMap { result -> Bool? in
                        if case .success(let u) = result { return isRateLimited(u) }
                        return nil
                    } ?? false

                    VStack(spacing: 0) {
                        // Account header: name + plan badge
                        HStack(alignment: .center, spacing: 9) {
                            ProviderIconView(provider: account.provider, size: 20)
                                .frame(width: 32, height: 32)
                                .background(MenuBarPanelStyle.inset, in: RoundedRectangle(cornerRadius: 9))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(account.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .help(account.name)

                                if let usageResult, case .success(let usage) = usageResult {
                                    Text(providerPlanLabel(account: account, usage: usage))
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                        .padding(.bottom, 10)

                        // Quota cards content
                        if let usageResult {
                            switch usageResult {
                            case .success(let usage):
                                VStack(spacing: 0) {
                                    if let metadata = usage.fetchMetadata, metadata.isStale {
                                        VStack(alignment: .leading, spacing: 3) {
                                            if let retryAt = metadata.retryAt {
                                                Text(L10n.claudeUsageRateLimited(retryAt: retryAt))
                                            }
                                            Text(L10n.cachedUsageAsOf(metadata.fetchedAt))
                                        }
                                        .font(.system(size: 10))
                                        .foregroundStyle(.orange)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 12)
                                        .padding(.bottom, 8)
                                    }
                                    Group {
                                        if account.provider == .openCodeGo {
                                            OpenCodeGoQuotaView(
                                                usage: usage,
                                                displayMode: displayMode,
                                                allowanceSummary: quotaAllowanceSummary(
                                                    account: account,
                                                    usage: usage
                                                ),
                                                isLimited: limited,
                                                resetTimeFormat: resetTimeFormat
                                            )
                                        } else {
                                            QuotaCardsGridView(
                                                usage: usage,
                                                displayMode: displayMode,
                                                allowanceSummary: quotaAllowanceSummary(
                                                    account: account,
                                                    usage: usage
                                                ),
                                                isLimited: limited,
                                                resetTimeFormat: resetTimeFormat
                                            )
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.bottom, 8)
                                    .blur(radius: limited ? 1.5 : 0)
                                    .overlay {
                                        if limited {
                                            LimitOverlayView(
                                                usage: usage,
                                                resetTimeFormat: resetTimeFormat
                                            )
                                            .padding(.horizontal, 8)
                                            .padding(.bottom, 8)
                                        }
                                    }

                                    if let resetCredits {
                                        Divider().opacity(0.25)
                                            .padding(.horizontal, 14)
                                        ResetCreditsCompactView(
                                            credits: resetCredits,
                                            provider: account.provider,
                                            resetTimeFormat: resetTimeFormat
                                        )
                                    }
                                }
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
                    .background(MenuBarPanelStyle.card)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(MenuBarPanelStyle.border, lineWidth: 0.5)
                            .allowsHitTesting(false)
                    }
                    .id(account.id)
                }
            }
            .padding(12)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: visibleAccounts.count)
        }
        .menuBarScrollEdgeTreatment()
    }

    private var formattedRefreshTime: String {
        if let time = accountStore.lastRefreshTime {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return L10n.updatedAt(time: formatter.string(from: time))
        }
        return L10n.notYetUpdated
    }

    private func quotaAllowanceSummary(account: Account, usage: UsageResponse) -> QuotaAllowanceSummary? {
        guard showQuotaAllowanceSummary else { return nil }
        return QuotaAllowanceSummary.make(
            from: usage.rateLimit,
            provider: account.provider,
            calibratedCapacityRatio: QuotaEquivalenceEstimator.shared.capacityRatio(
                accountID: account.id,
                provider: account.provider,
                planType: usage.planType
            )
        )
    }

    private func providerPlanLabel(account: Account, usage: UsageResponse) -> String {
        if account.provider == .openCodeGo {
            let plan = usage.planType.lowercased()
            if plan.contains("cached") { return L10n.cachedShort }
            return L10n.dashboardShort
        }
        let provider = account.provider.displayName
        let plan = usage.displayPlanType
        if provider.caseInsensitiveCompare(plan) == .orderedSame { return provider }
        return "\(provider) · \(plan)"
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack(spacing: 8) {
            Label(formattedRefreshTime, systemImage: "clock")
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer(minLength: 4)

            Button(action: {
                NSApp.terminate(nil)
            }) {
                Image(systemName: "power")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help(L10n.quitCodexMonitor)
            .accessibilityLabel(L10n.quitCodexMonitor)
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 3)
        .background(MenuBarPanelStyle.card.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
}

private extension View {
    @ViewBuilder
    func menuBarScrollEdgeTreatment() -> some View {
        if #available(macOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
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
