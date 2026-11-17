// "TeraScale Swift" section (Sistema): the Swift conformance accelerator the driver bundle starts in every process
// that loads it ("System.Swift" in policy.plist, docs/OTTIMIZZAZIONE-SWIFT.md). This app also links the accelerator
// itself (src/swift/TSSwiftAccel.c, bridged by build.sh) and starts it at launch, before SwiftUI builds its views.
import Foundation
import os
import SwiftUI

/// The CLI's and the section's commands. Turning on or off applies to processes started afterwards.
enum SwiftControl {
    static var killed: Bool { FileManager.default.fileExists(atPath: Paths.swiftKill) }

    static func setKilled(_ on: Bool) throws {
        if on {
            try FileManager.default.createDirectory(atPath: Paths.swiftState, withIntermediateDirectories: true)
            guard FileManager.default.createFile(atPath: Paths.swiftKill, contents: Data("spento a mano\n".utf8)) else {
                throw PolicyStore.Failure.write("non riesco a scrivere \(Paths.swiftKill)")
            }
        } else if killed {
            try FileManager.default.removeItem(atPath: Paths.swiftKill)
        }
    }

    static func modify(_ change: (inout SwiftPolicy) -> Void) throws {
        var (policy, err) = PolicyStore.load()
        if let err { throw PolicyStore.Failure.write(err + " (non lo sovrascrivo)") }
        policy.hasSwift = true
        change(&policy.swift)
        try PolicyStore.save(policy)
    }

    /// This app's own accelerator: same policy as the driver (the app's entry, then the global switch), same log lines.
    static func startInThisApp() {
        let id = Bundle.main.bundleIdentifier ?? "com.terascale.mtlshim.monitor"
        let policy = PolicyStore.load().0.swift
        let decision = policy.decide(id: id)
        let log = Logger(subsystem: Paths.subsystem, category: "swift")
        let diag = TSSwiftDiagnose()
        let on = decision.on && !killed
        let hooks = on ? TSSwiftInstall(policy.validate ? Int32(TSSwiftValidate) : 0) : 0
        let reason = killed && decision.on ? "kill-switch" : decision.reason.rawValue
        log.notice("\(on && hooks > 0 ? "on" : "off", privacy: .public) TeraScaleMetal pid=\(getpid()) reason=\(reason, privacy: .public) hooks=\(hooks) validate=\(policy.validate ? 1 : 0) version=app launchMode=\(String(format: "%#x", diag.launchMode), privacy: .public) preoptimized=\(diag.preoptimized) cacheOverridden=\(diag.cacheOverridden) images=\(diag.images) sinceStart=\(String(format: "%.2f", diag.secondsSinceStart), privacy: .public) hookable=\(diag.hookable)")
        guard hooks > 0 else { return }
        for seconds in [15, 60, 300] {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .seconds(seconds)) {
                var s = TSSwiftStats()
                TSSwiftGetStats(&s)
                let last = TSSwiftLastMismatch().map { " last-mismatch=" + String(cString: $0) } ?? ""
                let line = String(format: "stats TeraScaleMetal pid=%d t=%ds fast=%llu nominal=%llu conditional=%llu class=%llu structural=%llu fastMs=%.1f deferred=%llu deferredMs=%.0f deferredNo=%llu deferredNoMs=%.0f mismatches=%llu indexMs=%.1f indexKB=%.0f protocols=%u records=%llu",
                                  getpid(), seconds, TSSwiftFastTotal(&s), s.fastNominal, s.fastConditional, s.fastClass, s.fastStructural,
                                  Double(s.fastNs) / 1e6, s.deferred, Double(s.deferredNs) / 1e6, s.deferredNo, Double(s.deferredNoNs) / 1e6,
                                  s.mismatches, Double(s.indexNs) / 1e6, Double(s.indexBytes) / 1024, s.protocols, s.records) + last
                log.notice("\(line, privacy: .public)")
            }
        }
    }
}

/// One process seen in the log: the driver's start line ("on|off|unhooked <name> pid= reason= ...") and its latest
/// stats line.
struct SwiftProcess: Identifiable {
    struct Stats {
        var t = 0, fast = 0, nominal = 0, conditional = 0, klass = 0, structural = 0, deferred = 0, deferredNo = 0, mismatches = 0
        var fastMs = 0.0, deferredNoMs = 0.0, indexKB = 0.0
        var lastMismatch: String?
    }
    var id: Int { pid }
    var pid: Int
    var process: String
    var date: Date
    var on = false
    var reason = "?"
    var sinceStart = 0.0
    var launchMode = "?"
    var stats: Stats?

