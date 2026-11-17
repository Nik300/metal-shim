// Reading the driver's os_log output through /usr/bin/log (stream/show, ndjson), and parsing the
// "policy" and "stats" lines of the contract.
import Foundation

enum LogCategory: String, CaseIterable, Codable {
    case unimplemented, error, warning, general, policy, stats, compute, glass, swift, other

    init(raw: String) { self = LogCategory(rawValue: raw) ?? .other }

    var tag: String {   // fixed-width tags for the CLI
        switch self {
        case .unimplemented: "UNIMPL"
        case .error: "ERROR "
        case .warning: "WARN  "
        case .general: "INFO  "
        case .policy: "POLICY"
        case .stats: "STATS "
        case .compute: "COMPUT"
        case .glass: "GLASS "
        case .swift: "SWIFT "
        case .other: "OTHER "
        }
    }
}

/// The four user-facing filters of the Log view / `tsmtl log --filter`.
enum LogFilter: String, CaseIterable, Identifiable {
    case warning, unimplemented, error, general, compute, glass, swift
    var id: String { rawValue }

    var title: String {
        switch self {
        case .warning: "Avvisi"
        case .unimplemented: "Non implementate"
        case .error: "Errori"
        case .general: "Generali"
        case .compute: "Compute"
        case .glass: "Glass"
        case .swift: "Swift"
        }
    }

    var categories: [LogCategory] {
        switch self {
        case .warning: [.warning]
        case .unimplemented: [.unimplemented]
        case .error: [.error]
        case .general: [.general, .policy, .other]
        case .compute: [.compute]
        case .glass: [.glass]
        case .swift: [.swift]
        }
    }

    static func of(_ c: LogCategory) -> LogFilter? { allCases.first { $0.categories.contains(c) } }
}

struct LogEntry: Identifiable, Hashable {
    let id: Int
    let date: Date
    let category: LogCategory
    let level: String       // messageType: Default, Info, Error, Fault, Debug
    let process: String
    let pid: Int
    let message: String

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
    static let fullFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    var timeString: String { LogEntry.timeFormatter.string(from: date) }

    /// One compact, grep-friendly line (CLI output and "copy").
    var line: String { "\(LogEntry.fullFormatter.string(from: date)) \(category.tag) \(process)[\(pid)] \(message)" }

    var json: [String: Any] {
        ["time": LogEntry.isoFormatter.string(from: date), "category": category.rawValue, "level": level,
         "process": process, "pid": pid, "message": message]
    }
}

enum LogParser {
    private static let tsFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZ"
        return f
    }()
    nonisolated(unsafe) private static var counter = 0
    private static let lock = NSLock()

    static func nextId() -> Int {
        lock.lock(); defer { lock.unlock() }
        counter += 1
        return counter
    }

    /// Parses one ndjson line of `log stream/show --style ndjson`; nil for headers and summaries.
    static func parse(_ line: Substring) -> LogEntry? {
        guard line.first == "{", let data = line.data(using: .utf8),
              let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = d["eventMessage"] as? String, d["subsystem"] as? String == Paths.subsystem else { return nil }
        let ts = (d["timestamp"] as? String).flatMap { tsFormatter.date(from: $0) } ?? Date()
        let path = d["processImagePath"] as? String ?? "?"
        return LogEntry(id: nextId(), date: ts, category: LogCategory(raw: d["category"] as? String ?? ""),
                        level: d["messageType"] as? String ?? "", process: (path as NSString).lastPathComponent,
                        pid: (d["processID"] as? NSNumber)?.intValue ?? 0, message: message)
    }

    static func predicate(categories: [LogCategory]? = nil, excludingStats: Bool = false) -> String {
        var p = "subsystem == \"\(Paths.subsystem)\""
        if let categories, !categories.isEmpty {
            p += " AND (" + categories.map { "category == \"\($0.rawValue)\"" }.joined(separator: " OR ") + ")"
        } else if excludingStats {
            p += " AND category != \"stats\""
        }
        return p
    }
}

