import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var accountStore: MobileAccountStore
    @AppStorage(MobilePreferenceKeys.displayMode, store: AppGroupConstants.defaults) private var displayModeRaw = UsageDisplayMode.remaining.rawValue
    @AppStorage(MobilePreferenceKeys.resetTimeFormat, store: AppGroupConstants.defaults) private var resetTimeFormatRaw = ResetTimeFormat.relative.rawValue

    private var displayMode: UsageDisplayMode {
        UsageDisplayMode(rawValue: displayModeRaw) ?? .remaining
    }

    private var resetTimeFormat: ResetTimeFormat {
        ResetTimeFormat(rawValue: resetTimeFormatRaw) ?? .relative
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                DashboardSummaryCard(
                    accountCount: accountStore.accounts.count,
                    overallUsedPercent: accountStore.overallUsedPercent,
                    hasLimitedAccount: accountStore.hasLimitedAccount,
                    isLoading: accountStore.isLoading,
                    lastRefreshTime: accountStore.lastRefreshTime
                )

                if accountStore.accounts.isEmpty {
                    EmptyDashboardState()
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(accountStore.sortedSnapshots) { snapshot in
                            AccountQuotaCard(
                                snapshot: snapshot,
                                displayMode: displayMode,
                                resetTimeFormat: resetTimeFormat
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Codex Monitor")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await accountStore.refreshAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(accountStore.isLoading)
                .accessibilityLabel("Refresh quota")
            }
        }
        .refreshable {
            await accountStore.refreshAll()
        }
    }
}

private struct DashboardSummaryCard: View {
    let accountCount: Int
    let overallUsedPercent: Int?
    let hasLimitedAccount: Bool
    let isLoading: Bool
    let lastRefreshTime: Date?

    private var tint: Color {
        if hasLimitedAccount { return Color(hex: "EF4444") }
        if let overallUsedPercent, overallUsedPercent >= 80 { return Color(hex: "F97316") }
        return Color(hex: "2563EB")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summaryTitle)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color(hex: "111827"))

                    Text("\(accountCount) synced account\(accountCount == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ZStack {
                    Circle()
                        .stroke(tint.opacity(0.12), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: CGFloat((overallUsedPercent ?? 0)) / 100)
                        .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    if isLoading {
                        ProgressView()
                    } else {
                        Text(overallUsedPercent.map { "\($0)%" } ?? "-")
                            .font(.system(size: 18, weight: .bold).monospacedDigit())
                    }
                }
                .frame(width: 76, height: 76)
            }

            HStack(spacing: 8) {
                Image(systemName: hasLimitedAccount ? "exclamationmark.triangle.fill" : "icloud")
                    .foregroundStyle(tint)
                Text(statusText)
                    .font(.footnote)
                    .foregroundStyle(Color(hex: "4B5563"))
                Spacer()
            }
        }
        .padding(18)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 0.7)
        }
    }

    private var summaryTitle: String {
        if accountCount == 0 { return "No accounts" }
        if hasLimitedAccount { return "Limit reached" }
        if let overallUsedPercent, overallUsedPercent >= 80 { return "High usage" }
        return "Quota healthy"
    }

    private var statusText: String {
        if accountCount == 0 { return "Add accounts on Mac, then let iCloud sync them here." }
        if isLoading { return "Refreshing account usage..." }
        return "Updated \(UsagePresentation.freshnessText(lastRefreshTime))"
    }
}

private struct EmptyDashboardState: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "macbook.and.iphone")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Color(hex: "9CA3AF"))

            VStack(spacing: 6) {
                Text("Waiting for iCloud sync")
                    .font(.headline)
                    .foregroundStyle(Color(hex: "111827"))
                Text("Accounts are managed on Mac. This app syncs and monitors the accounts already added there.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 46)
        .padding(.horizontal, 24)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 0.7)
        }
    }
}

