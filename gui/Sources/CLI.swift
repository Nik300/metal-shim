// Command-line mode of the TeraScaleMetal executable (called by the `tsmtl` wrapper).
// Human output is Italian and compact (one fact per line, key=value where useful) so it can be grepped;
// --json gives machine-readable output.
import Foundation

enum CLI {
    static let commands: Set<String> = ["status", "stats", "log", "apps", "enable", "disable", "reset", "remove", "auto", "spoof", "compute", "glass", "swift",
                                        "help", "-h", "--help", "version", "--version"]

    static func isCLI(_ args: [String]) -> Bool {
        // Any first argument that is not a launch option is a CLI command (unknown ones get an error, not a window).
        guard let first = args.first else { return false }
        return commands.contains(first) || (!first.hasPrefix("-") && first != "gui")
    }

    static func run(_ args: [String]) -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        var rest = Array(args.dropFirst())
        switch args[0] {
        case "status": return status(json: take(&rest, "--json"))
        case "stats": return stats(&rest)
        case "log": return log(&rest)
        case "apps": return apps(&rest)
        case "enable": return setApp(rest, enabled: true)
        case "disable": return setApp(rest, enabled: false)
        case "reset": return resetApp(rest, remove: false)
        case "remove": return resetApp(rest, remove: true)
        case "auto": return auto(rest)
        case "spoof": return spoof(&rest)
        case "compute": return compute(&rest)
        case "glass": return glass(&rest)
        case "swift": return swift(&rest)
        case "version", "--version": print("tsmtl \(appVersion)"); return 0
        case "help", "-h", "--help": help(); return 0
        default: return fail("comando sconosciuto: \(args[0]) (vedi tsmtl help)")
        }
    }

    static var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev" }

    static func help() {
        print("""
        tsmtl – controllo dello shim Metal TeraScale (Metal su OpenGL 4.1 per la Radeon HD 6750M)

        Uso:
          tsmtl                     apre l'app TeraScale Metal (anche: tsmtl gui)
          tsmtl status [--json]     kext, plugin Metal sulla GPU, bundle, cartella di configurazione
          tsmtl stats [--json] [--watch [s]] [--count n]
                                    statistiche GPU + statistiche per app dello shim (circa 2 s di raccolta;
                                    --watch ripete ogni s secondi, predefinito 2, fino a Ctrl-C o n volte)
          tsmtl log [-f|--follow] [--last 1h] [--filter unimplemented,error,warning,general,compute] [--app nome|id] [--json]
                                    messaggi del driver (storico con log show; -f segue in diretta)
          tsmtl apps [--json] [--last 1d]
                                    policy per app, stato effettivo e app viste di recente nei log
          tsmtl enable  <id app | percorso .app | proc:nome>   attiva lo shim per l'app
          tsmtl disable <id app | percorso .app | proc:nome>   disattiva lo shim per l'app
          tsmtl reset   <...>       toglie l'impostazione manuale (l'app torna automatica, resta in elenco)
          tsmtl remove  <...>       toglie l'app dall'elenco
          tsmtl auto on|off         attiva/disattiva lo shim automatico su tutte le app in Applicazioni
          tsmtl spoof [--json]      spoofing del modello (kext 1.1): regole automatiche, elenco, stato effettivo
          tsmtl spoof enable|disable|reset|remove <id app | percorso .app>
          tsmtl spoof auto on|off   spoofing automatico su Safari, Chrome e processi WebKit
          tsmtl spoof model <nome>  modello mostrato (predefinito \(SpoofPolicy.defaultModel))
          tsmtl compute [--json]    TeraScale Compute (Sistema): compute Metal su OpenCL, acceso salvo eccezioni
          tsmtl compute on|off      attiva/disattiva il compute per tutte le app in cui lo shim è attivo
          tsmtl compute enable|disable|reset|remove <id app | percorso .app | proc:nome>
          tsmtl glass [--json]      TeraScale Glass: il vetro di Apple nel compositore di WindowServer (Moraea)
          tsmtl glass on|off        acceso (dal prossimo avvio di WindowServer) / spento subito, senza riavvio
          tsmtl glass trial [min]   acceso in prova: dopo min minuti (predefinito 15) torna da solo il vetro di Moraea
          tsmtl glass confirm       tiene acceso il vetro provato (toglie la scadenza)
          tsmtl swift [--json]      TeraScale Swift: risposte rapide del runtime Swift (Impostazioni, app SwiftUI), acceso salvo eccezioni
          tsmtl swift on|off        acceso/spento per tutti i processi che caricano il driver (salvo le eccezioni)
          tsmtl swift enable|disable|reset|remove <id app | percorso .app | proc:nome>
          tsmtl swift validate on|off  confronta ogni risposta rapida col runtime e registra le differenze
          tsmtl swift kill|unkill   interruttore d'emergenza (senza sudo) per i processi avviati da ora
          tsmtl swift stats [--last 1h] [--json]  contatori per processo dal log
          tsmtl help

        Cartella di configurazione: \(Paths.configDir)\(Paths.configFromEnv ? " (da TSMTL_CONFIG_DIR)" : "")
        Le modifiche alla policy valgono per le app avviate dopo.
        """)
    }

    // MARK: argument helpers

    static func take(_ args: inout [String], _ names: String...) -> Bool {
        guard let i = args.firstIndex(where: { names.contains($0) }) else { return false }
        args.remove(at: i)
        return true
    }

    static func value(_ args: inout [String], _ names: String...) -> String? {
        guard let i = args.firstIndex(where: { names.contains($0) }), i + 1 < args.count else { return nil }
        let v = args[i + 1]
        args.removeSubrange(i...(i + 1))
        return v
    }

    static func printJSON(_ obj: Any) {
        if let d = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .withoutEscapingSlashes]) {
            print(String(decoding: d, as: UTF8.self))
        }
    }

    static func encodeJSON<T: Encodable>(_ v: T) -> Any {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let d = try? enc.encode(v), let o = try? JSONSerialization.jsonObject(with: d) else { return NSNull() }
        return o
    }

    static func fail(_ msg: String) -> Int32 {
        FileHandle.standardError.write(Data("tsmtl: \(msg)\n".utf8))
        return 1
    }

    static func yesNo(_ b: Bool) -> String { b ? "sì" : "no" }

    // MARK: status

    static func status(json: Bool) -> Int32 {
        let r = StatusReport.probe(withCodesign: true)
        if json { printJSON(encodeJSON(r)); return 0 }
        print("kext:      \(r.kextLoaded ? "caricato" : "NON caricato (TSMetalEnabler assente in IORegistry)")"
              + (r.kextLoaded ? " versione=\(r.kextVersion ?? "?") accelPatched=\(r.kextAcceleratorPatched.map(yesNo) ?? "?") lvHook=\"\(r.lvHook ?? "?")\" lvAllowed=\(r.lvAllowed.map(String.init) ?? "?") lvRefused=\(r.lvRefused.map(String.init) ?? "?") lvLast=\(r.lvLastProcess ?? "-")" : ""))
        print("gpu:       \(r.gpuFound ? "\(r.gpuModel ?? "?") VRAM=\(r.vramTotalMB.map { "\($0) MB" } ?? "?") acceleratore=\(r.acceleratorClass ?? "?")" : "acceleratore Radeon non trovato")")
        print("plugin:    MetalPluginName=\(r.metalPluginName ?? "-") MetalPluginClassName=\(r.metalPluginClassName ?? "-")"
              + (r.pluginActive ? " (shim registrato)" : " (shim non registrato sulla GPU)"))
        if r.bundleInstalled {
            print("bundle:    installato \(r.bundlePath) id=\(r.bundleId ?? "?") versione=\(r.bundleVersion ?? "?") cdhash=\(r.bundleCDHash ?? "?")")
        } else {
            print("bundle:    NON installato (\(r.bundlePath) assente)")
        }
        let cfg = r.configDirExists ? (r.configDirWritable ? "presente, scrivibile" : "presente, NON scrivibile") : "assente"
        print("config:    \(r.configDir)\(r.configFromEnv ? " (TSMTL_CONFIG_DIR)" : "") \(cfg); policy.plist \(r.policyExists ? "presente" : "assente (valori predefiniti)") AutoEnable=\(yesNo(r.autoEnable)) voci=\(r.policyEntries)")
        if let e = r.policyError { print("config:    ATTENZIONE \(e)") }
        print("spoof:     kext=\(r.kextLoaded ? (r.spoofState ?? "assente (kext < 1.1)") : "non caricato") count=\(r.spoofCount.map(String.init) ?? "-") last=\(r.spoofLastProcess ?? "-") auto=\(r.spoofAuto ? "on" : "off") model=\(r.spoofModel) voci=\(r.spoofEntries)")
        let flags = [r.bootOff ? "-tsmtloff (kext spento)" : nil, r.bootNoLV ? "-tsmtlnolv (niente deroga LV)" : nil,
                     r.bootNoSpoof ? "-tsmtlnospoof (niente spoofing)" : nil].compactMap { $0 }
        print("boot-args: \(flags.isEmpty ? "nessun flag tsmtl" : flags.joined(separator: " "))")
        print("stato:     \(r.installed ? "shim installato e attivo" : "shim non installato o incompleto")")
        return 0
    }

    // MARK: stats

    static func gpuLine(_ s: GPUSample) -> String {
        "gpu: \(s.model ?? "GPU") carico=\(Fmt.pct(s.load)) (attesa hw \(Fmt.rate(s.hwWaitMsPerSec)) ms/s) utilDriver=\(s.driverUtilization.map { "\($0)%" } ?? "–")"
            + " vram=\(Fmt.mb(s.vramUsed))/\(Fmt.mb(s.vramTotal)) gart=\(Fmt.mb(s.gartUsed))/\(Fmt.mb(s.gartSize)) sys=\(Fmt.mb(s.sysMemInUse))"
            + " texture=\(s.textures.map(String.init) ?? "–") superfici=\(s.surfaces.map(String.init) ?? "–") ctxGL=\(s.glContexts.map(String.init) ?? "–")"
            + " swap/s=\(Fmt.rate(s.swapsPerSec, digits: 1)) pm4/s=\(Fmt.rate(s.pm4PerSec))"
    }

    static func appLines(_ rows: [AppStatsRow]) -> [String] {
        if rows.isEmpty { return ["app: nessuna statistica dallo shim (nessuna app con lo shim attivo, o shim non installato)"] }
        return rows.map { r in
            String(format: "app: %@ (%@) pid=%@ fps=%.1f draw/s=%.0f gpuBusy=%.0f%% upKB/s=%.0f pipeline=%.0f fallback=%.0f mslHits=%.0f memMB=%.1f drawableWaitMs=%.0f",
                   r.name, r.app, r.pids.map(String.init).joined(separator: ","), r.fps, r.draws, r.gpuBusy * 100,
                   r.uploadKBps, r.pipelines, r.fallbacks, r.mslHits, r.memMB, r.drawableWaitMs)
                + (r.dispatches > 0 || r.clRuns > 0 ? String(format: " dispatch/s=%.0f clRun/s=%.0f", r.dispatches, r.clRuns) : "")
        }
    }

    static func stats(_ args: inout [String]) -> Int32 {
        let json = take(&args, "--json")
        var interval: Double? = nil
        if let i = args.firstIndex(of: "--watch") {
            interval = 2
            if i + 1 < args.count, let v = Double(args[i + 1]), v > 0 { interval = v; args.remove(at: i + 1) }
            args.remove(at: i)
        }
        let count = value(&args, "--count").flatMap(Int.init)
        if !args.isEmpty { return fail("argomento sconosciuto: \(args[0])") }

        let reader = GPUReader()
        let agg = StatsAggregator()
        let lock = NSLock()
        let attached = DispatchSemaphore(value: 0)
        var sawHeader = false
        let stream = LogProcess(arguments: LogProcess.streamArgs(predicate: LogParser.predicate(categories: [.stats]), level: "default")) { line in
            if !sawHeader { sawHeader = true; attached.signal() }
            guard let e = LogParser.parse(line), e.category == .stats, let s = ShimStats.parse(e.message) else { return }
            lock.lock(); agg.add(s); lock.unlock()
        }
        guard stream.start() else { return fail("impossibile avviare \(Paths.logTool) stream") }
        _ = attached.wait(timeout: .now() + 3)   // "Filtering the log data..." = stream attached
        StatsLease.shared.acquire()
        _ = reader.read()
        let stop = {
            StatsLease.shared.stopNow()
            stream.stop()
        }
        for sig in [SIGINT, SIGTERM, SIGHUP] { signal(sig, SIG_IGN) }
        var sources: [DispatchSourceSignal] = []
        for sig in [SIGINT, SIGTERM, SIGHUP] {
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { stop(); exit(0) }
            src.resume()
            sources.append(src)
        }
        func report() {
            guard let g = reader.read() else { print("gpu: acceleratore Radeon non trovato"); return }
            lock.lock(); let rows = agg.rows(); lock.unlock()
            if json {
                printJSON(["gpu": encodeJSON(g), "apps": encodeJSON(rows), "lease": StatsLease.shared.active])
            } else {
                if interval != nil { print("--- \(LogEntry.fullFormatter.string(from: Date()))") }
                print(gpuLine(g))
                appLines(rows).forEach { print($0) }
            }
        }
        guard let interval else {
            Thread.sleep(forTimeInterval: 2.3)
            report()
            stop()
            return 0
        }
        var n = 0
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler {
            report()
            n += 1
            if let count, n >= count { stop(); exit(0) }
        }
        timer.resume()
        withExtendedLifetime((sources, timer)) { dispatchMain() }
    }

    // MARK: log

    static func log(_ args: inout [String]) -> Int32 {
        let follow = take(&args, "-f", "--follow")
        let json = take(&args, "--json")
        let lastArg = value(&args, "--last")
        let filterArg = value(&args, "--filter")
        let appArg = value(&args, "--app")?.lowercased()
        if !args.isEmpty { return fail("argomento sconosciuto: \(args[0])") }
        var categories: [LogCategory]? = nil
        if let filterArg {
            var cats: [LogCategory] = []
            for f in filterArg.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) {
                switch f {
                case "unimplemented", "unimpl", "nonimpl": cats.append(.unimplemented)
                case "error", "errors", "errori": cats.append(.error)
                case "warning", "warnings", "warn", "avvisi": cats.append(.warning)
                case "general", "generali", "info": cats += [.general, .policy]
                case "policy": cats.append(.policy)
                case "compute": cats.append(.compute)
                case "glass": cats.append(.glass)
                case "swift": cats.append(.swift)
                default: return fail("filtro sconosciuto: \(f) (usa unimplemented, error, warning, general, policy, compute, glass, swift)")
                }
            }
            categories = cats
        }
        let predicate = LogParser.predicate(categories: categories, excludingStats: true)
        // pid -> app id from policy lines, so --app can match a bundle id as well as a process name.
        var pidApp: [Int: String] = [:]
        let lock = NSLock()
        func matches(_ e: LogEntry) -> Bool {
            guard let appArg else { return true }
            if e.process.lowercased().contains(appArg) { return true }
            lock.lock(); defer { lock.unlock() }
            if let p = PolicyLine.parse(e) { pidApp[e.pid] = p.appId.lowercased() + " " + p.name.lowercased() }
            return pidApp[e.pid]?.contains(appArg) ?? false
        }
        func emit(_ e: LogEntry) {
            guard matches(e) else { return }
            if json { printJSON(e.json) } else { print(e.line) }
        }
        if appArg != nil, categories != nil {
            // Learn pid -> app id even when policy lines are filtered out.
            let out = Shell.run(Paths.logTool, LogProcess.showArgs(predicate: LogParser.predicate(categories: [.policy]),
                                                                   last: lastArg ?? "1h", info: false))
            for line in out.split(separator: "\n") {
                if let e = LogParser.parse(line), let p = PolicyLine.parse(e) {
                    pidApp[e.pid] = p.appId.lowercased() + " " + p.name.lowercased()
                }
            }
        }
        if !follow || lastArg != nil {
            let out = Shell.run(Paths.logTool, LogProcess.showArgs(predicate: predicate, last: lastArg ?? "1h"))
            var n = 0
            for line in out.split(separator: "\n") {
                if let e = LogParser.parse(line), e.category != .stats { emit(e); n += 1 }
            }
            if !follow {
                if n == 0 && !json { print("(nessun messaggio di \(Paths.subsystem) nell'intervallo \(lastArg ?? "1h"))") }
                return 0
            }
        }
        let stream = LogProcess(arguments: LogProcess.streamArgs(predicate: predicate), onLine: { line in
            if let e = LogParser.parse(line), e.category != .stats { emit(e) }
        }, onExit: { status in exit(status) })
        guard stream.start() else { return fail("impossibile avviare \(Paths.logTool) stream") }
        signal(SIGINT, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        src.setEventHandler { stream.stop(); exit(0) }
        src.resume()
        withExtendedLifetime(src) { dispatchMain() }
    }

    // MARK: apps / policy editing

    static func apps(_ args: inout [String]) -> Int32 {
        let json = take(&args, "--json")
        let last = value(&args, "--last") ?? "1d"
        if !args.isEmpty { return fail("argomento sconosciuto: \(args[0])") }
        let (policy, err) = PolicyStore.load()
        let seen = PolicyLine.latestPerApp(PolicyLine.history(last: last))
        if json {
            let entries: [[String: Any]] = policy.sortedEntries.map { e in
                let d = policy.decide(id: e.id, path: e.path)
                var o: [String: Any] = ["id": e.id, "name": e.displayName, "effective": d.on ? "on" : "off", "reason": d.reason.rawValue]
                if let v = e.enabled { o["enabled"] = v }
                if let p = e.path { o["path"] = p }
                return o
            }
            let recent: [[String: Any]] = seen.map { l in
                let d = policy.decide(id: l.appId, path: l.path)
                var o: [String: Any] = ["id": l.appId, "name": l.name, "seen": l.on ? "on" : "off", "seenReason": l.reason,
                                        "lastSeen": ISO8601DateFormatter().string(from: l.date), "pid": l.pid,
                                        "inList": policy.apps[l.appId] != nil, "effective": d.on ? "on" : "off", "reason": d.reason.rawValue]
                if let p = l.path { o["path"] = p }
                return o
            }
            var root: [String: Any] = ["configDir": Paths.configDir, "autoEnable": policy.autoEnable, "apps": entries, "recent": recent,
                                       "recentWindow": last]
            if let err { root["error"] = err }
            printJSON(root)
            return 0
        }
        print("config: \(Paths.policyFile)\(FileManager.default.fileExists(atPath: Paths.policyFile) ? "" : " (assente: valori predefiniti)")")
        if let err { print("ATTENZIONE: \(err)") }
        print("auto: \(policy.autoEnable ? "on" : "off") (shim automatico sulle app in Applicazioni)")
        print("elenco (\(policy.apps.count)):")
        if policy.apps.isEmpty { print("  (vuoto)") }
        for e in policy.sortedEntries {
            let d = policy.decide(id: e.id, path: e.path)
            let set = e.enabled.map { $0 ? "enable" : "disable" } ?? "auto"
            print("  \(d.on ? "on " : "off") \(d.reason.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)) \(e.id) impostazione=\(set) nome=\"\(e.displayName)\"\(e.path.map { " path=\($0)" } ?? "")")
        }
        print("viste di recente (log, ultimi \(last)): \(seen.count)")
        for l in seen {
            let d = policy.decide(id: l.appId, path: l.path)
            print("  \(l.on ? "on " : "off") \(l.reason.padding(toLength: 8, withPad: " ", startingAt: 0)) \(l.appId) nome=\"\(l.name)\" visto=\(LogEntry.fullFormatter.string(from: l.date)) pid=\(l.pid)\(policy.apps[l.appId] != nil ? " [in elenco]" : "") ora=\(d.on ? "on" : "off")/\(d.reason.rawValue)\(l.path.map { " path=\($0)" } ?? "")")
        }
        return 0
    }

    static func modify(_ change: (inout Policy) -> Void) -> Int32 {
        var (policy, err) = PolicyStore.load()
        if let err { return fail(err + " (non lo sovrascrivo)") }
        change(&policy)
        do { try PolicyStore.save(policy) } catch { return fail(error.localizedDescription) }
        return 0
    }

    static func badApp(_ arg: String) -> String {
        let path = (arg as NSString).expandingTildeInPath
        if !FileManager.default.fileExists(atPath: path) { return "\(arg) non esiste (serve un id come com.apple.Maps, un percorso .app o proc:nome)" }
        return "\(arg) non è un'app valida (serve un bundle .app con CFBundleIdentifier)"
    }

    static func setApp(_ args: [String], enabled: Bool) -> Int32 {
        guard args.count == 1 else { return fail("uso: tsmtl \(enabled ? "enable" : "disable") <id app | percorso .app | proc:nome>") }
        guard let app = AppIdentity.resolve(args[0]) else { return fail(badApp(args[0])) }
        if Policy.isCritical(id: app.id) { return fail("\(app.id) è un processo di sistema critico: lo shim resta sempre spento") }
        let rc = modify { p in
            var e = p.apps[app.id] ?? PolicyEntry(id: app.id)
            e.enabled = enabled
            e.name = e.name ?? app.name
            e.path = app.path ?? e.path
            p.apps[app.id] = e
        }
        if rc == 0 { print("\(enabled ? "attivato" : "disattivato"): \(app.id) (\(app.name)) – vale per le app avviate da ora") }
        return rc
    }

    static func resetApp(_ args: [String], remove: Bool) -> Int32 {
        guard args.count == 1 else { return fail("uso: tsmtl \(remove ? "remove" : "reset") <id app | percorso .app | proc:nome>") }
        guard let app = AppIdentity.resolve(args[0]) else { return fail(badApp(args[0])) }
        let (policy, _) = PolicyStore.load()
        guard policy.apps[app.id] != nil else { return fail("\(app.id) non è nell'elenco") }
        let rc = modify { p in
            if remove { p.apps[app.id] = nil } else { p.apps[app.id]?.enabled = nil }
        }
        if rc == 0 { print(remove ? "rimosso: \(app.id)" : "automatico: \(app.id) (resta in elenco senza impostazione manuale)") }
        return rc
    }

    static func auto(_ args: [String]) -> Int32 {
        guard args.count == 1, ["on", "off"].contains(args[0]) else { return fail("uso: tsmtl auto on|off") }
        let on = args[0] == "on"
        let rc = modify { $0.autoEnable = on }
        if rc == 0 { print("auto: \(on ? "on" : "off") – vale per le app avviate da ora") }
        return rc
    }

    // MARK: compute (System.Compute)

    static func compute(_ args: inout [String]) -> Int32 {
        let json = take(&args, "--json")
        guard let sub = args.first else { return computeList(json: json) }
        let rest = Array(args.dropFirst())
        switch sub {
        case "status": return computeList(json: json)
        case "on", "off":
            let on = sub == "on"
            let rc = modify { $0.hasCompute = true; $0.compute.enabled = on; $0.compute.enabledSet = true }
            if rc == 0 { print("compute: \(on ? "on" : "off") per tutte le app (salvo le eccezioni) – vale per le app avviate da ora") }
            return rc
        case "enable", "disable":
            guard rest.count == 1 else { return fail("uso: tsmtl compute \(sub) <id app | percorso .app | proc:nome>") }
            guard let app = AppIdentity.resolve(rest[0]) else { return fail(badApp(rest[0])) }
            let on = sub == "enable"
            let rc = modify { p in
                p.hasCompute = true
                var e = p.compute.apps[app.id] ?? PolicyEntry(id: app.id)
                e.enabled = on
                e.name = e.name ?? app.name
                e.path = e.path ?? app.path
                p.compute.apps[app.id] = e
            }
            if rc == 0 { print("compute \(on ? "attivo" : "spento"): \(app.id) (\(app.name)) – riavvia l'app") }
            return rc
        case "reset", "remove":
            guard rest.count == 1 else { return fail("uso: tsmtl compute \(sub) <id app | percorso .app | proc:nome>") }
            guard let app = AppIdentity.resolve(rest[0]) else { return fail(badApp(rest[0])) }
            guard PolicyStore.load().0.compute.apps[app.id] != nil else { return fail("\(app.id) non è nell'elenco del compute") }
            let rc = modify { p in
                p.hasCompute = true
                if sub == "remove" { p.compute.apps[app.id] = nil } else { p.compute.apps[app.id]?.enabled = nil }
            }
            if rc == 0 { print(sub == "remove" ? "compute: \(app.id) tolta dall'elenco" : "compute: \(app.id) segue l'interruttore generale") }
            return rc
        default:
            return fail("sottocomando sconosciuto: compute \(sub) (usa on, off, enable, disable, reset, remove)")
        }
    }

    static func computeList(json: Bool) -> Int32 {
        let (policy, err) = PolicyStore.load()
        let c = policy.compute
        func row(_ e: PolicyEntry) -> [String: Any] {
            let shimOn = policy.decide(id: e.id, path: e.path).on
            let d = c.decide(id: e.id, shimOn: shimOn)
            var o: [String: Any] = ["id": e.id, "name": e.displayName, "effective": d.on ? "on" : "off", "reason": d.reason.rawValue]
            if let v = e.enabled { o["enabled"] = v }
            if let p = e.path { o["path"] = p }
            return o
        }
        if json {
            var root: [String: Any] = ["configDir": Paths.configDir, "enabled": c.enabled, "apps": c.sortedEntries.map(row),
                                       "driver": StatusReport.probe(withCodesign: false).bundleVersion as Any? ?? NSNull()]
            if let err { root["error"] = err }
            printJSON(root)
            return 0
        }
        print("config: \(Paths.policyFile)\(policy.hasCompute ? "" : " (nessun System.Compute: valori predefiniti, compute acceso)")")
        if let err { print("ATTENZIONE: \(err)") }
        print("compute: \(c.enabled ? "on" : "off") per tutte le app (System.Compute.Enabled\(c.enabledSet ? "" : ", predefinito")) – OpenCL caricato solo dalle app che ne usano i kernel")
        for e in c.sortedEntries {
            let o = row(e)
            print("  \(o["effective"] as! String == "on" ? "on " : "off") \((o["reason"] as! String).padding(toLength: 8, withPad: " ", startingAt: 0)) \(e.id) nome=\"\(e.displayName)\"\(e.enabled.map { " impostazione=\($0 ? "enable" : "disable")" } ?? "")")
        }
        print("Righe del log: tsmtl log --filter compute")
        return 0
    }

    // MARK: swift (System.Swift)

    static func swift(_ args: inout [String]) -> Int32 {
        let json = take(&args, "--json")
        guard let sub = args.first else { return swiftStatus(json: json) }
        let rest = Array(args.dropFirst())
        let usage = "<id app | percorso .app | proc:nome>"
        switch sub {
        case "status": return swiftStatus(json: json)
        case "on", "off":
            let on = sub == "on"
            let rc = modify { $0.hasSwift = true; $0.swift.enabled = on; $0.swift.enabledSet = true }
            if rc == 0 { print("swift: \(on ? "on" : "off") per tutti i processi (salvo le eccezioni) – vale per i processi avviati da ora") }
            if rc == 0, on, SwiftControl.killed { print("ATTENZIONE: l'interruttore d'emergenza è presente (\(Paths.swiftKill)): tsmtl swift unkill") }
            return rc
        case "validate":
            guard rest.count == 1, ["on", "off"].contains(rest[0]) else { return fail("uso: tsmtl swift validate on|off") }
            let rc = modify { $0.hasSwift = true; $0.swift.validate = rest[0] == "on" }
            if rc == 0 { print("swift: validazione \(rest[0]) – righe \"last-mismatch\" in tsmtl swift stats") }
            return rc
        case "kill", "unkill":
            do { try SwiftControl.setKilled(sub == "kill") } catch { return fail("\(error)") }
            print(sub == "kill" ? "swift: interruttore d'emergenza presente (\(Paths.swiftKill)): spento nei processi avviati da ora"
                                : "swift: interruttore d'emergenza tolto")
            return 0
        case "enable", "disable":
            guard rest.count == 1 else { return fail("uso: tsmtl swift \(sub) \(usage)") }
            guard let app = AppIdentity.resolve(rest[0]) else { return fail(badApp(rest[0])) }
            let on = sub == "enable"
            let rc = modify { p in
                p.hasSwift = true
                var e = p.swift.apps[app.id] ?? PolicyEntry(id: app.id)
                e.enabled = on
                e.name = e.name ?? app.name
                e.path = e.path ?? app.path
                p.swift.apps[app.id] = e
            }
            if rc == 0 { print("swift \(on ? "attivo" : "spento"): \(app.id) (\(app.name)) – riavvia l'app") }
            return rc
        case "reset", "remove":
            guard rest.count == 1 else { return fail("uso: tsmtl swift \(sub) \(usage)") }
            guard let app = AppIdentity.resolve(rest[0]) else { return fail(badApp(rest[0])) }
            guard PolicyStore.load().0.swift.apps[app.id] != nil else { return fail("\(app.id) non è nell'elenco di TeraScale Swift") }
            let rc = modify { p in
                p.hasSwift = true
                if sub == "remove" { p.swift.apps[app.id] = nil } else { p.swift.apps[app.id]?.enabled = nil }
            }
            if rc == 0 { print(sub == "remove" ? "swift: \(app.id) tolta dall'elenco" : "swift: \(app.id) segue l'interruttore generale") }
            return rc
        case "stats":
            var r = rest
            let last = value(&r, "--last") ?? "1h"
            return swiftStats(last: last, json: json)
        default:
            return fail("sottocomando sconosciuto: swift \(sub) (usa on, off, enable, disable, reset, remove, validate, kill, unkill, stats)")
        }
    }

    static func swiftStatus(json: Bool) -> Int32 {
        let (policy, err) = PolicyStore.load()
        let w = policy.swift
        func row(_ e: PolicyEntry) -> [String: Any] {
            let d = w.decide(id: e.id)
            var o: [String: Any] = ["id": e.id, "name": e.displayName, "effective": d.on ? "on" : "off", "reason": d.reason.rawValue]
            if let v = e.enabled { o["enabled"] = v }
            return o
        }
        if json {
            var root: [String: Any] = ["configDir": Paths.configDir, "enabled": w.enabled, "validate": w.validate,
                                       "killSwitch": SwiftControl.killed, "apps": w.sortedEntries.map(row)]
            if let err { root["error"] = err }
            printJSON(root)
            return 0
        }
        print("config: \(Paths.policyFile)\(policy.hasSwift ? "" : " (nessun System.Swift: valori predefiniti, acceso)")")
        if let err { print("ATTENZIONE: \(err)") }
        print("swift: \(w.enabled ? "on" : "off") per tutti i processi (System.Swift.Enabled\(w.enabledSet ? "" : ", predefinito")), validazione \(w.validate ? "on" : "off")")
        print("interruttore d'emergenza: \(SwiftControl.killed ? "presente (\(Paths.swiftKill)): spento ovunque" : "assente")")
        for e in w.sortedEntries {
            let o = row(e)
            print("  \(o["effective"] as! String == "on" ? "on " : "off") \((o["reason"] as! String).padding(toLength: 8, withPad: " ", startingAt: 0)) \(e.id) nome=\"\(e.displayName)\"\(e.enabled.map { " impostazione=\($0 ? "enable" : "disable")" } ?? "")")
        }
        print("Contatori: tsmtl swift stats; righe del log: tsmtl log --filter swift")
        return 0
    }

    static func swiftStats(last: String, json: Bool) -> Int32 {
        let procs = SwiftReport.load(last: last)
        if json { printJSON(["processes": procs.map(\.json)]); return 0 }
        if procs.isEmpty { print("nessuna riga di TeraScale Swift nell'ultimo \(last) (il driver la scrive quando un processo lo carica)"); return 0 }
        for p in procs {
            var line = "\(p.process) pid=\(p.pid) \(p.on ? "on" : "off") (\(p.reason)) caricato a \(String(format: "%.1f", p.sinceStart)) s"
            if let s = p.stats {
                line += String(format: " | a %d s: %d risposte rapide in %.0f ms, %d al runtime di cui %d no (%.0f ms), differenze %d",
                               s.t, s.fast, s.fastMs, s.deferred, s.deferredNo, s.deferredNoMs, s.mismatches)
                if let m = s.lastMismatch { line += " (ultima: \(m))" }
            }
            print(line)
        }
        let mismatches = procs.compactMap(\.stats).reduce(0) { $0 + $1.mismatches }
        print("processi \(procs.count), accesi \(procs.filter(\.on).count), differenze col runtime \(mismatches)")
        return 0
    }

    // MARK: glass (System.Glass)

    static func glass(_ args: inout [String]) -> Int32 {
        let json = take(&args, "--json")
        guard let sub = args.first else { return glassStatus(json: json) }
        let rest = Array(args.dropFirst())
        switch sub {
        case "status": return glassStatus(json: json)
        case "on", "confirm":
            if sub == "confirm", !PolicyStore.load().0.glass.enabled { return fail("TeraScale Glass non è acceso: niente da confermare") }
            do { try GlassControl.on() } catch { return fail(error.localizedDescription) }
            print(sub == "confirm" ? "glass: confermato, resta acceso" : "glass: acceso – \(GlassReport.probe(kextVersion: StatusReport.probe(withCodesign: false).kextVersion).summary)")
            return 0
        case "trial":
            let minutes = rest.first.flatMap(Int.init) ?? 15
            guard minutes > 0, minutes <= 24 * 60, rest.count <= 1 else { return fail("uso: tsmtl glass trial [minuti] (1-1440)") }
            let deadline: Date
            do { deadline = try GlassControl.trial(minutes: minutes) } catch { return fail(error.localizedDescription) }
            print("glass: in prova fino alle \(DateFormatter.localizedString(from: deadline, dateStyle: .none, timeStyle: .short)); poi torna il vetro di Moraea, salvo tsmtl glass confirm")
            print("Il componente entra in WindowServer al suo prossimo avvio (riavvia il Mac: il logout non riavvia WindowServer).")
            return 0
        case "off", "revert":
            do { try GlassControl.off(reason: "tsmtl glass off") } catch { return fail(error.localizedDescription) }
            print("glass: spento – il vetro di Moraea torna entro un secondo, senza riavvio; dal prossimo avvio il driver non entra più in WindowServer")
            return 0
        default:
            return fail("sottocomando sconosciuto: glass \(sub) (usa on, off, trial, confirm)")
        }
    }

    static func glassStatus(json: Bool) -> Int32 {
        let report = StatusReport.probe(withCodesign: false)
        let g = GlassReport.probe(kextVersion: report.kextVersion)
        if json {
            var root: [String: Any] = ["enabled": g.policy.enabled, "summary": g.summary, "active": g.active, "replaced": g.replaced,
                                       "killSwitch": g.killSwitch, "kextReady": g.kextReady, "snippet": g.snippetPresent,
                                       "componentRunning": g.componentRunning, "recentWindowServerCrashes": g.recentCrashes]
            if let d = g.policy.trialDeadline { root["trialDeadline"] = ISO8601DateFormatter().string(from: d) }
            if let r = g.killReason { root["killReason"] = r }
            if !g.status.isEmpty { root["status"] = g.status.mapValues { "\($0)" } }
            printJSON(root)
            return 0
        }
        print("glass: \(g.summary)")
        print("policy: System.Glass.Enabled=\(g.policy.enabled)\(g.policy.trialDeadline.map { " prova fino a \(DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short))" } ?? "")")
        print("kext: \(g.kextVersion ?? "non caricato")\(g.kextReady ? "" : " (serve 1.2 per WindowServer)")")
        print("shader: \(g.snippetPresent ? Paths.glassSnippet : "mancanti (zsh system/glass.sh prepare)")\((g.snippetInfo["Translator"] as? String).map { " traduttore \($0)" } ?? "")")
        if !g.status.isEmpty {
            print("componente: stato=\(g.status["State"] ?? "?") programmi=\(g.replaced) falliti=\(g.status["Failed"] ?? 0) pid=\(g.status["PID"] ?? "?")\(g.componentRunning ? "" : " (WindowServer di allora, non quello attuale)")\((g.status["Detail"] as? String).flatMap { $0.isEmpty ? nil : " – \($0)" } ?? "")")
        }
        print("interruttore: \(g.killSwitch ? "presente (\(Paths.glassKill))" : "assente")")
        if !g.recentCrashes.isEmpty { print("crash di WindowServer nelle ultime 24 ore: \(g.recentCrashes.count) (\(g.recentCrashes.last!))") }
        print("Righe del log: tsmtl log --filter glass")
        return 0
    }

    // MARK: spoof

    static func spoof(_ args: inout [String]) -> Int32 {
        let json = take(&args, "--json")
        guard let sub = args.first else { return spoofList(json: json) }
        let rest = Array(args.dropFirst())
        switch sub {
        case "enable", "disable":
            guard rest.count == 1 else { return fail("uso: tsmtl spoof \(sub) <id app | percorso .app>") }
            return spoofSet(rest[0], enabled: sub == "enable")
        case "reset", "remove":
            guard rest.count == 1 else { return fail("uso: tsmtl spoof \(sub) <id app | percorso .app>") }
            guard let app = AppIdentity.resolve(rest[0]) else { return fail(badApp(rest[0])) }
            guard PolicyStore.load().0.spoof.apps[app.id] != nil else { return fail("\(app.id) non è nell'elenco dello spoofing") }
            let auto = SpoofPolicy.isAutoRule(app.id)
            let rc = modify { p in
                p.hasSpoof = true
                if sub == "remove" || auto { p.spoof.apps[app.id] = nil } else { p.spoof.apps[app.id]?.enabled = nil }
            }
            if rc == 0 {
                print(sub == "remove" || auto ? "spoof rimosso: \(app.id)\(auto ? " (torna alla regola automatica)" : "")"
                      : "spoof senza impostazione: \(app.id) (resta in elenco, il kext lo ignora)")
            }
            return rc
        case "auto":
            guard rest.count == 1, ["on", "off"].contains(rest[0]) else { return fail("uso: tsmtl spoof auto on|off") }
            let rc = modify { $0.hasSpoof = true; $0.spoof.auto = rest[0] == "on" }
            if rc == 0 { print("spoof auto: \(rest[0]) – vale per i processi avviati da ora") }
            return rc
        case "model":
            guard rest.count == 1 else { return fail("uso: tsmtl spoof model <nome>  (es. \(SpoofPolicy.defaultModel))") }
            let m = rest[0].trimmingCharacters(in: .whitespaces)
            guard !m.isEmpty, m.utf8.count < 32, !m.contains(" ") else { return fail("modello non valido: \(rest[0]) (max 31 caratteri, senza spazi)") }
            let rc = modify { $0.hasSpoof = true; $0.spoof.model = m }
            if rc == 0 { print("spoof model: \(m)") }
            return rc
        default:
            return fail("sottocomando sconosciuto: spoof \(sub) (usa enable, disable, reset, remove, auto, model)")
        }
    }

    static func spoofSet(_ arg: String, enabled: Bool) -> Int32 {
        guard let app = AppIdentity.resolve(arg) else { return fail(badApp(arg)) }
        let auto = SpoofPolicy.isAutoRule(app.id)
        if !auto && app.path == nil { return fail("per \(app.id) serve il percorso dell'app (.app): il kext riconosce i processi dal percorso") }
        let rc = modify { p in
            p.hasSpoof = true
            if auto {
                // Auto rules: an explicit entry only when it differs from what Auto would do.
                if enabled == p.spoof.auto { p.spoof.apps[app.id] = nil } else { p.spoof.apps[app.id] = SpoofEntry(id: app.id, enabled: enabled) }
            } else {
                var e = p.spoof.apps[app.id] ?? SpoofEntry(id: app.id)
                e.enabled = enabled
                e.name = e.name ?? app.name
                if let path = app.path { e.path = path; e.match = path + "/" }
                p.spoof.apps[app.id] = e
            }
        }
        if rc == 0 { print("spoof \(enabled ? "attivo" : "spento"): \(app.id) (\(app.name)) – riavvia l'app") }
        return rc
    }

    static func spoofList(json: Bool) -> Int32 {
        let (policy, err) = PolicyStore.load()
        let r = StatusReport.probe(withCodesign: false)
        let sp = policy.spoof
        let ids = SpoofPolicy.autoRules.map(\.id) + sp.manualEntries.map(\.id)
        func row(_ id: String) -> [String: Any] {
            let d = sp.decide(id: id), e = sp.apps[id]
            var o: [String: Any] = ["id": id, "name": e?.displayName ?? SpoofPolicy.autoRules.first { $0.id == id }?.name ?? id,
                                    "effective": d.on ? "on" : "off", "reason": d.reason.rawValue, "autoRule": SpoofPolicy.isAutoRule(id)]
            if let v = e?.enabled { o["enabled"] = v }
            if let m = e?.match ?? SpoofPolicy.autoRules.first(where: { $0.id == id })?.match { o["match"] = m }
            if let p = e?.path { o["path"] = p }
            return o
        }
        if json {
            var root: [String: Any] = ["configDir": Paths.configDir, "auto": sp.auto, "model": sp.model, "apps": ids.map(row),
                                       "kext": ["loaded": r.kextLoaded, "spoof": (r.spoofState as Any? ?? NSNull()), "count": (r.spoofCount as Any? ?? NSNull()),
                                                "lastProcess": (r.spoofLastProcess as Any? ?? NSNull())]]
            if let err { root["error"] = err }
            printJSON(root)
            return 0
        }
        print("config: \(Paths.policyFile)\(policy.hasSpoof ? "" : " (nessun dizionario Spoof: valori predefiniti)")")
        if let err { print("ATTENZIONE: \(err)") }
        print("kext: \(r.kextLoaded ? "spoof=\(r.spoofState ?? "assente (serve TSMetalEnabler 1.1)") count=\(r.spoofCount.map(String.init) ?? "-") last=\(r.spoofLastProcess ?? "-")" : "TSMetalEnabler non caricato: lo spoofing non ha effetto")")
        print("auto: \(sp.auto ? "on" : "off") model: \(sp.model)")
        for id in ids {
            let o = row(id)
            print("  \(o["effective"] as! String == "on" ? "on " : "off") \((o["reason"] as! String).padding(toLength: 8, withPad: " ", startingAt: 0)) \(id)\(SpoofPolicy.isAutoRule(id) ? " [regola automatica]" : "") nome=\"\(o["name"] as! String)\"\(o["enabled"].map { " impostazione=\(($0 as! Bool) ? "enable" : "disable")" } ?? "")\(o["match"].map { " match=\($0)" } ?? "")")
        }
        return 0
    }
}
