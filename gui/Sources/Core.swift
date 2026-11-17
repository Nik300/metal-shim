// Shared model for the GUI and the CLI: paths, policy.plist, app identity and installation status.
// Everything here follows docs/FASE4-INTERFACCE.md.
import AppKit
import Foundation
import IOKit

enum Paths {
    static let defaultConfigDir = "/Library/GPUBundles/TeraScaleMTLDriver.config"
    static let driverBundle = "/Library/GPUBundles/TeraScaleMTLDriver.bundle"
    static let subsystem = "com.terascale.mtlshim"
    static let statsNotify = "com.terascale.mtlshim.stats"
    static let logTool = "/usr/bin/log"   // zsh has a `log` builtin: always use the full path

    static var configFromEnv: Bool { !(ProcessInfo.processInfo.environment["TSMTL_CONFIG_DIR"] ?? "").isEmpty }
    static var configDir: String {
        if let env = ProcessInfo.processInfo.environment["TSMTL_CONFIG_DIR"], !env.isEmpty {
            return (env as NSString).expandingTildeInPath
        }
        return defaultConfigDir
    }
    static var policyFile: String { configDir + "/policy.plist" }
    /// TeraScale Glass: the shaders tools/glassgen writes, and the component's state in WindowServer
    /// (kill switch, crash counter, status), shared by _windowserver and the user.
    static var glassSnippet: String { configDir + "/glass/glass.glsl" }
    static var glassInfo: String { configDir + "/glass/glass.plist" }
    static var glassState: String { configFromEnv ? configDir + "/TeraScaleGlass" : "/var/tmp/TeraScaleGlass" }
    static var glassKill: String { glassState + "/DISABLE" }
    static var glassStatus: String { glassState + "/status.plist" }
    /// TeraScale Swift: kill switch read by every process that loads the driver (no sudo needed to create it).
    static var swiftState: String { configFromEnv ? configDir + "/TeraScaleSwift" : "/var/tmp/TeraScaleSwift" }
    static var swiftKill: String { swiftState + "/DISABLE" }
}

// MARK: - Policy

enum Reason: String, Codable {
    case auto, list, critical, outside, nopolicy, injected
    // System.Compute (docs/PIANO-COMPUTE.md): the global switch, its default, the shim being off for the app.
    case global, off = "default", shimOff = "shim-off", env

    var label: String {
        switch self {
        case .auto: "automatico"
        case .list: "impostata a mano"
        case .critical: "processo di sistema critico"
        case .outside: "non coperta dall'automatico"
        case .nopolicy: "automatico, senza policy.plist"
        case .injected: "iniettato per una prova"
        case .global: "interruttore generale"
        case .off: "predefinito (acceso)"
        case .shimOff: "shim spento per l'app"
        case .env: "variabile TSMTL_COMPUTE"
        }
    }
}

struct Decision: Equatable {
    var on: Bool
    var reason: Reason
}

struct PolicyEntry: Identifiable, Equatable {
    var id: String
    var enabled: Bool?      // nil = no override, the entry follows AutoEnable
    var name: String?
    var path: String?

    var displayName: String { name ?? AppIdentity.fallbackName(for: id) }
}

/// One entry of Spoof.Apps (read by the kext). Entries without Enabled are ignored by the kext.
struct SpoofEntry: Identifiable, Equatable {
    var id: String
    var enabled: Bool?
    var match: String?
    var name: String?
    var path: String?

    var displayName: String { name ?? SpoofPolicy.autoRules.first { $0.id == id }?.name ?? AppIdentity.fallbackName(for: id) }
}

/// The "Spoof" dictionary of policy.plist (contract, section policy.plist).
struct SpoofPolicy: Equatable {
    static let defaultModel = "iMac19,1"
    static let autoRules: [(id: String, name: String, match: String)] = [
        ("com.google.Chrome", "Google Chrome", "/Google Chrome.app/"),
        ("com.apple.Safari", "Safari", "/Safari.app/"),
        ("com.apple.WebKit", "WebKit (processi web di Safari e delle app con viste web)", "/WebKit.framework/"),
    ]
    static func isAutoRule(_ id: String) -> Bool { autoRules.contains { $0.id == id } }

