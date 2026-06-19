import SwiftUI
import WidgetKit

struct CodexMonitorWidgetEntry: TimelineEntry {
    let date: Date
    let snapshots: [WidgetAccountSnapshot]
    let isFresh: Bool
}

struct CodexMonitorTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> CodexMonitorWidgetEntry {
        CodexMonitorWidgetEntry(
            date: Date(),
            snapshots: [
                WidgetAccountSnapshot(
                    id: UUID(),
                    name: "Codex Account",
                    accountEmail: "account@example.com",
                    planType: "plus",
                    primaryUsedPercent: 38,
                    primaryResetAt: Int(Date().addingTimeInterval(7_200).timeIntervalSince1970),
                    primaryWindowSeconds: 18_000,
                    secondaryUsedPercent: 62,
                    secondaryResetAt: Int(Date().addingTimeInterval(86_400).timeIntervalSince1970),
                    secondaryWindowSeconds: 604_800,
                    isLimited: false,
                    refreshedAt: Date()
                )
            ],
            isFresh: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (CodexMonitorWidgetEntry) -> Void) {
        completion(makeCachedEntry(family: context.family))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CodexMonitorWidgetEntry>) -> Void) {
        Task {
            let entry = await makeEntry(family: context.family)
            let interval = MobileRefreshInterval(
                rawValue: AppGroupConstants.defaults.integer(forKey: MobilePreferenceKeys.refreshInterval)
            ) ?? .fiveMinutes
            let nextRefresh = interval == .off
                ? Date().addingTimeInterval(15 * 60)
                : Date().addingTimeInterval(TimeInterval(interval.rawValue))
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }

    private func makeCachedEntry(family: WidgetFamily) -> CodexMonitorWidgetEntry {
        let snapshots = selectedSnapshots(family: family, snapshots: WidgetSnapshotStore.loadSnapshots())
        return CodexMonitorWidgetEntry(date: Date(), snapshots: snapshots, isFresh: false)
    }

    private func makeEntry(family: WidgetFamily) async -> CodexMonitorWidgetEntry {
        let accounts = loadAccounts()
        let visibleAccounts = selectedAccounts(family: family, accounts: accounts)
        guard !visibleAccounts.isEmpty else {
            return makeCachedEntry(family: family)
        }

        var usageData: [UUID: Result<UsageResponse, APIError>] = [:]
        await withTaskGroup(of: (UUID, Result<UsageResponse, APIError>).self) { group in
            for account in visibleAccounts {
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

        let refreshedAt = Date()
        let snapshots = visibleAccounts.map {
            WidgetAccountSnapshot(account: $0, result: usageData[$0.id], refreshedAt: refreshedAt)
        }
        WidgetSnapshotStore.saveSnapshots(snapshots)
        WidgetSnapshotStore.saveAvailableAccounts(accounts)
        return CodexMonitorWidgetEntry(date: refreshedAt, snapshots: snapshots, isFresh: true)
    }

    private func loadAccounts() -> [CloudSyncedAccount] {
        let cloudStore = ICloudAccountSyncStore()
        cloudStore.synchronize()
        if let accounts = cloudStore.loadPayload()?.accounts, !accounts.isEmpty {
            return accounts.sorted { $0.createdAt < $1.createdAt }
        }
        return WidgetSnapshotStore.loadAvailableAccounts().sorted { $0.createdAt < $1.createdAt }
    }

    private func selectedAccounts(family: WidgetFamily, accounts: [CloudSyncedAccount]) -> [CloudSyncedAccount] {
        let selectedIDs = WidgetPreferenceStore.selectedAccountIDs()
        let selected = selectedIDs.isEmpty ? accounts : accounts.filter { selectedIDs.contains($0.id) }
        return Array(selected.prefix(limit(for: family)))
    }

    private func selectedSnapshots(family: WidgetFamily, snapshots: [WidgetAccountSnapshot]) -> [WidgetAccountSnapshot] {
        let selectedIDs = WidgetPreferenceStore.selectedAccountIDs()
        let selected = selectedIDs.isEmpty ? snapshots : snapshots.filter { selectedIDs.contains($0.id) }
        return Array(selected.prefix(limit(for: family)))
    }

    private func limit(for family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall:
            return 1
        case .systemMedium:
            return 2
        case .systemLarge, .systemExtraLarge:
            return 4
        default:
            return 2
        }
    }
}

struct CodexMonitorQuotaWidget: Widget {
    let kind = "CodexMonitorQuotaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CodexMonitorTimelineProvider()) { entry in
            CodexMonitorWidgetView(entry: entry)
                .widgetURL(URL(string: "codexmonitor://refresh"))
        }
        .configurationDisplayName("Codex Quota")
        .description("Quickly check synced Codex account quota.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct CodexMonitorWidgetView: View {
    let entry: CodexMonitorWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetBackground()
    }

    @ViewBuilder
    private var content: some View {
        if entry.snapshots.isEmpty {
            EmptyWidgetView()
        } else {
            switch family {
            case .systemSmall:
                SmallWidgetView(snapshot: entry.snapshots[0], date: entry.date)
            case .systemLarge:
                LargeWidgetView(snapshots: entry.snapshots, date: entry.date)
            default:
                MediumWidgetView(snapshots: entry.snapshots, date: entry.date)
            }
        }
    }
}

