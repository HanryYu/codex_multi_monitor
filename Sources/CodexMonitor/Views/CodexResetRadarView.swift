import AppKit
import SwiftUI

struct CodexResetRadarView: View {
    @ObservedObject var service: CodexResetService
    @StateObject private var detailsPanel = CodexResetDetailsPanelController()
    @StateObject private var avatarStore = CodexResetAvatarStore()
    @State private var delayedHoverTask: Task<Void, Never>?
    @State private var isHovering = false

    private let siteURL = URL(string: "https://codex-reset.com")!
    private let avatarURL = URL(string: "https://codex-reset.com/tibo-avatar.jpg")!

    var body: some View {
        Button(action: toggleDetails) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.11))
                    RadarIconView(color: accentColor)
                }
                .frame(width: 24, height: 24)

                Text("Codex Reset Radar")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 6)

                probabilityValue

                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(detailsPanel.isShown ? 180 : 0))
                    .animation(.easeInOut(duration: 0.16), value: detailsPanel.isShown)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(height: 40)
        .background(CodexResetPanelAnchor(controller: detailsPanel))
        .background(
            Color.primary.opacity(detailsPanel.isShown ? 0.065 : (isHovering ? 0.045 : 0.03))
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.075), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .task {
            await avatarStore.preload(from: avatarURL)
        }
        .onDisappear {
            delayedHoverTask?.cancel()
            detailsPanel.close()
        }
        .onHover(perform: updateHover)
        .accessibilityLabel(accessibilityText)
        .accessibilityValue(detailsPanel.isShown ? "Open" : "Closed")
        .help(detailsPanel.isShown ? "Close reset details" : "Open reset details")
    }

    private var probabilityText: String {
        guard let probability = service.snapshot?.probability24h else { return "--%" }
        return "\(probability)%"
    }

    @ViewBuilder
    private var probabilityValue: some View {
        if service.isLoading {
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.6)
                    .frame(width: 10, height: 10)

                Text(L10n.refreshing)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 76, alignment: .trailing)
            .transition(.opacity)
        } else {
            Text(probabilityText)
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundStyle(accentColor)
                .frame(width: 76, alignment: .trailing)
                .transition(.opacity)
        }
    }

    private var accessibilityText: String {
        let action = detailsPanel.isShown ? "Close details" : "Open details"
        if service.isLoading {
            return "Codex Reset Radar, \(L10n.refreshing). \(action)"
        }
        return "Codex Reset Radar, \(probabilityText) in the next 24 hours. \(action)"
    }

    private var accentColor: Color {
        guard let snapshot = service.snapshot else {
            return service.errorMessage == nil ? .secondary : .red
        }
        if snapshot.feed.stale || service.errorMessage != nil { return .orange }
        if snapshot.activeSignal != nil { return .purple }
        if snapshot.probability24h >= 70 { return .red }
        if snapshot.probability24h >= 40 { return .orange }
        return .blue
    }

    private func toggleDetails() {
        delayedHoverTask?.cancel()
        detailsPanel.toggle(feedCard)
    }

    private func updateHover(_ isHovering: Bool) {
        self.isHovering = isHovering
        delayedHoverTask?.cancel()
        guard isHovering, !detailsPanel.isShown else { return }

        scheduleHoverDetails()
    }

    private func scheduleHoverDetails() {
        delayedHoverTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            detailsPanel.show(feedCard)
        }
    }

    private var feedCard: some View {
        CodexResetFeedCard(
            service: service,
            avatarStore: avatarStore,
            sourceURL: siteURL
        )
    }
}