    var auto = true
    var model = SpoofPolicy.defaultModel
    var apps: [String: SpoofEntry] = [:]

    var manualEntries: [SpoofEntry] {
        apps.values.filter { !SpoofPolicy.isAutoRule($0.id) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// Mirrors the kext: explicit Enabled wins, then the auto rules when Auto is on.
    func decide(id: String) -> Decision {
        if let e = apps[id]?.enabled { return Decision(on: e, reason: .list) }
        if auto && SpoofPolicy.isAutoRule(id) { return Decision(on: true, reason: .auto) }
        return Decision(on: false, reason: .outside)
    }
}

/// System.Compute of policy.plist: TeraScale Compute (compute encoders on OpenCL or as GL passes), on by default.
/// Until driver 0.9.0 it was Experimental.Compute, off by default: still read when System.Compute is absent.
struct ComputePolicy: Equatable {
    var enabled = true
    var enabledSet = false          // Compute.Enabled is in the file (reason "global" rather than "default")
    var apps: [String: PolicyEntry] = [:]

    var sortedEntries: [PolicyEntry] {
        apps.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// Mirrors TSMtlComputeEnabled in the driver: shim off -> off, then the app's entry, then the global switch.
    func decide(id: String, shimOn: Bool) -> Decision {
        if !shimOn { return Decision(on: false, reason: .shimOff) }
        if let e = apps[id]?.enabled { return Decision(on: e, reason: .list) }
        return Decision(on: enabled, reason: enabledSet ? .global : .off)
    }
}

/// System.Glass of policy.plist: TeraScale Glass, Apple's glass shader inside Moraea's WindowServer compositor
/// (docs/PIANO-GLASS.md). Off by default. trialDeadline: System.Glass.Trial.Deadline, after which the component
/// goes back to Moraea's glass unless the trial is confirmed (tsmtl glass confirm removes it).
struct GlassPolicy: Equatable {
    var enabled = false
    var trialDeadline: Date?
}

/// System.Swift of policy.plist: TeraScale Swift, the Swift conformance accelerator the driver bundle starts in every
/// process that loads it (docs/OTTIMIZZAZIONE-SWIFT.md). On by default since driver 0.12.2. validate: check every fast answer against
/// the Swift runtime and log the differences (System.Swift.Validate).
struct SwiftPolicy: Equatable {
    var enabled = true
    var enabledSet = false
    var validate = false
    var apps: [String: PolicyEntry] = [:]

    var sortedEntries: [PolicyEntry] {
        apps.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// Mirrors TSMtlSwiftEnabled in the driver: the app's entry, critical processes off, then the global switch.
    /// The shim's own policy does not matter (the accelerator runs where the shim is off too).
    func decide(id: String) -> Decision {
        if let e = apps[id]?.enabled { return Decision(on: e, reason: .list) }
        if Policy.isCritical(id: id) { return Decision(on: false, reason: .critical) }
        return Decision(on: enabled, reason: enabledSet ? .global : .off)
    }
}

struct Policy: Equatable {
    var fromFile = false    // false: no policy.plist, the bundle reports reason "nopolicy"
    var autoEnable = true
    var apps: [String: PolicyEntry] = [:]
    var spoof = SpoofPolicy()
    var hasSpoof = false            // the file has a Spoof dictionary (written only when present or edited)
    var compute = ComputePolicy()
    var hasCompute = false          // the file has System.Compute or Experimental.Compute (written only when present or edited)
    var glass = GlassPolicy()
    var hasGlass = false            // the file has System.Glass (written only when present or edited)
    var swift = SwiftPolicy()
    var hasSwift = false            // the file has System.Swift (written only when present or edited)
    var raw: NSDictionary = [:]     // the file as read: unknown keys are written back untouched

    static let webKitGPU = "com.apple.WebKit.GPU"

    var sortedEntries: [PolicyEntry] {
        apps.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    static let appFolders = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications",
                             "/System/Volumes/Preboot/Cryptexes/App/System/Applications"]
    static let criticalProcesses: Set<String> = ["WindowServer", "loginwindow", "Dock", "SystemUIServer", "ControlCenter",
                                                 "NotificationCenter", "WallpaperAgent", "WindowManager"]
    static let criticalIds: Set<String> = ["com.apple.loginwindow", "com.apple.dock", "com.apple.systemuiserver",
                                           "com.apple.controlcenter", "com.apple.notificationcenterui",
                                           "com.apple.wallpaper.agent", "com.apple.WindowManager", "proc:WindowServer"]

    static func isCritical(id: String) -> Bool {
        criticalIds.contains(id) || (id.hasPrefix("proc:") && criticalProcesses.contains(String(id.dropFirst(5))))
    }

    static func inAppFolder(_ path: String) -> Bool {
        appFolders.contains { path.hasPrefix($0 + "/") }
    }

    /// Mirrors the bundle's decision (contract, "Decisione del bundle"). `path` is the outermost .app, if known.
    func decide(id: String, path: String?) -> Decision {
        if Policy.isCritical(id: id) { return Decision(on: false, reason: .critical) }
        if let enabled = apps[id]?.enabled { return Decision(on: enabled, reason: .list) }
        let p = path ?? apps[id]?.path ?? AppIdentity.locate(id: id)
        if autoEnable, id == Policy.webKitGPU || (p.map(Policy.inAppFolder) ?? false) {
            return Decision(on: true, reason: fromFile ? .auto : .nopolicy)
        }
        return Decision(on: false, reason: .outside)
    }
}

enum PolicyStore {
    enum Failure: LocalizedError {
        case unreadable(String), write(String)
        var errorDescription: String? {
            switch self {
            case .unreadable(let s): "policy.plist illeggibile: \(s)"
            case .write(let s): s
            }
        }
    }

    /// Missing file = defaults (AutoEnable true, no apps), as the bundle does. An unreadable file is reported.
    static func load() -> (Policy, error: String?) {
        let path = Paths.policyFile
        guard FileManager.default.fileExists(atPath: path) else { return (Policy(), nil) }
        guard let data = FileManager.default.contents(atPath: path),
              let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return (Policy(), "il file \(path) esiste ma non si può leggere: lo shim usa i valori predefiniti")
        }
        var policy = Policy()
        policy.fromFile = true
        policy.raw = root as NSDictionary
        policy.autoEnable = (root["AutoEnable"] as? Bool) ?? true
        for (id, value) in (root["Apps"] as? [String: Any]) ?? [:] {
            guard let d = value as? [String: Any] else { continue }
            policy.apps[id] = PolicyEntry(id: id, enabled: d["Enabled"] as? Bool, name: d["Name"] as? String, path: d["Path"] as? String)
        }
        if let sp = root["Spoof"] as? [String: Any] {
            policy.hasSpoof = true
            policy.spoof.auto = (sp["Auto"] as? Bool) ?? true
            if let m = sp["Model"] as? String, !m.isEmpty { policy.spoof.model = m }
            for (id, value) in (sp["Apps"] as? [String: Any]) ?? [:] {
                guard let d = value as? [String: Any] else { continue }
                policy.spoof.apps[id] = SpoofEntry(id: id, enabled: d["Enabled"] as? Bool, match: d["Match"] as? String,
                                                   name: d["Name"] as? String, path: d["Path"] as? String)
            }
        }
        let legacyCompute = (root["Experimental"] as? [String: Any])?["Compute"] as? [String: Any]
        if let c = (root["System"] as? [String: Any])?["Compute"] as? [String: Any] ?? legacyCompute {
            policy.hasCompute = true
            if let e = c["Enabled"] as? Bool { policy.compute.enabled = e; policy.compute.enabledSet = true }
            for (id, value) in (c["Apps"] as? [String: Any]) ?? [:] {
                guard let d = value as? [String: Any] else { continue }
                policy.compute.apps[id] = PolicyEntry(id: id, enabled: d["Enabled"] as? Bool, name: d["Name"] as? String, path: d["Path"] as? String)
            }
        }
        if let sys = root["System"] as? [String: Any], let g = sys["Glass"] as? [String: Any] {
            policy.hasGlass = true
            policy.glass.enabled = (g["Enabled"] as? Bool) ?? false
            // Unix seconds: the kext parses this file with OSUnserializeXML, which has no <date> (a date makes the
            // whole file unreadable to it). A <date> written by an older app is still accepted here.
            let d = (g["Trial"] as? [String: Any])?["Deadline"]
            policy.glass.trialDeadline = (d as? Int).map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? d as? Date
        }
        if let sys = root["System"] as? [String: Any], let w = sys["Swift"] as? [String: Any] {
            policy.hasSwift = true
            if let e = w["Enabled"] as? Bool { policy.swift.enabled = e; policy.swift.enabledSet = true }
            policy.swift.validate = (w["Validate"] as? Bool) ?? false
            for (id, value) in (w["Apps"] as? [String: Any]) ?? [:] {
                guard let d = value as? [String: Any] else { continue }
                policy.swift.apps[id] = PolicyEntry(id: id, enabled: d["Enabled"] as? Bool, name: d["Name"] as? String, path: d["Path"] as? String)
            }
        }
        return (policy, nil)
    }

    /// Sets or removes string/bool fields of a dictionary entry, keeping any other key.
    private static func merge(_ base: Any?, _ fields: [String: Any?]) -> [String: Any] {
        var d = base as? [String: Any] ?? [:]
        for (k, v) in fields {
            if let v, !((v as? String)?.isEmpty ?? false) { d[k] = v } else { d[k] = nil }
        }
        return d
    }

    /// Writes the contract schema as XML (the kext parses it with OSUnserializeXML), atomically
    /// (temp file in the same directory + rename). Keys this app does not know are kept as they were.
    static func save(_ policy: Policy) throws {
        let dir = Paths.configDir
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: dir, isDirectory: &isDir) || !isDir.boolValue {
            throw Failure.write("la cartella di configurazione \(dir) non esiste: lo shim non è installato")
        }
        var root = policy.raw as? [String: Any] ?? [:]
        let rawApps = root["Apps"] as? [String: Any] ?? [:]
        var apps: [String: Any] = [:]
        for e in policy.apps.values {
            apps[e.id] = merge(rawApps[e.id], ["Enabled": e.enabled, "Name": e.name, "Path": e.path])
        }
        root["Version"] = 1
        root["AutoEnable"] = policy.autoEnable
        root["Apps"] = apps
        if policy.hasSpoof || policy.spoof != SpoofPolicy() {
            var sp = root["Spoof"] as? [String: Any] ?? [:]
            let rawSpoofApps = sp["Apps"] as? [String: Any] ?? [:]
            var spApps: [String: Any] = [:]
            for e in policy.spoof.apps.values {
                spApps[e.id] = merge(rawSpoofApps[e.id], ["Enabled": e.enabled, "Match": e.match, "Name": e.name, "Path": e.path])
            }
            sp["Auto"] = policy.spoof.auto
            sp["Model"] = policy.spoof.model
            sp["Apps"] = spApps
            root["Spoof"] = sp
        }
        var sys = root["System"] as? [String: Any] ?? [:]
        if policy.hasCompute || policy.compute != ComputePolicy() {
            var ex = root["Experimental"] as? [String: Any] ?? [:]
            let legacy = ex["Compute"] as? [String: Any]
            var c = sys["Compute"] as? [String: Any] ?? legacy ?? [:]
            let rawComputeApps = c["Apps"] as? [String: Any] ?? [:]
            var cApps: [String: Any] = [:]
            for e in policy.compute.apps.values {
                cApps[e.id] = merge(rawComputeApps[e.id], ["Enabled": e.enabled, "Name": e.name, "Path": e.path])
            }
            c["Enabled"] = policy.compute.enabledSet ? policy.compute.enabled : nil
            c["Apps"] = cApps
            sys["Compute"] = c
            root["System"] = sys
            // Drivers up to 0.9.0 read only Experimental.Compute (update.sh installs the driver alone): a file that
            // still has it gets the same content, so an older driver keeps the user's settings. Drop it after 0.10.
            if legacy != nil { ex["Compute"] = c; root["Experimental"] = ex }
        }
        if policy.hasGlass || policy.glass != GlassPolicy() {
            var g = sys["Glass"] as? [String: Any] ?? [:]
            g["Enabled"] = policy.glass.enabled
            g["Trial"] = policy.glass.trialDeadline.map { ["Deadline": Int($0.timeIntervalSince1970)] }
            sys["Glass"] = g
            root["System"] = sys
        }
        if policy.hasSwift || policy.swift != SwiftPolicy() {
            var w = sys["Swift"] as? [String: Any] ?? [:]
            let rawSwiftApps = w["Apps"] as? [String: Any] ?? [:]
            var wApps: [String: Any] = [:]
            for e in policy.swift.apps.values {
                wApps[e.id] = merge(rawSwiftApps[e.id], ["Enabled": e.enabled, "Name": e.name, "Path": e.path])
            }
            w["Enabled"] = policy.swift.enabledSet ? policy.swift.enabled : nil
            w["Validate"] = policy.swift.validate ? true : nil
            w["Apps"] = wApps
            sys["Swift"] = w
            root["System"] = sys
        }
        let data: Data
        do { data = try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0) }
        catch { throw Failure.write("serializzazione fallita: \(error.localizedDescription)") }
        let tmp = dir + "/.policy.plist.\(getpid()).tmp"
        guard FileManager.default.createFile(atPath: tmp, contents: data, attributes: [.posixPermissions: 0o644]) else {
            throw Failure.write("impossibile scrivere in \(dir) (\(String(cString: strerror(errno))))")
        }
        if rename(tmp, Paths.policyFile) != 0 {
            let err = String(cString: strerror(errno))
            unlink(tmp)
            throw Failure.write("impossibile sostituire policy.plist (\(err))")
        }
    }
}

// MARK: - TeraScale Glass

/// TeraScale Glass as policy, files and the component in WindowServer report it (docs/PIANO-GLASS.md, "Contratto").
struct GlassReport {
    var policy = GlassPolicy()
    var snippetPresent = false
    var snippetInfo: [String: Any] = [:]    // glass.plist written by tools/glassgen
    var killSwitch = false
    var killReason: String?
    var status: [String: Any] = [:]          // status.plist written by the component
    var componentRunning = false             // status.plist comes from the WindowServer that is running now
    var kextVersion: String?
    var recentCrashes: [String] = []         // WindowServer reports of the last 24 hours