/// Runs /usr/bin/log and delivers complete lines on a background queue.
final class LogProcess {
    private let process = Process()
    private var buffer = Data()
    private let onLine: (Substring) -> Void

    init(arguments: [String], onLine: @escaping (Substring) -> Void, onExit: ((Int32) -> Void)? = nil) {
        self.onLine = onLine
        process.executableURL = URL(fileURLWithPath: Paths.logTool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let chunk = h.availableData
            guard let self else { return }
            if chunk.isEmpty { h.readabilityHandler = nil; self.flush(final: true); return }
            self.buffer.append(chunk)
            self.flush(final: false)
        }
        process.terminationHandler = { p in onExit?(p.terminationStatus) }
    }

    private func flush(final: Bool) {
        while let nl = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            onLine(Substring(String(decoding: lineData, as: UTF8.self)))
        }
        if final, !buffer.isEmpty {
            onLine(Substring(String(decoding: buffer, as: UTF8.self)))
            buffer.removeAll()
        }
    }

    private static let running = NSHashTable<LogProcess>.weakObjects()
    private static let runningLock = NSLock()

    func start() -> Bool {
        do { try process.run() } catch { return false }
        LogProcess.runningLock.lock(); LogProcess.running.add(self); LogProcess.runningLock.unlock()
        return true
    }

    func stop() { if process.isRunning { process.terminate() } }

    /// Terminates every child `log` process (app quit).
    static func stopAll() {
        runningLock.lock(); let all = running.allObjects; runningLock.unlock()
        all.forEach { $0.stop() }
    }

    var isRunning: Bool { process.isRunning }

    static func streamArgs(predicate: String, level: String = "info") -> [String] {
        ["stream", "--style", "ndjson", "--level", level, "--predicate", predicate]
    }

    static func showArgs(predicate: String, last: String, info: Bool = true) -> [String] {
        ["show", "--style", "ndjson", "--last", last] + (info ? ["--info"] : []) + ["--predicate", predicate]
    }
}

// MARK: - policy lines

struct PolicyLine: Identifiable, Codable {
    var id: String { appId }
    var on: Bool
    var appId: String
    var reason: String
    var name: String
    var path: String?
    var date: Date
    var pid: Int
    var process: String

    /// `policy: on|off id=<id> reason=<r> name=<name> path=<path>`; name and path may contain spaces.
    static func parse(_ e: LogEntry) -> PolicyLine? {
        let m = e.message
        guard m.hasPrefix("policy: ") else { return nil }
        let rest = m.dropFirst("policy: ".count)
        let on = rest.hasPrefix("on ")
        guard on || rest.hasPrefix("off ") else { return nil }
        func field(_ key: String, until next: String?) -> String? {
            guard let r = m.range(of: " \(key)=") else { return nil }
            let tail = m[r.upperBound...]
            if let next, let n = tail.range(of: " \(next)=") { return String(tail[..<n.lowerBound]) }
            return String(tail)
        }
        guard let id = field("id", until: "reason") else { return nil }
        let path = field("path", until: nil)
        return PolicyLine(on: on, appId: id, reason: field("reason", until: "name") ?? "?",
                          name: field("name", until: "path") ?? AppIdentity.fallbackName(for: id),
                          path: (path?.isEmpty ?? true) || path == "-" ? nil : path, date: e.date, pid: e.pid, process: e.process)
    }

    /// Latest line per app id, newest first.
    static func latestPerApp(_ lines: [PolicyLine]) -> [PolicyLine] {
        var latest: [String: PolicyLine] = [:]
        for l in lines where (latest[l.appId]?.date ?? .distantPast) <= l.date { latest[l.appId] = l }
        return latest.values.sorted { $0.date > $1.date }
    }

    /// Reads the policy history with `log show` (blocking; ~15 s for 7 days on this Mac).
    static func history(last: String) -> [PolicyLine] {
        let out = Shell.run(Paths.logTool, LogProcess.showArgs(predicate: LogParser.predicate(categories: [.policy]),
                                                               last: last, info: false))
        return out.split(separator: "\n").compactMap { LogParser.parse($0).flatMap(PolicyLine.parse) }
    }
}

// MARK: - stats lines