private struct CodexResetFeedCard: View {
    @ObservedObject var service: CodexResetService
    @ObservedObject var avatarStore: CodexResetAvatarStore
    let sourceURL: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let snapshot = service.snapshot {
                feedContent(snapshot)
            } else if service.isLoading {
                loadingContent
            } else {
                errorContent
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func feedContent(_ snapshot: CodexResetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Group {
                    if let avatar = avatarStore.image {
                        Image(nsImage: avatar)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ZStack {
                            Circle().fill(Color.primary.opacity(0.08))
                            Text("T")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: 38, height: 38)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(snapshot.feed.profile.name)
                            .font(.system(size: 13, weight: .bold))
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.blue)
                    }
                    HStack(spacing: 4) {
                        Text("@\(snapshot.feed.profile.handle)")
                        if let postDate = displayedPostDate(snapshot) {
                            Text("·")
                            Text(CodexResetPostTimestamp.text(for: postDate))
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .help(displayedPostDate(snapshot)?.formatted(date: .abbreviated, time: .shortened) ?? "")
                }

                Spacer()

                if let status = noteworthyFeedStatus(snapshot) {
                    Text(status.title)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(status.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(status.color.opacity(0.11))
                        .clipShape(Capsule())
                }

                refreshButton
            }

            Text(displayText(snapshot))
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineSpacing(2)
                .lineLimit(7)
                .textSelection(.enabled)

            if let tweet = snapshot.latestTweet,
               snapshot.activeSignal == nil,
               tweet.replies != nil || tweet.likes != nil {
                HStack(spacing: 15) {
                    if let replies = tweet.replies {
                        metric("bubble", count: replies)
                    }
                    if let likes = tweet.likes {
                        metric("heart", count: likes)
                    }
                }
                .foregroundStyle(.secondary)
            }

            Divider().opacity(0.4)

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Community forecast · Next 24h")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("\(snapshot.probability24h)%")
                        .font(.system(size: 19, weight: .bold).monospacedDigit())
                        .foregroundStyle(forecastColor(snapshot.probability24h))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text("48h  \(snapshot.probability48h)%")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    Text(snapshot.forecast.confidence.capitalized + " confidence")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
            }

            if let lastResetAt = snapshot.forecast.lastResetAt?.codexResetDate {
                Text("Last verified reset \(lastResetAt.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if snapshot.feed.stale || service.errorMessage != nil {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(service.errorMessage == nil ? "Feed is delayed; showing the last cached update." : "Live refresh failed; showing cached data.")
                }
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.orange)
            }

            HStack {
                Link("codex-reset.com ↗", destination: sourceURL)
                    .font(.system(size: 8.5))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Open on X ↗", action: openDisplayedPost)
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.blue)
            }
        }
        .padding(16)
    }

    private var loadingContent: some View {
        HStack(spacing: 10) {
            HStack(spacing: 9) {
                ProgressView().controlSize(.small)
                Text("Checking Tibo's latest feed…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            refreshButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private var refreshButton: some View {
        Button {
            Task { await service.refreshLatest() }
        } label: {
            Group {
                if service.isLoading {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .frame(width: 24, height: 24)
            .contentShape(Circle())
        }
        .buttonStyle(.borderless)
        .disabled(service.isLoading)
        .help(service.isLoading ? L10n.refreshing : L10n.refreshModels)
        .accessibilityLabel(service.isLoading ? L10n.refreshing : L10n.refreshModels)
    }

    private var errorContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Codex Reset is unavailable", systemImage: "wifi.exclamationmark")
                .font(.system(size: 12, weight: .semibold))
            Text(service.errorMessage ?? "The community API did not respond.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Button("Try Again") {
                Task { await service.refreshLatest() }
            }
                .controlSize(.small)
        }
        .padding(16)
    }

    private func displayText(_ snapshot: CodexResetSnapshot) -> String {
        if let signal = snapshot.activeSignal { return signal.summary }
        return snapshot.latestTweet?.text ?? "No recent posts were returned by the feed."
    }

    private func displayedPostDate(_ snapshot: CodexResetSnapshot) -> Date? {
        (snapshot.activeSignal?.at ?? snapshot.latestTweet?.at)?.codexResetDate
    }

    private func noteworthyFeedStatus(_ snapshot: CodexResetSnapshot) -> (title: String, color: Color)? {
        if snapshot.feed.stale { return ("Feed delayed", .orange) }
        if snapshot.activeSignal != nil { return ("Active signal", .purple) }
        if snapshot.latestTweet?.verificationStatus == "confirmed" { return ("Reset confirmed", .green) }
        if snapshot.latestTweet?.resetVerificationCandidate == true { return ("Reset candidate", .orange) }
        return nil
    }

    private func metric(_ systemImage: String, count: Int) -> some View {
        Label(formatCount(count), systemImage: systemImage)
            .font(.system(size: 10))
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }

    private func forecastColor(_ probability: Int) -> Color {
        if probability >= 70 { return .red }
        if probability >= 40 { return .orange }
        return .blue
    }

    private func openDisplayedPost() {
        guard let snapshot = service.snapshot else { return }
        let url = snapshot.activeSignal?.url ?? snapshot.latestTweet?.url ?? URL(string: "https://x.com/thsottiaux")!
        NSWorkspace.shared.open(url)
    }
}

private struct RadarIconView: View {
    let color: Color

    private static let image: NSImage? = {
        let image = NSImage(named: NSImage.Name("RadarLucide"))
            ?? Bundle.main.url(forResource: "RadarLucide", withExtension: "png").flatMap(NSImage.init(contentsOf:))
            ?? Bundle.module.url(forResource: "RadarLucide", withExtension: "png").flatMap(NSImage.init(contentsOf:))
        image?.isTemplate = true
        return image
    }()

    var body: some View {
        Group {
            if let image = Self.image {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
            } else {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .resizable()
                    .scaledToFit()
            }
        }
        .foregroundStyle(color)
        .frame(width: 14, height: 14)
    }
}