    /// Kext 1.2.0 or later lets the driver into WindowServer (only while System.Glass.Enabled is set).
    var kextReady: Bool { kextVersion.map { $0.compare("1.2.0", options: .numeric) != .orderedAscending } ?? false }
    var trialActive: Bool { policy.trialDeadline.map { $0 > Date() } ?? false }
    var trialExpired: Bool { policy.trialDeadline.map { $0 <= Date() } ?? false }
    var active: Bool { componentRunning && (status["State"] as? String) == "active" }
    var replaced: Int { status["Replaced"] as? Int ?? 0 }

    static func probe(kextVersion: String?) -> GlassReport {
        var r = GlassReport()
        r.policy = PolicyStore.load().0.glass
        r.snippetPresent = FileManager.default.fileExists(atPath: Paths.glassSnippet)
        r.snippetInfo = NSDictionary(contentsOfFile: Paths.glassInfo) as? [String: Any] ?? [:]
        r.killSwitch = FileManager.default.fileExists(atPath: Paths.glassKill)
        if r.killSwitch, let text = try? String(contentsOfFile: Paths.glassKill, encoding: .utf8), !text.isEmpty {
            r.killReason = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        r.status = NSDictionary(contentsOfFile: Paths.glassStatus) as? [String: Any] ?? [:]
        if let pid = r.status["PID"] as? Int32 ?? (r.status["PID"] as? Int).map(Int32.init) {
            var info = kinfo_proc(), size = MemoryLayout<kinfo_proc>.stride
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
            if sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 {
                let name = withUnsafePointer(to: &info.kp_proc.p_comm) { $0.withMemoryRebound(to: CChar.self, capacity: 17) { String(cString: $0) } }
                r.componentRunning = name == "WindowServer"
            }
        }
        r.kextVersion = kextVersion
        let dir = "/Library/Logs/DiagnosticReports"
        let day = Date().addingTimeInterval(-86400)
        for f in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] where f.hasPrefix("WindowServer") {
            let m = (try? FileManager.default.attributesOfItem(atPath: dir + "/" + f))?[.modificationDate] as? Date
            if let m, m > day { r.recentCrashes.append(f) }
        }
        r.recentCrashes.sort()
        return r
    }