    var json: [String: Any] {
        var o: [String: Any] = ["pid": pid, "process": process, "on": on, "reason": reason, "sinceStart": sinceStart, "launchMode": launchMode]
        if let s = stats {
            o["stats"] = ["t": s.t, "fast": s.fast, "nominal": s.nominal, "conditional": s.conditional, "class": s.klass,
                          "structural": s.structural, "fastMs": s.fastMs, "deferred": s.deferred, "deferredNo": s.deferredNo,
                          "deferredNoMs": s.deferredNoMs, "mismatches": s.mismatches, "indexKB": s.indexKB,
                          "lastMismatch": s.lastMismatch as Any? ?? NSNull()]
        }
        return o
    }
}

enum SwiftReport {
    static func fields(_ message: String) -> [String: String] {
        var out: [String: String] = [:]
        let body = message.components(separatedBy: " last-mismatch=")
        for token in body[0].split(separator: " ") {
            guard let eq = token.firstIndex(of: "=") else { continue }
            out[String(token[..<eq])] = String(token[token.index(after: eq)...])
        }
        if body.count > 1 { out["last-mismatch"] = body[1] }
        return out
    }

    /// Reads the "swift" lines of the driver log (blocking: `log show`), latest first, one row per process.
    static func load(last: String) -> [SwiftProcess] {
        let out = Shell.run(Paths.logTool, LogProcess.showArgs(predicate: LogParser.predicate(categories: [.swift]), last: last, info: false))
        var procs: [Int: SwiftProcess] = [:]
        for line in out.split(separator: "\n") {
            guard let e = LogParser.parse(line), e.category == .swift else { continue }
            let f = fields(e.message)
            var p = procs[e.pid] ?? SwiftProcess(pid: e.pid, process: e.process, date: e.date)
            p.date = max(p.date, e.date)
            if e.message.hasPrefix("stats ") {
                func i(_ k: String) -> Int { Int(f[k] ?? "") ?? 0 }
                func d(_ k: String) -> Double { Double(f[k] ?? "") ?? 0 }
                p.stats = SwiftProcess.Stats(t: Int(f["t"]?.dropLast() ?? "") ?? 0, fast: i("fast"), nominal: i("nominal"),
                                             conditional: i("conditional"), klass: i("class"), structural: i("structural"),
                                             deferred: i("deferred"), deferredNo: i("deferredNo"), mismatches: i("mismatches"),
                                             fastMs: d("fastMs"), deferredNoMs: d("deferredNoMs"), indexKB: d("indexKB"),
                                             lastMismatch: f["last-mismatch"])
            } else if e.message.hasPrefix("unhooked "), p.on {
                // the driver bundle arrived after this process's own copy (the control app): keep the "on" line
            } else {
                p.on = e.message.hasPrefix("on ")
                p.reason = f["reason"] ?? "?"
                p.sinceStart = Double(f["sinceStart"] ?? "") ?? 0
                p.launchMode = f["launchMode"] ?? "?"
            }
            procs[e.pid] = p
        }
        return procs.values.sorted { $0.date > $1.date }
    }
}

@MainActor
final class SwiftAccelModel: ObservableObject {
    @Published private(set) var policy = SwiftPolicy()
    @Published private(set) var killed = false
    @Published private(set) var processes: [SwiftProcess] = []
    @Published private(set) var loading = false
    @Published var error: String?

    func refresh() {
        policy = PolicyStore.load().0.swift
        killed = SwiftControl.killed
        loading = true
        Task.detached(priority: .utility) {
            let procs = SwiftReport.load(last: "2h")
            await MainActor.run { self.processes = procs; self.loading = false }
        }
    }

    func perform(_ action: () throws -> Void) {
        do { try action() } catch { self.error = error.localizedDescription }
        policy = PolicyStore.load().0.swift
        killed = SwiftControl.killed
    }
}

struct SwiftAccelView: View {
    @StateObject private var model = SwiftAccelModel()