private struct AccountQuotaCard: View {
    let snapshot: WidgetAccountSnapshot
    let displayMode: UsageDisplayMode
    let resetTimeFormat: ResetTimeFormat

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Circle()
                    .fill(Color(hex: "F3F4F6"))
                    .frame(width: 42, height: 42)
                    .overlay {
                        Text(initials)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(hex: "4B5563"))
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: "111827"))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(snapshot.planType?.localizedCapitalized ?? "Synced account")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 10)

                if snapshot.isLimited {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(Color(hex: "EF4444"))
                        .accessibilityLabel("Limit reached")
                }
            }

            if let errorMessage = snapshot.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Color(hex: "EF4444"))
                    .lineLimit(2)
            } else if snapshot.primaryUsedPercent == nil && snapshot.secondaryUsedPercent == nil && snapshot.creditsBalance == nil && !snapshot.creditsUnlimited {
                Label("No usage data yet", systemImage: "questionmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    if snapshot.primaryUsedPercent != nil {
                        QuotaMetricRow(
                            title: UsagePresentation.windowLabel(seconds: snapshot.primaryWindowSeconds),
                            usedPercent: snapshot.primaryUsedPercent,
                            resetAt: snapshot.primaryResetAt,
                            displayMode: displayMode,
                            resetTimeFormat: resetTimeFormat
                        )
                    }

                    if snapshot.secondaryUsedPercent != nil {
                        QuotaMetricRow(
                            title: UsagePresentation.windowLabel(seconds: snapshot.secondaryWindowSeconds),
                            usedPercent: snapshot.secondaryUsedPercent,
                            resetAt: snapshot.secondaryResetAt,
                            displayMode: displayMode,
                            resetTimeFormat: resetTimeFormat
                        )
                    }

                    if snapshot.creditsUnlimited || snapshot.creditsBalance != nil {
                        CreditsRow(snapshot: snapshot)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(snapshot.isLimited ? Color(hex: "EF4444").opacity(0.2) : Color.black.opacity(0.05), lineWidth: 0.7)
        }
    }

    private var initials: String {
        let source = snapshot.displayName
        let parts = source.split(whereSeparator: { $0 == " " || $0 == "@" || $0 == "." })
        let letters = parts.prefix(2).compactMap(\.first).map { String($0).uppercased() }
        return letters.isEmpty ? "CM" : letters.joined()
    }
}

private struct QuotaMetricRow: View {
    let title: String
    let usedPercent: Int?
    let resetAt: Int?
    let displayMode: UsageDisplayMode
    let resetTimeFormat: ResetTimeFormat

    private var displayPercent: Int? {
        UsagePresentation.displayPercent(usedPercent: usedPercent, mode: displayMode)
    }

    private var tint: Color {
        guard let usedPercent else { return Color(hex: "9CA3AF") }
        if usedPercent >= 90 { return Color(hex: "EF4444") }
        if usedPercent >= 70 { return Color(hex: "F97316") }
        return Color(hex: "22C55E")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color(hex: "4B5563"))

                Spacer()

                Text(displayPercent.map { "\($0)% \(displayMode.title.lowercased())" } ?? "-")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color(hex: "111827"))
            }

            ProgressView(value: Double(usedPercent ?? 0), total: 100)
                .tint(tint)

            if let reset = UsagePresentation.resetText(resetAt: resetAt, format: resetTimeFormat) {
                Text("Resets in \(reset)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CreditsRow: View {
    let snapshot: WidgetAccountSnapshot

    var body: some View {
        HStack {
            Label("Credits", systemImage: "creditcard")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color(hex: "4B5563"))

            Spacer()

            Text(snapshot.creditsUnlimited ? "Unlimited" : (snapshot.creditsBalance ?? "-"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(snapshot.hasCredits == false ? Color(hex: "EF4444") : Color(hex: "111827"))
        }
    }
}

#if DEBUG
struct DashboardView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            DashboardView()
                .environmentObject(MobileAccountStore())
        }
    }
}
#endif
