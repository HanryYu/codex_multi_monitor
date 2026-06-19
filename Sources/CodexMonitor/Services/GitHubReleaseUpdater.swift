import AppKit
import Foundation
import UserNotifications

enum AppVersion {
    static let fallback = "0.6.12"

    static var current: String {
        let info = Bundle.main.infoDictionary
        if let version = info?["CFBundleShortVersionString"] as? String, !version.isEmpty {
            return version
        }
        return fallback
    }
}

@MainActor
final class GitHubReleaseUpdater: ObservableObject {
    static let shared = GitHubReleaseUpdater()

    @Published private(set) var isChecking = false
    @Published private(set) var isDownloading = false
    @Published private(set) var availableVersion: String?
    @Published private(set) var downloadedURL: URL?
    @Published private(set) var statusText: String = L10n.updateStatusIdle

    private let owner = "HanryYu"
    private let repository = "codex_multi_monitor"
    private let session: URLSession

    private var latestRelease: GitHubRelease?
    private var automaticCheckTask: Task<Void, Never>?

    private init(session: URLSession = .shared) {
        self.session = session
    }

    func checkAutomaticallyIfNeeded() {
        guard UserDefaults.standard.bool(forKey: PreferencesKeys.automaticUpdatesEnabled) else { return }

        let lastCheck = UserDefaults.standard.object(forKey: PreferencesKeys.lastUpdateCheckAt) as? Date
        if let lastCheck, Date().timeIntervalSince(lastCheck) < 12 * 60 * 60 {
            return
        }

        automaticCheckTask?.cancel()
        automaticCheckTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await self.checkForUpdates(downloadIfAvailable: true, userInitiated: false)
        }
    }

    func checkForUpdates(downloadIfAvailable: Bool, userInitiated: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        statusText = L10n.updateStatusChecking

        defer {
            isChecking = false
            UserDefaults.standard.set(Date(), forKey: PreferencesKeys.lastUpdateCheckAt)
        }

        do {
            let release = try await fetchLatestRelease()
            latestRelease = release

            let releaseVersion = release.versionNumber
            guard VersionComparator.compare(releaseVersion, AppVersion.current) == .orderedDescending else {
                availableVersion = nil
                downloadedURL = nil
                statusText = L10n.updateStatusCurrent(version: AppVersion.current)
                return
            }

            availableVersion = releaseVersion
            statusText = L10n.updateStatusAvailable(version: releaseVersion)

            if downloadIfAvailable {
                try await downloadLatestRelease()
            } else if userInitiated {
                sendUpdateAvailableNotification(version: releaseVersion)
            }
        } catch {
            statusText = L10n.updateStatusFailed(error: error.localizedDescription)
            print("[CodexMonitor] Update check failed: \(error)")
        }
    }

    func downloadLatestRelease() async throws {
        guard !isDownloading else { return }
        guard let release = latestRelease else {
            await checkForUpdates(downloadIfAvailable: true, userInitiated: true)
            return
        }
        guard let asset = release.dmgAsset else {
            statusText = L10n.updateStatusNoAsset
            return
        }

        isDownloading = true
        statusText = L10n.updateStatusDownloading(version: release.versionNumber)
        defer { isDownloading = false }

        let localURL = try await download(asset: asset)
        downloadedURL = localURL
        statusText = L10n.updateStatusDownloaded(version: release.versionNumber)
        sendUpdateReadyNotification(version: release.versionNumber)
    }

    func installDownloadedUpdate() {
        guard let downloadedURL else {
            if let url = latestRelease?.htmlURL {
                NSWorkspace.shared.open(url)
            }
            return
        }

        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension == "app" else {
            NSWorkspace.shared.activateFileViewerSelecting([downloadedURL])
            return
        }

        do {
            let scriptURL = try createInstallerScript(appURL: bundleURL, dmgURL: downloadedURL)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [scriptURL.path, bundleURL.path, downloadedURL.path, "\(ProcessInfo.processInfo.processIdentifier)"]
            try process.run()
            NSApp.terminate(nil)
        } catch {
            statusText = L10n.updateStatusFailed(error: error.localizedDescription)
            NSWorkspace.shared.activateFileViewerSelecting([downloadedURL])
            print("[CodexMonitor] Failed to start installer script: \(error)")
        }
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("CodexMonitor/\(AppVersion.current)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw UpdateError.httpStatus(http.statusCode)
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    private func download(asset: GitHubAsset) async throws -> URL {
        let cacheDir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexMonitor/Updates", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let destination = cacheDir.appendingPathComponent(asset.name)
        if FileManager.default.fileExists(atPath: destination.path) {
            return destination
        }

        let (temporaryURL, response) = try await session.download(from: asset.browserDownloadURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdateError.invalidDownload
        }

        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    private func createInstallerScript(appURL: URL, dmgURL: URL) throws -> URL {
        let script = """
        #!/bin/zsh
        set -euo pipefail

        APP_PATH="$1"
        DMG_PATH="$2"
        APP_PID="$3"
        APP_NAME="CodexMonitor.app"

        while /bin/kill -0 "$APP_PID" 2>/dev/null; do
            /bin/sleep 0.2
        done

        ATTACH_OUTPUT=$(/usr/bin/hdiutil attach -nobrowse -readonly "$DMG_PATH")
        MOUNT_POINT=$(echo "$ATTACH_OUTPUT" | /usr/bin/awk '/\\/Volumes\\// { print substr($0, index($0, "/Volumes/")); exit }')

        if [[ -z "$MOUNT_POINT" ]]; then
            exit 1
        fi

        SOURCE_APP="$MOUNT_POINT/$APP_NAME"
        if [[ ! -d "$SOURCE_APP" ]]; then
            /usr/bin/hdiutil detach "$MOUNT_POINT" || true
            /usr/bin/open "$DMG_PATH"
            exit 1
        fi

        /usr/bin/codesign --verify --deep --strict "$SOURCE_APP"

        TEMP_APP="${APP_PATH}.update"
        BACKUP_APP="${APP_PATH}.backup"
        /bin/rm -rf "$TEMP_APP" "$BACKUP_APP"
        /usr/bin/ditto "$SOURCE_APP" "$TEMP_APP"
        /usr/bin/codesign --verify --deep --strict "$TEMP_APP"

        /bin/mv "$APP_PATH" "$BACKUP_APP"
        if /bin/mv "$TEMP_APP" "$APP_PATH" && /usr/bin/codesign --verify --deep --strict "$APP_PATH"; then
            /bin/rm -rf "$BACKUP_APP"
        else
            /bin/rm -rf "$APP_PATH"
            /bin/mv "$BACKUP_APP" "$APP_PATH"
            /usr/bin/hdiutil detach "$MOUNT_POINT" || true
            exit 1
        fi

        /usr/bin/hdiutil detach "$MOUNT_POINT" || true
        /usr/bin/open "$APP_PATH"
        """

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexmonitor-update-\(UUID().uuidString).zsh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    private func sendUpdateAvailableNotification(version: String) {
        sendNotification(body: L10n.updateAvailableNotification(version: version))
    }

    private func sendUpdateReadyNotification(version: String) {
        sendNotification(body: L10n.updateReadyNotification(version: version))
    }

    private func sendNotification(body: String) {
        let content = UNMutableNotificationContent()
        content.title = "CodexMonitor"
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "github_update_\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[CodexMonitor] Update notification failed: \(error)")
            }
        }
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }

    var versionNumber: String {
        tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }

    var dmgAsset: GitHubAsset? {
        assets.first { asset in
            asset.name.lowercased().hasSuffix(".dmg")
        }
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

private enum UpdateError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case invalidDownload

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response"
        case .httpStatus(let status):
            return "HTTP \(status)"
        case .invalidDownload:
            return "Invalid download"
        }
    }
}

private enum VersionComparator {
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = components(lhs)
        let right = components(rhs)
        let count = max(left.count, right.count)

        for index in 0..<count {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func components(_ version: String) -> [Int] {
        let core = version.split(separator: "-").first ?? ""
        return core
            .split(separator: ".")
            .map { Int($0) ?? 0 }
    }
}
