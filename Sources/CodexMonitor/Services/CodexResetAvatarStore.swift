import AppKit
import Foundation

@MainActor
final class CodexResetAvatarStore: ObservableObject {
    @Published private(set) var image: NSImage?

    private let cacheURL: URL?
    private let refreshInterval: TimeInterval = 7 * 24 * 60 * 60
    private var isLoading = false

    init(fileManager: FileManager = .default) {
        let cacheDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("CodexMonitor/Images", isDirectory: true)
        cacheURL = cacheDirectory?.appendingPathComponent("tibo-avatar.jpg")
        image = cacheURL.flatMap { NSImage(contentsOf: $0) }
    }

    func preload(from remoteURL: URL) async {
        guard !isLoading else { return }
        guard image == nil || cacheNeedsRefresh else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            var request = URLRequest(url: remoteURL)
            request.timeoutInterval = 15
            request.cachePolicy = image == nil ? .returnCacheDataElseLoad : .reloadRevalidatingCacheData

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let downloadedImage = NSImage(data: data)
            else { return }

            image = downloadedImage
            persist(data)
        } catch {
            // A cached image remains usable when the refresh request fails.
            print("[CodexMonitor] Tibo avatar preload failed: \(error)")
        }
    }

    private var cacheNeedsRefresh: Bool {
        guard let cacheURL,
              let attributes = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
              let modifiedAt = attributes[.modificationDate] as? Date
        else { return true }
        return Date().timeIntervalSince(modifiedAt) >= refreshInterval
    }

    private func persist(_ data: Data) {
        guard let cacheURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            print("[CodexMonitor] Tibo avatar cache write failed: \(error)")
        }
    }
}