struct ShimStats: Codable {
    var pid: Int
    var app: String
    var name: String
    var fps: Double
    var draws: Double
    var passes: Double
    var cmdbufs: Double
    var gpuBusy: Double
    var bufKB: Double
    var texKB: Double
    var readbacks: Double
    var translations: Double
    var links: Double
    var fallbacks: Double
    var pipelines: Double
    var memMB: Double
    var drawableWaitMs: Double
    var dispatches: Double = 0      // TeraScale Compute (per second), OpenCL runs, compute pipelines that do not run
    var clRuns: Double = 0
    var computeRejected: Double = 0
    var mslHits: Double = 0         // shaders taken from precompiled bundles (total)

    /// Lenient decoding: missing numeric fields read as 0.
    static func parse(_ message: String) -> ShimStats? {
        guard let data = message.data(using: .utf8),
              let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = (d["pid"] as? NSNumber)?.intValue else { return nil }
        func n(_ k: String) -> Double { (d[k] as? NSNumber)?.doubleValue ?? 0 }
        let app = d["app"] as? String ?? "pid:\(pid)"
        return ShimStats(pid: pid, app: app, name: d["name"] as? String ?? AppIdentity.fallbackName(for: app),
                         fps: n("fps"), draws: n("draws"), passes: n("passes"), cmdbufs: n("cmdbufs"), gpuBusy: n("gpuBusy"),
                         bufKB: n("bufKB"), texKB: n("texKB"), readbacks: n("readbacks"), translations: n("translations"),
                         links: n("links"), fallbacks: n("fallbacks"), pipelines: n("pipelines"), memMB: n("memMB"),
                         drawableWaitMs: n("drawableWaitMs"), dispatches: n("dispatches"), clRuns: n("clRuns"),
                         computeRejected: n("computeRejected"), mslHits: n("mslHits"))
    }
}

/// One row per app id (helpers, GPU processes and extensions of the same app are summed).
struct AppStatsRow: Identifiable, Codable {
    var id: String { app }
    var app: String
    var name: String
    var pids: [Int]
    var fps: Double             // max over the app's processes (the one presenting)
    var draws: Double           // per second, summed
    var gpuBusy: Double         // summed, 0...1+ (fraction of a second)
    var uploadKBps: Double      // bufKB + texKB, summed
    var pipelines: Double
    var fallbacks: Double
    var memMB: Double
    var drawableWaitMs: Double
    var dispatches: Double = 0
    var clRuns: Double = 0
    var mslHits: Double = 0
}

final class StatsAggregator {
    private var perPid: [Int: (stats: ShimStats, seen: Date)] = [:]
    var maxAge: TimeInterval = 5

    func add(_ s: ShimStats, at date: Date = Date()) { perPid[s.pid] = (s, date) }

    func rows(now: Date = Date()) -> [AppStatsRow] {
        perPid = perPid.filter { now.timeIntervalSince($0.value.seen) < maxAge }
        var rows: [String: AppStatsRow] = [:]
        for (pid, v) in perPid {
            let s = v.stats
            var r = rows[s.app] ?? AppStatsRow(app: s.app, name: s.name, pids: [], fps: 0, draws: 0, gpuBusy: 0, uploadKBps: 0,
                                               pipelines: 0, fallbacks: 0, memMB: 0, drawableWaitMs: 0)
            r.pids.append(pid)
            r.fps = max(r.fps, s.fps)
            r.draws += s.draws
            r.gpuBusy += s.gpuBusy
            r.uploadKBps += s.bufKB + s.texKB
            r.pipelines += s.pipelines
            r.fallbacks += s.fallbacks
            r.memMB += s.memMB
            r.drawableWaitMs += s.drawableWaitMs
            r.dispatches += s.dispatches
            r.clRuns += s.clRuns
            r.mslHits += s.mslHits
            rows[s.app] = r
        }
        return rows.values.map { var r = $0; r.pids.sort(); return r }
            .sorted { $0.gpuBusy != $1.gpuBusy ? $0.gpuBusy > $1.gpuBusy : $0.name < $1.name }
    }
}
