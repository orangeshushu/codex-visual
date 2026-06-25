import AppKit
import Foundation

struct RateLimitEvent: Codable {
    let type: String
    let planType: String?
    let rateLimits: RateLimits

    enum CodingKeys: String, CodingKey {
        case type
        case planType = "plan_type"
        case rateLimits = "rate_limits"
    }
}

struct RateLimits: Codable {
    let allowed: Bool
    let limitReached: Bool
    let primary: QuotaWindow
    let secondary: QuotaWindow

    enum CodingKeys: String, CodingKey {
        case allowed
        case limitReached = "limit_reached"
        case primary
        case secondary
    }
}

struct QuotaWindow: Codable {
    let usedPercent: Int
    let windowMinutes: Int
    let resetAfterSeconds: Int?
    let resetAt: TimeInterval

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetAfterSeconds = "reset_after_seconds"
        case resetAt = "reset_at"
    }

    var remainingPercent: Int {
        min(100, max(0, 100 - usedPercent))
    }

    var resetDate: Date {
        Date(timeIntervalSince1970: resetAt)
    }
}

struct QuotaSnapshot {
    let event: RateLimitEvent
    let logDate: Date
    let readDate: Date
    let source: String
}

enum QuotaReadError: Error, LocalizedError {
    case missingDatabase(String)
    case sqliteFailed(String)
    case missingEvent
    case invalidLogRow
    case invalidJSON
    case cannotRunSQLite(String)

    var errorDescription: String? {
        switch self {
        case .missingDatabase(let path):
            return "未找到 Codex 日志数据库: \(path)"
        case .sqliteFailed(let message):
            return "读取 SQLite 失败: \(message)"
        case .missingEvent:
            return "还没有读到 codex.rate_limits 事件"
        case .invalidLogRow:
            return "日志行格式无法解析"
        case .invalidJSON:
            return "额度事件 JSON 无法解析"
        case .cannotRunSQLite(let message):
            return "无法运行 sqlite3: \(message)"
        }
    }
}

final class QuotaReader {
    private let sqlitePath = "/usr/bin/sqlite3"
    private let databasePath: String

    init(databasePath: String = NSHomeDirectory() + "/.codex/logs_2.sqlite") {
        self.databasePath = databasePath
    }

    func readLatest() throws -> QuotaSnapshot {
        if let liveSnapshot = try readFromLogs() {
            saveCache(snapshot: liveSnapshot)
            return liveSnapshot
        }

        if let cachedSnapshot = readCache() {
            return cachedSnapshot
        }

        throw QuotaReadError.missingEvent
    }

