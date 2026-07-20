import Foundation
import AppKit

struct CodexCloudModel: Codable, Hashable, Identifiable {
    let slug: String
    let displayName: String
    var id: String { slug }
}

enum CodexCloudModelService {
    struct Result: Sendable {
        enum Source: Sendable { case live, cache, unavailable }
        let models: [CodexCloudModel]
        let source: Source
    }

    static func fetch() async -> Result {
        await Task.detached(priority: .utility) { fetchBlocking() }.value
    }

    private static func fetchBlocking() -> Result {
        guard let executable = CodexQuotaActivationService.codexExecutableURL() else { return cachedResult() }
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let lock = NSLock(), initialized = DispatchSemaphore(value: 0), done = DispatchSemaphore(value: 0)
        var buffer = Data(), response: Data?
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            lock.lock(); defer { lock.unlock() }
            buffer.append(data)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<newline]
                buffer.removeSubrange(...newline)
                if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                   let id = object["id"] as? Int {
                    if id == 1 { initialized.signal() }
                    if id == 2 { response = Data(line); done.signal(); return }
                }
            }
        }
        do {
            try process.run()
            input.fileHandleForWriting.write(Data((#"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"codex-monitor","version":"0.7.3"},"capabilities":{}}}"# + "\n").utf8))
            guard initialized.wait(timeout: .now() + 30) == .success else { throw CocoaError(.coderReadCorrupt) }
            let request = #"{"method":"initialized","params":{}}"# + "\n" + #"{"id":2,"method":"model/list","params":{"includeHidden":false,"limit":100}}"# + "\n"
            input.fileHandleForWriting.write(Data(request.utf8))
            _ = done.wait(timeout: .now() + 30)
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            if process.isRunning { process.terminate() }
            return cachedResult()
        }
        output.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
        guard let response,
              let object = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
              let result = object["result"] as? [String: Any],
              let data = result["data"] as? [[String: Any]] else { return cachedResult() }
        let models: [CodexCloudModel] = data.compactMap { model -> CodexCloudModel? in
            guard model["hidden"] as? Bool != true,
                  let slug = model["model"] as? String,
                  let name = model["displayName"] as? String else { return nil }
            return CodexCloudModel(slug: slug, displayName: name)
        }
        return models.isEmpty ? cachedResult() : Result(models: models, source: .live)
    }

    private static func cachedResult() -> Result {
        struct Cache: Decodable { let models: [Model] }
        struct Model: Decodable {
            let slug: String; let displayName: String; let visibility: String?
            enum CodingKeys: String, CodingKey { case slug, visibility; case displayName = "display_name" }
        }
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/models_cache.json")
        guard let data = try? Data(contentsOf: url), let cache = try? JSONDecoder().decode(Cache.self, from: data) else {
            return Result(models: [], source: .unavailable)
        }
        let models = cache.models.filter { $0.visibility == nil || $0.visibility == "list" }.map { CodexCloudModel(slug: $0.slug, displayName: $0.displayName) }
        return Result(models: models, source: models.isEmpty ? .unavailable : .cache)
    }
}

enum FiveHourQuotaRefreshSettings {
    static func accountEnabled(_ id: UUID) -> Bool {
        let values = UserDefaults.standard.dictionary(forKey: PreferencesKeys.fiveHourRefreshAccountEnabled) as? [String: Bool]
        return values?[id.uuidString] ?? true
    }

    static func setAccountEnabled(_ enabled: Bool, id: UUID) {
        var values = UserDefaults.standard.dictionary(forKey: PreferencesKeys.fiveHourRefreshAccountEnabled) as? [String: Bool] ?? [:]
        values[id.uuidString] = enabled
        UserDefaults.standard.set(values, forKey: PreferencesKeys.fiveHourRefreshAccountEnabled)
    }

    static func time(for id: UUID?) -> Date {
        let values = UserDefaults.standard.dictionary(forKey: PreferencesKeys.fiveHourRefreshAccountTimes) as? [String: String]
        let value = id.flatMap { values?[$0.uuidString] } ?? UserDefaults.standard.string(forKey: PreferencesKeys.fiveHourRefreshTime) ?? "05:00"
        let parts = value.split(separator: ":").compactMap { Int($0) }
        return Calendar.current.date(bySettingHour: parts.first ?? 5, minute: parts.dropFirst().first ?? 0, second: 0, of: Date()) ?? Date()
    }

    static func setTime(_ date: Date, for id: UUID?) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let value = String(format: "%02d:%02d", components.hour ?? 5, components.minute ?? 0)
        if let id {
            var values = UserDefaults.standard.dictionary(forKey: PreferencesKeys.fiveHourRefreshAccountTimes) as? [String: String] ?? [:]
            values[id.uuidString] = value
            UserDefaults.standard.set(values, forKey: PreferencesKeys.fiveHourRefreshAccountTimes)
        } else { UserDefaults.standard.set(value, forKey: PreferencesKeys.fiveHourRefreshTime) }
    }

    static func selectedModel(from models: [CodexCloudModel]) -> String? {
        if let saved = UserDefaults.standard.string(forKey: PreferencesKeys.fiveHourRefreshModel), models.contains(where: { $0.slug == saved }) { return saved }
        return models.first(where: { $0.slug.localizedCaseInsensitiveContains("mini") })?.slug ?? models.last?.slug
    }
}