    var body: some View {
        let p = model.policy
        let on = p.enabled
        Form {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "swift")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.tint)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.tint(.accentColor.opacity(0.18)), in: .circle)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TeraScale Swift").font(.title3.weight(.semibold))
                        Text("Le app SwiftUI (Impostazioni, la pagina Sfondi, questa app) chiedono al runtime Swift migliaia di volte se un tipo è Equatable. Su questo Mac ogni \"no\" costa una scansione di tutte le conformità caricate (1–4 ms), anche nelle app di Apple, che qui partono senza le tabelle precalcolate di dyld. TeraScale Swift risponde subito quando le conformità lo dimostrano e lascia tutto il resto al runtime: −60% di CPU all'avvio di questa app, −41% all'apertura di Impostazioni → Sfondi.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 6)
            }

            if model.killed {
                Section {
                    Label {
                        Text("Interruttore d'emergenza presente (\(Paths.swiftKill)): TeraScale Swift è spento in tutti i processi avviati da ora.")
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    Button("Togli l'interruttore", systemImage: "arrow.uturn.backward") { model.perform { try SwiftControl.setKilled(false) } }
                }
            }

            Section {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Risposte rapide del runtime Swift").font(.headline)
                        Text(on ? "Acceso in tutti i processi che caricano il driver, salvo le eccezioni. Vale per i processi avviati da ora."
                                : "Spento per tutti i processi, salvo le eccezioni. Vale per i processi avviati da ora; le app aperte vanno riavviate.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Toggle("Risposte rapide del runtime Swift", isOn: Binding(get: { on }, set: { v in
                        model.perform { try SwiftControl.modify { $0.enabled = v; $0.enabledSet = true } }
                    }))
                    .toggleStyle(.switch).controlSize(.large).labelsHidden()
                }
                .padding(.vertical, 4)
                Toggle(isOn: Binding(get: { p.validate }, set: { v in model.perform { try SwiftControl.modify { $0.validate = v } } })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Validazione")
                        Text("Ogni risposta rapida viene confrontata con il runtime, che ha sempre l'ultima parola; le differenze finiscono nel log. Più lento: per il periodo di prova.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !model.killed {
                    Button("Interruttore d'emergenza", systemImage: "power", role: .destructive) { model.perform { try SwiftControl.setKilled(true) } }
                }
            }

            if !p.apps.isEmpty {
                Section("Eccezioni") {
                    ForEach(p.sortedEntries) { e in
                        HStack {
                            Text(e.displayName)
                            Text(e.id).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(e.enabled.map { $0 ? "sempre acceso" : "sempre spento" } ?? "segue l'interruttore").foregroundStyle(.secondary)
                            Button("Togli", systemImage: "minus.circle") { model.perform { try SwiftControl.modify { $0.apps[e.id] = nil } } }
                                .labelStyle(.iconOnly).buttonStyle(.borderless)
                        }
                    }
                }
            }

            Section {
                if model.processes.isEmpty {
                    Text(model.loading ? "Lettura del log…" : "Nessun processo nelle ultime 2 ore: il driver scrive una riga quando un processo lo carica.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.processes) { proc in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Image(systemName: proc.on ? "bolt.fill" : "bolt.slash").foregroundStyle(proc.on ? Color.accentColor : .secondary)
                            Text(proc.process).font(.body.weight(.medium))
                            Text("pid \(proc.pid)").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(proc.date, style: .time).font(.caption).foregroundStyle(.secondary)
                        }
                        if let s = proc.stats {
                            Text("a \(s.t) s: \(s.fast) risposte rapide (\(Int(s.fastMs)) ms), \(s.deferredNo) \"no\" lasciati al runtime (\(Int(s.deferredNoMs)) ms)\(s.mismatches > 0 ? ", \(s.mismatches) DIFFERENZE" : "")")
                                .font(.caption).foregroundStyle(s.mismatches > 0 ? .red : .secondary)
                        } else {
                            Text("\(proc.on ? "acceso" : "spento") (\(proc.reason)), caricato \(String(format: "%.1f", proc.sinceStart)) s dopo l'avvio del processo")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Processi recenti")
                    Spacer()
                    Button("Aggiorna", systemImage: "arrow.clockwise") { model.refresh() }.labelStyle(.iconOnly).buttonStyle(.borderless)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("TeraScale Swift")
        .onAppear { model.refresh() }
        .alert("TeraScale Swift", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}