    /// One line for the CLI and the app's subtitle.
    var summary: String {
        if killSwitch { return "spento dall'interruttore\(killReason.map { " (\($0))" } ?? "")" }
        if !policy.enabled { return "spento (vetro di Moraea)" }
        if trialExpired { return "prova scaduta: vetro di Moraea" }
        if active { return "attivo in WindowServer: \(replaced) programmi con il vetro di Apple" + (trialActive ? " (in prova)" : "") }
        if componentRunning { return "caricato in WindowServer, ma: \(status["Detail"] as? String ?? status["State"] as? String ?? "?")" }
        if !kextReady { return "acceso nella policy, ma serve il kext 1.2 (zsh system/glass.sh kext, poi riavvio)" }
        if !snippetPresent { return "acceso nella policy, ma manca glass.glsl (zsh system/glass.sh prepare)" }
        return "acceso nella policy: vale dal prossimo avvio di WindowServer (riavvia il Mac: il logout non riavvia WindowServer)"
    }
}

/// The TeraScale Glass commands of the CLI and of the "Sistema" section. Turning off is immediate (kill switch, the
/// component checks it every second); turning on takes effect when WindowServer next starts.
enum GlassControl {
    static func modify(_ change: (inout GlassPolicy) -> Void) throws {
        var (policy, err) = PolicyStore.load()
        if let err { throw PolicyStore.Failure.write(err + " (non lo sovrascrivo)") }
        policy.hasGlass = true
        change(&policy.glass)
        try PolicyStore.save(policy)
    }