    private func readFromLogs() throws -> QuotaSnapshot? {
        guard FileManager.default.fileExists(atPath: databasePath) else {
            throw QuotaReadError.missingDatabase(databasePath)
        }

        let query = """
        select ts, feedback_log_body
        from logs
        where feedback_log_body like 'Received message {"type":"codex.rate_limits"%'
        order by ts desc, ts_nanos desc, id desc
        limit 50;
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: sqlitePath)
        process.arguments = ["-readonly", "-separator", "\t", databasePath, query]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw QuotaReadError.cannotRunSQLite(error.localizedDescription)
        }
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw QuotaReadError.sqliteFailed(errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, let timestamp = TimeInterval(parts[0]) else {
                continue
            }

            let body = String(parts[1])
            if let event = extractRateLimitEvent(from: body) {
                return QuotaSnapshot(
                    event: event,
                    logDate: Date(timeIntervalSince1970: timestamp),
                    readDate: Date(),
                    source: "Codex 日志"
                )
            }
        }

        return nil
    }

    private func extractRateLimitEvent(from body: String) -> RateLimitEvent? {
        let needles = ["{\"type\":\"codex.rate_limits\"", "{\\\"type\\\":\\\"codex.rate_limits\\\""]

        for needle in needles {
            var searchStart = body.startIndex
            while let range = body.range(of: needle, range: searchStart..<body.endIndex) {
                let rawCandidate = String(body[range.lowerBound...])
                let candidate: String
                if needle.contains("\\\"") {
                    candidate = rawCandidate
                        .replacingOccurrences(of: "\\\"", with: "\"")
                        .replacingOccurrences(of: "\\\\", with: "\\")
                } else {
                    candidate = rawCandidate
                }

                if let event = decodeJSONPrefix(candidate), event.type == "codex.rate_limits" {
                    return event
                }

                searchStart = body.index(after: range.lowerBound)
            }
        }

        return nil
    }

    private func decodeJSONPrefix(_ text: String) -> RateLimitEvent? {
        let decoder = JSONDecoder()
        var depth = 0
        var inString = false
        var isEscaped = false

        for (offset, character) in text.enumerated() {
            if inString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }

            if character == "\"" {
                inString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    let endIndex = text.index(text.startIndex, offsetBy: offset + 1)
                    let jsonText = String(text[..<endIndex])
                    guard let data = jsonText.data(using: .utf8) else {
                        return nil
                    }
                    return try? decoder.decode(RateLimitEvent.self, from: data)
                }
            }
        }

        return nil
    }

    private var cacheURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("CodexVisual/latest-rate-limit.json")
    }

    private func saveCache(snapshot: QuotaSnapshot) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let payload = CachedSnapshot(
                event: snapshot.event,
                logTimestamp: snapshot.logDate.timeIntervalSince1970,
                cachedTimestamp: Date().timeIntervalSince1970
            )
            let data = try encoder.encode(payload)
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            // Cache failures should not hide live quota data.
        }
    }

    private func readCache() -> QuotaSnapshot? {
        do {
            let data = try Data(contentsOf: cacheURL)
            let cached = try JSONDecoder().decode(CachedSnapshot.self, from: data)
            return QuotaSnapshot(
                event: cached.event,
                logDate: Date(timeIntervalSince1970: cached.logTimestamp),
                readDate: Date(timeIntervalSince1970: cached.cachedTimestamp),
                source: "本地缓存"
            )
        } catch {
            return nil
        }
    }
}

struct CachedSnapshot: Codable {
    let event: RateLimitEvent
    let logTimestamp: TimeInterval
    let cachedTimestamp: TimeInterval
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let reader = QuotaReader()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let fiveHourItem = NSMenuItem()
    private let fiveHourResetItem = NSMenuItem()
    private let sevenDayItem = NSMenuItem()
    private let sevenDayResetItem = NSMenuItem()
    private let orderItem = NSMenuItem()
    private let planItem = NSMenuItem()
    private let logTimeItem = NSMenuItem()
    private let readTimeItem = NSMenuItem()
    private let errorItem = NSMenuItem()
    private var timer: Timer?

    private lazy var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_US")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    private lazy var shortTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_US")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMenu()
        refresh(nil)
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh(nil)
            }
        }
    }

    private func configureMenu() {
        statusItem.button?.title = "Codex -- / --%"
        statusItem.button?.toolTip = "Codex 额度"

        for item in [orderItem, planItem, fiveHourItem, fiveHourResetItem, sevenDayItem, sevenDayResetItem, logTimeItem, readTimeItem, errorItem] {
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let refreshItem = NSMenuItem(title: "立即刷新", action: #selector(refresh(_:)), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出", action: #selector(quit(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func refresh(_ sender: Any?) {
        do {
            let snapshot = try reader.readLatest()
            update(snapshot)
        } catch {
            statusItem.button?.title = "Codex -- / --%"
            statusItem.button?.toolTip = error.localizedDescription
            orderItem.title = "显示顺序: 5小时 / 7天"
            errorItem.title = error.localizedDescription
            errorItem.isHidden = false
        }
    }

    private func update(_ snapshot: QuotaSnapshot) {
        let primary = snapshot.event.rateLimits.primary
        let secondary = snapshot.event.rateLimits.secondary
        let title = "Codex \(primary.remainingPercent) / \(secondary.remainingPercent)%"
        statusItem.button?.title = title
        statusItem.button?.toolTip = "5小时 / 7天: \(primary.remainingPercent)% / \(secondary.remainingPercent)%"

        let plan = snapshot.event.planType?.uppercased() ?? "未知"
        orderItem.title = "显示顺序: 5小时 / 7天"
        planItem.title = "计划: \(plan)"
        fiveHourItem.title = "5小时剩余: \(primary.remainingPercent)% (已用 \(primary.usedPercent)%)"
        fiveHourResetItem.title = "5小时刷新: \(timeFormatter.string(from: primary.resetDate))"
        sevenDayItem.title = "7天剩余: \(secondary.remainingPercent)% (已用 \(secondary.usedPercent)%)"
        sevenDayResetItem.title = "7天刷新: \(timeFormatter.string(from: secondary.resetDate))"
        logTimeItem.title = "数据来源: \(snapshot.source), \(timeFormatter.string(from: snapshot.logDate))"
        readTimeItem.title = "最后读取: \(shortTimeFormatter.string(from: snapshot.readDate))"
        errorItem.isHidden = true
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}

if CommandLine.arguments.contains("--print") {
    do {
        let snapshot = try QuotaReader().readLatest()
        let primary = snapshot.event.rateLimits.primary
        let secondary = snapshot.event.rateLimits.secondary
        print("5h_remaining=\(primary.remainingPercent)")
        print("7d_remaining=\(secondary.remainingPercent)")
        print("5h_reset=\(primary.resetDate)")
        print("7d_reset=\(secondary.resetDate)")
        print("source=\(snapshot.source)")
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(1)
    }
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