private struct EmptyWidgetView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "icloud")
                .font(.title3)
                .foregroundStyle(Color(hex: "2563EB"))
            Text("No accounts")
                .font(.headline)
                .foregroundStyle(Color(hex: "111827"))
            Text("Open Codex Monitor after Mac sync finishes.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding()
    }
}

private struct SmallWidgetView: View {
    let snapshot: WidgetAccountSnapshot
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeader(date: date, compact: true)

            Spacer(minLength: 0)

            Text(snapshot.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(hex: "4B5563"))
                .lineLimit(1)
                .truncationMode(.middle)

            PrimaryMetric(snapshot: snapshot, large: true)
        }
        .padding()
    }
}

private struct MediumWidgetView: View {
    let snapshots: [WidgetAccountSnapshot]
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WidgetHeader(date: date, compact: false)

            HStack(spacing: 10) {
                ForEach(snapshots) { snapshot in
                    WidgetAccountPanel(snapshot: snapshot)
                }
                if snapshots.count == 1 {
                    Spacer(minLength: 0)
                }
            }
        }
        .padding()
    }
}

private struct LargeWidgetView: View {
    let snapshots: [WidgetAccountSnapshot]
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WidgetHeader(date: date, compact: false)

            VStack(spacing: 9) {
                ForEach(snapshots) { snapshot in
                    WidgetAccountRow(snapshot: snapshot)
                }
            }

            Spacer(minLength: 0)
        }
        .padding()
    }
}

private struct WidgetHeader: View {
    let date: Date
    let compact: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: compact ? 13 : 15, weight: .semibold))
                .foregroundStyle(Color(hex: "2563EB"))

            Text(compact ? "Quota" : "Codex Quota")
                .font(.system(size: compact ? 12 : 14, weight: .semibold))
                .foregroundStyle(Color(hex: "111827"))
                .lineLimit(1)

            Spacer(minLength: 6)

            Text(date, style: .time)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

private struct WidgetAccountPanel: View {
    let snapshot: WidgetAccountSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(snapshot.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(hex: "4B5563"))
                .lineLimit(1)
                .truncationMode(.middle)

            PrimaryMetric(snapshot: snapshot, large: false)

            if let secondary = snapshot.secondaryUsedPercent {
                MiniProgress(title: "Weekly", usedPercent: secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(hex: "F9FAFB"))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(snapshot.isLimited ? Color(hex: "EF4444").opacity(0.22) : Color.black.opacity(0.05), lineWidth: 0.7)
        }
    }
}

private struct WidgetAccountRow: View {
    let snapshot: WidgetAccountSnapshot

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(hex: "111827"))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(snapshot.planType?.localizedCapitalized ?? "Synced")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            PrimaryMetric(snapshot: snapshot, large: false)
                .frame(width: 92, alignment: .trailing)
        }
        .padding(10)
        .background(Color(hex: "F9FAFB"))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct PrimaryMetric: View {
    let snapshot: WidgetAccountSnapshot
    let large: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: large ? 8 : 6) {
            if let errorMessage = snapshot.errorMessage {
                Text("!")
                    .font(.system(size: large ? 28 : 20, weight: .bold))
                    .foregroundStyle(Color(hex: "EF4444"))
                    .accessibilityLabel(errorMessage)
            } else if let used = snapshot.primaryUsedPercent {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(max(0, 100 - used))")
                        .font(.system(size: large ? 32 : 22, weight: .bold).monospacedDigit())
                        .foregroundStyle(snapshot.isLimited ? Color(hex: "EF4444") : Color(hex: "111827"))
                    Text("%")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                MiniProgress(title: "5h left", usedPercent: used)
            } else if snapshot.creditsUnlimited {
                Image(systemName: "infinity")
                    .font(.system(size: large ? 31 : 22, weight: .bold))
                    .foregroundStyle(Color(hex: "22C55E"))
            } else if let balance = snapshot.creditsBalance {
                Text(balance)
                    .font(.system(size: large ? 26 : 19, weight: .bold).monospacedDigit())
                    .foregroundStyle(snapshot.hasCredits == false ? Color(hex: "EF4444") : Color(hex: "111827"))
                    .lineLimit(1)
            } else {
                Text("-")
                    .font(.system(size: large ? 28 : 20, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct MiniProgress: View {
    let title: String
    let usedPercent: Int

    private var tint: Color {
        if usedPercent >= 90 { return Color(hex: "EF4444") }
        if usedPercent >= 70 { return Color(hex: "F97316") }
        return Color(hex: "22C55E")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.black.opacity(0.08))
                    Capsule()
                        .fill(tint)
                        .frame(width: proxy.size.width * CGFloat(max(0, min(100, usedPercent))) / 100)
                }
            }
            .frame(height: 4)

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private extension View {
    @ViewBuilder
    func widgetBackground() -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(Color.white, for: .widget)
        } else {
            background(Color.white)
        }
    }
}

#if DEBUG
struct CodexMonitorWidgetView_Previews: PreviewProvider {
    static var previews: some View {
        CodexMonitorWidgetView(
            entry: CodexMonitorWidgetEntry(
                date: Date(),
                snapshots: [
                    WidgetAccountSnapshot(
                        id: UUID(),
                        name: "Primary",
                        accountEmail: "primary@example.com",
                        planType: "plus",
                        primaryUsedPercent: 34,
                        secondaryUsedPercent: 55,
                        isLimited: false,
                        refreshedAt: Date()
                    )
                ],
                isFresh: true
            )
        )
        .previewContext(WidgetPreviewContext(family: .systemMedium))
    }
}
#endif