    static func on() throws {
        try modify { $0.enabled = true; $0.trialDeadline = nil }
        try? FileManager.default.removeItem(atPath: Paths.glassKill)
    }

    static func trial(minutes: Int) throws -> Date {
        let deadline = Date().addingTimeInterval(TimeInterval(minutes * 60))
        try modify { $0.enabled = true; $0.trialDeadline = deadline }
        try? FileManager.default.removeItem(atPath: Paths.glassKill)
        try? FileManager.default.removeItem(atPath: Paths.glassState + "/starts")
        return deadline
    }

    static func off(reason: String) throws {
        try? FileManager.default.createDirectory(atPath: Paths.glassState, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: Paths.glassKill, contents: Data((reason + "\n").utf8))
        try modify { $0.enabled = false; $0.trialDeadline = nil }
    }
}

// MARK: - App identity

struct AppIdentity: Equatable {
    var id: String
    var name: String
    var path: String?

    static func fallbackName(for id: String) -> String {
        id.hasPrefix("proc:") ? String(id.dropFirst(5)) : (id.split(separator: ".").last.map(String.init) ?? id)
    }

    static func displayName(ofApp path: String) -> String {
        let n = FileManager.default.displayName(atPath: path)
        return n.hasSuffix(".app") ? String(n.dropLast(4)) : n
    }