@MainActor
enum MacWakeScheduler {
    static func configure(for refreshTime: Date, enabled: Bool) -> Bool {
        let defaults = UserDefaults.standard
        let ownsSchedule = defaults.bool(forKey: PreferencesKeys.fiveHourRefreshOwnsWakeSchedule)
        if !enabled && !ownsSchedule { return true }
        if enabled && !ownsSchedule && hasExistingRepeatingSchedule() { return false }
        let command: String
        if enabled {
            let wakeTime = Calendar.current.date(byAdding: .minute, value: -2, to: refreshTime) ?? refreshTime
            let parts = Calendar.current.dateComponents([.hour, .minute], from: wakeTime)
            command = String(format: "/usr/bin/pmset repeat wakeorpoweron MTWRFSU %02d:%02d:00", parts.hour ?? 4, parts.minute ?? 58)
        } else {
            command = "/usr/bin/pmset repeat cancel"
        }
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        let succeeded = result != nil && error == nil
        if succeeded { defaults.set(enabled, forKey: PreferencesKeys.fiveHourRefreshOwnsWakeSchedule) }
        return succeeded
    }

    private static func hasExistingRepeatingSchedule() -> Bool {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "sched"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return true }
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.contains("Repeating power events:")
    }
}

@MainActor
final class FiveHourQuotaRefreshScheduler {
    private weak var accountStore: AccountStore?
    private var timer: Timer?
    init(accountStore: AccountStore) { self.accountStore = accountStore }

    func start() {
        timer?.invalidate()
        checkNow()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkNow() }
        }
    }
    func stop() { timer?.invalidate(); timer = nil }

    private func checkNow() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: PreferencesKeys.fiveHourRefreshEnabled), let accountStore else { return }
        let advanced = defaults.bool(forKey: PreferencesKeys.fiveHourRefreshAdvanced)
        let now = Date(), calendar = Calendar.current
        let dayKey = String(calendar.ordinality(of: .day, in: .era, for: now) ?? 0)
        var lastRuns = defaults.dictionary(forKey: PreferencesKeys.fiveHourRefreshLastRuns) as? [String: String] ?? [:]
        for account in accountStore.accounts where account.provider == .codex {
            if advanced && !FiveHourQuotaRefreshSettings.accountEnabled(account.id) { continue }
            let scheduled = FiveHourQuotaRefreshSettings.time(for: advanced ? account.id : nil)
            let target = calendar.date(bySettingHour: calendar.component(.hour, from: scheduled), minute: calendar.component(.minute, from: scheduled), second: 0, of: now) ?? now
            guard now >= target, now.timeIntervalSince(target) < 600, lastRuns[account.id.uuidString] != dayKey else { continue }
            lastRuns[account.id.uuidString] = dayKey
            defaults.set(lastRuns, forKey: PreferencesKeys.fiveHourRefreshLastRuns)
            let savedModel = defaults.string(forKey: PreferencesKeys.fiveHourRefreshModel)
            Task { await CodexQuotaActivationService.shared.refreshFiveHourQuota(account: account, model: savedModel) }
        }
    }
}
