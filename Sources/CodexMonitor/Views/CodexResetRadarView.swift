import AppKit
import SwiftUI

struct CodexResetRadarView: View {
    @ObservedObject var service: CodexResetService
    @StateObject private var hoverPanel = CodexResetHoverPanelController()
    @StateObject private var avatarStore = CodexResetAvatarStore()

    private let siteURL = URL(string: "https://codex-reset.com")!
    private let avatarURL = URL(string: "https://codex-reset.com/tibo-avatar.jpg")!

    var body: some View {
        Button(action: openSite) {
            HStack(spacing: 7) {
                Circle()
                    .fill(accentColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: accentColor.opacity(0.45), radius: 2)

                Text("CODEX RESET RADAR")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 6)

                if service.isLoading && service.snapshot == nil {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.65)
                } else {
                    Text(probabilityText)
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                        .foregroundStyle(accentColor)
                }

                Text("24H")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 11)
            .frame(height: 28)
            .contentShape(Rectangle())
            .background(accentColor.opacity(0.075))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 0.5)
            }
            .background(CodexResetHoverPanelAnchor(controller: hoverPanel))
        }
        .buttonStyle(.plain)
        .onHover(perform: updateHover)
        .task {
            async let resetData: Void = service.refreshIfNeeded()
            async let avatar: Void = avatarStore.preload(from: avatarURL)
            _ = await (resetData, avatar)
        }
        .onDisappear {
            hoverPanel.hide()
        }
        .accessibilityLabel("Codex Reset Radar, \(probabilityText) in the next 24 hours")
        .help("Community forecast. Hover for the latest @thsottiaux feed.")
    }

    private var probabilityText: String {
        guard let probability = service.snapshot?.probability24h else { return "--%" }
        return "\(probability)%"
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

    private func updateHover(_ isHovering: Bool) {
        if isHovering {
            hoverPanel.show(
                CodexResetFeedCard(service: service, avatarStore: avatarStore)
                    .onHover { panelIsHovering in
                        if panelIsHovering {
                            hoverPanel.keepVisible()
                        } else {
                            hoverPanel.scheduleHide()
                        }
                    }
            )
        } else {
            hoverPanel.scheduleHide()
        }
    }

    private func openSite() {
        NSWorkspace.shared.open(siteURL)
    }
}

private struct CodexResetFeedCard: View {
    @ObservedObject var service: CodexResetService
    @ObservedObject var avatarStore: CodexResetAvatarStore

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
        .frame(width: 300)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
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
                    Text("@\(snapshot.feed.profile.handle)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                statusBadge(snapshot)
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
                    Text("COMMUNITY FORECAST · NEXT 24H")
                        .font(.system(size: 8.5, weight: .semibold))
                        .tracking(0.45)
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
                Text("Independent data from codex-reset.com")
                    .font(.system(size: 8.5))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Open on X ↗", action: openDisplayedPost)
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.blue)
            }
        }
        .padding(14)
    }

    private var loadingContent: some View {
        HStack(spacing: 9) {
            ProgressView().controlSize(.small)
            Text("Checking Tibo's latest feed…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
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
                Task { await service.refresh() }
            }
                .controlSize(.small)
        }
        .padding(16)
    }

    private func displayText(_ snapshot: CodexResetSnapshot) -> String {
        if let signal = snapshot.activeSignal { return signal.summary }
        return snapshot.latestTweet?.text ?? "No recent posts were returned by the feed."
    }

    @ViewBuilder
    private func statusBadge(_ snapshot: CodexResetSnapshot) -> some View {
        let status = feedStatus(snapshot)
        Text(status.title.uppercased())
            .font(.system(size: 8, weight: .bold))
            .tracking(0.35)
            .foregroundStyle(status.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(status.color.opacity(0.11))
            .clipShape(Capsule())
    }

    private func feedStatus(_ snapshot: CodexResetSnapshot) -> (title: String, color: Color) {
        if snapshot.feed.stale { return ("Feed delayed", .orange) }
        if snapshot.activeSignal != nil { return ("Active signal", .purple) }
        if snapshot.latestTweet?.verificationStatus == "confirmed" { return ("Reset confirmed", .green) }
        if snapshot.latestTweet?.resetVerificationCandidate == true { return ("Reset candidate", .orange) }
        if snapshot.latestTweet?.kind == "codex" { return ("Codex update", .blue) }
        return ("Latest post", .secondary)
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