    /// Reads CFBundleIdentifier and the (localized) name of a .app bundle.
    static func fromApp(at url: URL) -> AppIdentity? {
        guard url.pathExtension == "app",
              let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
              let id = info["CFBundleIdentifier"] as? String, !id.isEmpty else { return nil }
        return AppIdentity(id: id, name: displayName(ofApp: url.path), path: url.path)
    }

    static func locate(id: String) -> String? {
        if id.hasPrefix("proc:") { return nil }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.path
    }

    /// CLI argument: a path to a .app, a bundle id or proc:<name>.
    static func resolve(_ arg: String) -> AppIdentity? {
        let expanded = (arg as NSString).expandingTildeInPath
        if arg.contains("/") || arg.hasSuffix(".app") {
            let url = URL(fileURLWithPath: expanded).standardizedFileURL
            return fromApp(at: url)
        }
        if let path = locate(id: arg) { return AppIdentity(id: arg, name: displayName(ofApp: path), path: path) }
        return AppIdentity(id: arg, name: fallbackName(for: arg), path: nil)
    }

    static func icon(path: String?) -> NSImage {
        if let path, FileManager.default.fileExists(atPath: path) { return NSWorkspace.shared.icon(forFile: path) }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }
}

// MARK: - IORegistry helpers

enum IOReg {
    static func service(_ className: String) -> io_service_t {
        let s = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(className))
        if s != 0 { return s }
        // Matching only finds registered services; Lilu plugins (TSMetalEnabler) never call registerService,
        // so walk the IOService plane as ioreg does.
        var it: io_iterator_t = 0
        guard IORegistryCreateIterator(kIOMainPortDefault, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &it) == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(it) }
        while case let e = IOIteratorNext(it), e != 0 {
            if IOObjectConformsTo(e, className) != 0 { return e }
            IOObjectRelease(e)
        }
        return 0
    }

    static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    static func search(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntrySearchCFProperty(entry, kIOServicePlane, key as CFString, kCFAllocatorDefault,
                                        IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents))
    }

    static func string(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let d = value as? Data {
            return String(decoding: d.prefix { $0 != 0 }, as: UTF8.self)
        }
        return nil
    }

    static func className(_ entry: io_registry_entry_t) -> String {
        var buf = [CChar](repeating: 0, count: 128)
        IOObjectGetClass(entry, &buf)
        return String(cString: buf)
    }

    /// The Radeon's IOAccelerator (AMDTurksGraphicsAccelerator); falls back to the first AMD accelerator.
    static func radeonAccelerator() -> io_registry_entry_t {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &it) == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(it) }
        var best: io_registry_entry_t = 0
        while case let s = IOIteratorNext(it), s != 0 {
            let cls = className(s)
            if cls == "AMDTurksGraphicsAccelerator" {
                if best != 0 { IOObjectRelease(best) }
                best = s
                break
            }
            if best == 0 && cls.hasPrefix("AMD") { best = s } else { IOObjectRelease(s) }
        }
        return best
    }
}

// MARK: - Installation status

struct StatusReport: Codable {
    var kextLoaded = false
    var kextVersion: String?
    var kextAcceleratorPatched: Bool?
    var lvHook: String?            // "installed", or why the library-validation exception is missing
    var lvAllowed: Int?
    var lvRefused: Int?
    var lvLastProcess: String?
    var spoofState: String?
    var spoofCount: Int?
    var spoofLastProcess: String?

    var gpuFound = false
    var gpuModel: String?
    var vramTotalMB: Int?
    var acceleratorClass: String?
    var metalPluginName: String?
    var metalPluginClassName: String?

    var bundlePath = Paths.driverBundle
    var bundleInstalled = false
    var bundleId: String?
    var bundleVersion: String?
    var bundleCDHash: String?

    var configDir = Paths.configDir
    var configFromEnv = Paths.configFromEnv
    var configDirExists = false
    var configDirWritable = false
    var policyExists = false
    var policyError: String?
    var autoEnable = true
    var policyEntries = 0

    var bootArgs: String?
    var bootOff = false
    var bootNoLV = false
    var bootNoSpoof = false
    var spoofAuto = true
    var spoofModel = SpoofPolicy.defaultModel
    var spoofEntries = 0

    var spoofActive: Bool { kextLoaded && spoofState == "installed" }

    var pluginActive: Bool { metalPluginName == "TeraScaleMTLDriver" }
    var installed: Bool { kextLoaded && bundleInstalled && pluginActive }

    /// `withCodesign` runs `codesign -dvvv` on the bundle (slow-ish, done off the main thread by the GUI).
    static func probe(withCodesign: Bool) -> StatusReport {
        var r = StatusReport()
        let kext = IOReg.service("TSMetalEnabler")
        if kext != 0 {
            r.kextLoaded = true
            r.kextVersion = IOReg.string(IOReg.property(kext, "TSVersion"))
            r.kextAcceleratorPatched = IOReg.property(kext, "TSAcceleratorPatched") as? Bool
            r.lvHook = IOReg.string(IOReg.property(kext, "TSLVHook"))
            r.lvAllowed = (IOReg.property(kext, "TSLVAllowed") as? NSNumber)?.intValue
            r.lvRefused = (IOReg.property(kext, "TSLVRefused") as? NSNumber)?.intValue
            r.lvLastProcess = IOReg.string(IOReg.property(kext, "TSLVLastProcess"))
            r.spoofState = IOReg.string(IOReg.property(kext, "TSSpoof"))
            r.spoofCount = (IOReg.property(kext, "TSSpoofCount") as? NSNumber)?.intValue
            r.spoofLastProcess = IOReg.string(IOReg.property(kext, "TSSpoofLastProcess"))
            IOObjectRelease(kext)
        }
        let accel = IOReg.radeonAccelerator()
        if accel != 0 {
            r.gpuFound = true
            r.acceleratorClass = IOReg.className(accel)
            r.gpuModel = IOReg.string(IOReg.search(accel, "model"))
            r.vramTotalMB = (IOReg.search(accel, "VRAM,totalMB") as? NSNumber)?.intValue
            r.metalPluginName = IOReg.string(IOReg.property(accel, "MetalPluginName"))
            r.metalPluginClassName = IOReg.string(IOReg.property(accel, "MetalPluginClassName"))
            IOObjectRelease(accel)
        }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: r.bundlePath, isDirectory: &isDir), isDir.boolValue {
            r.bundleInstalled = true
            let info = NSDictionary(contentsOfFile: r.bundlePath + "/Contents/Info.plist")
            r.bundleId = info?["CFBundleIdentifier"] as? String
            let short = info?["CFBundleShortVersionString"] as? String, build = info?["CFBundleVersion"] as? String
            r.bundleVersion = [short, build.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ").nilIfEmpty
            if withCodesign { r.bundleCDHash = codesignCDHash(r.bundlePath) }
        }
        isDir = false
        r.configDirExists = FileManager.default.fileExists(atPath: r.configDir, isDirectory: &isDir) && isDir.boolValue
        r.configDirWritable = r.configDirExists && access(r.configDir, W_OK) == 0
        r.policyExists = FileManager.default.fileExists(atPath: Paths.policyFile)
        let (policy, err) = PolicyStore.load()
        r.policyError = err
        r.autoEnable = policy.autoEnable
        r.policyEntries = policy.apps.count
        r.spoofAuto = policy.spoof.auto
        r.spoofModel = policy.spoof.model
        r.spoofEntries = policy.spoof.apps.count
        let options = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/options")
        if options != 0 {
            r.bootArgs = IOReg.string(IOReg.property(options, "boot-args"))
            IOObjectRelease(options)
        }
        let args = (r.bootArgs ?? "").split(separator: " ").map(String.init)
        r.bootOff = args.contains("-tsmtloff")
        r.bootNoLV = args.contains("-tsmtlnolv")
        r.bootNoSpoof = args.contains("-tsmtlnospoof")
        return r
    }

    static func codesignCDHash(_ path: String) -> String? {
        let out = Shell.run("/usr/bin/codesign", ["-dvvv", path])
        for line in out.split(separator: "\n") where line.hasPrefix("CDHash=") {
            return String(line.dropFirst(7))
        }
        return out.contains("not signed") ? "non firmato" : nil
    }
}

enum Shell {
    /// Runs a tool and returns stdout+stderr (used only for codesign and log show).
    static func run(_ tool: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

enum Fmt {
    static func mb(_ bytes: Int64?) -> String {
        guard let bytes else { return "–" }
        return String(format: "%.0f MB", Double(bytes) / 1_048_576)
    }
    static func rate(_ v: Double?, digits: Int = 0) -> String {
        guard let v else { return "–" }
        return String(format: "%.\(digits)f", v)
    }
    static func pct(_ v: Double?) -> String {
        guard let v else { return "–" }
        return String(format: "%.0f %%", v * 100)
    }
}
