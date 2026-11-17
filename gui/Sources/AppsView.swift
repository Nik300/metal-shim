// "App" section: per-app policy (policy.plist) and the apps recently seen in the driver's policy log lines.
import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class AppsModel: ObservableObject {
    @Published private(set) var policy = Policy()
    @Published private(set) var loadError: String?
    @Published var saveError: String?
    @Published private(set) var recent: [PolicyLine] = []
    @Published private(set) var loadingRecent = false
    @Published private(set) var recentLoaded = false
    @Published private(set) var configExists = false
    @Published private(set) var configWritable = false
    static let recentWindow = "7d"

    func reload() {
        let (p, err) = PolicyStore.load()
        if p != policy { policy = p }
        loadError = err
        var isDir: ObjCBool = false
        configExists = FileManager.default.fileExists(atPath: Paths.configDir, isDirectory: &isDir) && isDir.boolValue
        configWritable = configExists && access(Paths.configDir, W_OK) == 0
    }

    var canEdit: Bool { configWritable && loadError == nil }

    private func mutate(_ change: (inout Policy) -> Void) {
        reload()
        guard canEdit else { return }
        var p = policy
        change(&p)
        do {
            try PolicyStore.save(p)
            p.fromFile = true
            policy = p
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    func setAuto(_ on: Bool) { mutate { $0.autoEnable = on } }

    func setEnabled(_ id: String, _ enabled: Bool?) {
        mutate { $0.apps[id]?.enabled = enabled }
    }

    func remove(_ id: String) { mutate { $0.apps[id] = nil } }

    func add(id: String, name: String, path: String?, enabled: Bool) {
        guard !Policy.isCritical(id: id) else {
            saveError = "\(name) è un processo di sistema critico: lo shim resta sempre spento."
            return
        }
        mutate { p in
            var e = p.apps[id] ?? PolicyEntry(id: id)
            e.enabled = enabled
            e.name = e.name ?? name
            e.path = path ?? e.path
            p.apps[id] = e
        }
    }

    /// .app URLs from the open panel or a drop. Returns false if none was an app.
    @discardableResult
    func add(urls: [URL]) -> Bool {
        let apps = urls.compactMap(AppIdentity.fromApp(at:))
        for a in apps { add(id: a.id, name: a.name, path: a.path, enabled: true) }
        if apps.isEmpty && !urls.isEmpty { saveError = "Trascina un'applicazione (.app): gli altri file non hanno un identificatore." }
        return !apps.isEmpty
    }

    // MARK: Spoof (same file, "Spoof" dictionary)

    func setSpoofAuto(_ on: Bool) { mutate { $0.hasSpoof = true; $0.spoof.auto = on } }

    func setSpoofModel(_ model: String) {
        let m = model.trimmingCharacters(in: .whitespaces)
        guard !m.isEmpty, m.utf8.count < 32, !m.contains(" ") else {
            saveError = "Modello non valido: massimo 31 caratteri, senza spazi (es. \(SpoofPolicy.defaultModel))."
            return
        }
        guard m != policy.spoof.model else { return }
        mutate { $0.hasSpoof = true; $0.spoof.model = m }
    }

    /// Switch of an auto-rule row: an explicit entry only when it differs from what Auto would do.
    func setSpoofAutoRule(_ id: String, _ on: Bool) {
        mutate { p in
            p.hasSpoof = true
            p.spoof.apps[id] = on == p.spoof.auto ? nil : SpoofEntry(id: id, enabled: on)
        }
    }

    func setSpoofEnabled(_ id: String, _ enabled: Bool?) {
        mutate { p in
            p.hasSpoof = true
            if SpoofPolicy.isAutoRule(id) && enabled == nil { p.spoof.apps[id] = nil } else { p.spoof.apps[id]?.enabled = enabled }
        }
    }

    func removeSpoof(_ id: String) { mutate { $0.hasSpoof = true; $0.spoof.apps[id] = nil } }

    // TeraScale Compute (System.Compute)
    func setComputeAll(_ on: Bool) { mutate { $0.hasCompute = true; $0.compute.enabled = on; $0.compute.enabledSet = true } }
    func setComputeEnabled(_ id: String, _ enabled: Bool?) { mutate { $0.hasCompute = true; $0.compute.apps[id]?.enabled = enabled } }
    func removeCompute(_ id: String) { mutate { $0.hasCompute = true; $0.compute.apps[id] = nil } }

    @discardableResult
    func addCompute(urls: [URL]) -> Bool {
        let apps = urls.compactMap(AppIdentity.fromApp(at:))
        if apps.isEmpty && !urls.isEmpty { saveError = "Trascina un'applicazione (.app)." }
        guard !apps.isEmpty else { return false }
        mutate { p in
            p.hasCompute = true
            // An added app is an exception to the global switch (on by default: the list mostly turns apps off).
            for a in apps { p.compute.apps[a.id] = PolicyEntry(id: a.id, enabled: !p.compute.enabled, name: a.name, path: a.path) }
        }
        return true
    }

    @discardableResult
    func addSpoof(urls: [URL]) -> Bool {
        let apps = urls.compactMap(AppIdentity.fromApp(at:))
        if apps.isEmpty && !urls.isEmpty { saveError = "Trascina un'applicazione (.app)." }
        guard !apps.isEmpty else { return false }
        mutate { p in
            p.hasSpoof = true
            for a in apps {
                guard let path = a.path else { continue }
                if SpoofPolicy.isAutoRule(a.id) {
                    p.spoof.apps[a.id] = p.spoof.auto ? nil : SpoofEntry(id: a.id, enabled: true)
                } else {
                    p.spoof.apps[a.id] = SpoofEntry(id: a.id, enabled: true, match: path + "/", name: a.name, path: path)
                }
            }
        }
        return true
    }

    func loadRecent() {
        guard !loadingRecent else { return }
        loadingRecent = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let lines = PolicyLine.latestPerApp(PolicyLine.history(last: AppsModel.recentWindow))
            DispatchQueue.main.async {
                self?.recent = lines
                self?.loadingRecent = false
                self?.recentLoaded = true
            }
        }
    }
}

struct AppsView: View {
    @ObservedObject var model: AppsModel
    @State private var dropTargeted = false

    var body: some View {
        Form {
            Section {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: "wand.and.sparkles")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.tint)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.tint(.accentColor.opacity(0.18)), in: .circle)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Attiva automaticamente su tutte le app").font(.title3.weight(.semibold))
                        Text("Lo shim si accende per ogni app nelle cartelle Applicazioni. Le app nell'elenco qui sotto hanno la precedenza; demoni e servizi di sistema restano spenti, salvo una voce nell'elenco.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Toggle("Attiva automaticamente su tutte le app", isOn: Binding(get: { model.policy.autoEnable }, set: { model.setAuto($0) }))
                        .toggleStyle(.switch)
                        .controlSize(.large)
                        .labelsHidden()
                        .disabled(!model.canEdit)
                }
                .padding(.vertical, 6)
            } footer: {
                Label("Le modifiche valgono per le app avviate dopo: le app già aperte vanno chiuse e riaperte.", systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }

            if let banner = banner {
                Section {
                    Label {
                        Text(banner).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
            }

            Section {
                if model.policy.apps.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.down.on.square").font(.title2).foregroundStyle(.tertiary)
                        Text("Nessuna app nell'elenco. Usa «Aggiungi app…» oppure trascina qui un'app dal Finder.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                ForEach(model.policy.sortedEntries) { entry in
                    PolicyRow(entry: entry, decision: model.policy.decide(id: entry.id, path: entry.path), canEdit: model.canEdit,
                              setEnabled: { model.setEnabled(entry.id, $0) }, remove: { model.remove(entry.id) })
                }
            } header: {
                HStack {
                    Text("App impostate a mano")
                    Spacer()
                    Button("Aggiungi app…", systemImage: "plus") { openPanel() }
                        .disabled(!model.canEdit)
                }
            }

            Section {
                if model.loadingRecent && model.recent.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Leggo i log degli ultimi 7 giorni…").foregroundStyle(.secondary)
                    }
                } else if model.recent.isEmpty {
                    Text(model.recentLoaded ? "Nessuna app ha caricato lo shim negli ultimi 7 giorni." : "")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.recent) { line in
                    RecentRow(line: line, inList: model.policy.apps[line.appId] != nil, canEdit: model.canEdit,
                              decision: model.policy.decide(id: line.appId, path: line.path)) { enabled in
                        model.add(id: line.appId, name: line.name, path: line.path, enabled: enabled)
                    }
                }
            } header: {
                HStack {
                    Text("App viste di recente")
                    Text("· ultimi 7 giorni, dai log del driver").foregroundStyle(.secondary)
                    Spacer()
                    if model.loadingRecent { ProgressView().controlSize(.small) }
                    Button("Aggiorna", systemImage: "arrow.clockwise") { model.loadRecent() }
                        .labelStyle(.iconOnly)
                        .disabled(model.loadingRecent)
                        .help("Rileggi i log")
                }
            }
        }
        .formStyle(.grouped)
        .dropDestination(for: URL.self) { urls, _ in
            model.add(urls: urls)
        } isTargeted: { dropTargeted = $0 }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .alert("Impossibile salvare la policy", isPresented: Binding(get: { model.saveError != nil }, set: { if !$0 { model.saveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.saveError ?? "")
        }
        .navigationTitle("App")
        .navigationSubtitle(Paths.policyFile)
        .toolbar {
            ToolbarItem {
                Button("Aggiungi app…", systemImage: "plus") { openPanel() }
                    .disabled(!model.canEdit)
                    .help("Scegli un'app da aggiungere all'elenco")
            }
        }
        .onAppear {
            model.reload()
            if !model.recentLoaded { model.loadRecent() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.reload() }
    }

    private var banner: String? {
        if let e = model.loadError { return e.prefix(1).uppercased() + e.dropFirst() + ". Correggi o cancella il file per poter modificare la policy da qui." }
        if !model.configExists {
            return "La cartella di configurazione \(Paths.configDir) non esiste ancora: verrà creata dall'installazione dello shim. Fino ad allora la policy non si può salvare (valori in uso: automatico su tutte le app, elenco vuoto)."
        }
        if !model.configWritable {
            return "La cartella \(Paths.configDir) non è scrivibile dal tuo utente: l'installazione dovrebbe assegnarla a te (giulia:staff)."
        }
        return nil
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.title = "Aggiungi app"
        panel.prompt = "Aggiungi"
        panel.message = "Scegli una o più app: lo shim sarà attivo per queste app (puoi cambiarlo dall'elenco)."
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.begin { response in
            if response == .OK { model.add(urls: panel.urls) }
        }
    }
}

struct DecisionBadge: View {
    var decision: Decision

    var body: some View {
        let text = (decision.on ? "Attivo" : "Spento") + " · " + decision.reason.label
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(decision.on ? Color.green : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((decision.on ? Color.green : Color.secondary).opacity(0.12), in: Capsule())
            .lineLimit(1)
    }
}

struct PolicyRow: View {
    var entry: PolicyEntry
    var decision: Decision
    var canEdit: Bool
    var setEnabled: (Bool?) -> Void
    var remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: AppIcons.icon(id: entry.id, path: entry.path)).resizable().frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName).font(.body.weight(.medium)).lineLimit(1)
                Text(entry.id).font(.caption).foregroundStyle(.secondary).lineLimit(1).textSelection(.enabled)
            }
            Spacer(minLength: 8)
            DecisionBadge(decision: decision)
            if entry.enabled == nil {
                Text("auto").font(.caption).foregroundStyle(.tertiary)
            }
            Toggle("Shim per \(entry.displayName)", isOn: Binding(get: { entry.enabled ?? decision.on }, set: { setEnabled($0) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(!canEdit || decision.reason == .critical)
            Menu {
                Button("Ripristina automatico", systemImage: "arrow.uturn.backward") { setEnabled(nil) }
                    .disabled(entry.enabled == nil || !canEdit)
                if let path = entry.path {
                    Button("Mostra nel Finder", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    }
                }
                Divider()
                Button("Rimuovi dall'elenco", systemImage: "trash", role: .destructive) { remove() }
                    .disabled(!canEdit)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Altre azioni")
        }
        .padding(.vertical, 2)
    }
}

struct RecentRow: View {
    var line: PolicyLine
    var inList: Bool
    var canEdit: Bool
    var decision: Decision
    var add: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: AppIcons.icon(id: line.appId, path: line.path)).resizable().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(line.name).font(.body.weight(.medium)).lineLimit(1)
                HStack(spacing: 4) {
                    Text(verbatim: line.appId)
                    Text(verbatim: "·")
                    Text(verbatim: "visto \(line.date.formatted(.relative(presentation: .named))) (\(line.process), pid \(line.pid)): \(line.on ? "attivo" : "spento"), \(Reason(rawValue: line.reason)?.label ?? line.reason)")
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if decision.reason == .critical {
                Text("Critico").font(.caption).foregroundStyle(.secondary)
            } else if inList {
                Label("In elenco", systemImage: "checkmark").font(.caption).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 6) {
                    Button("Attiva") { add(true) }
                    Button("Disattiva") { add(false) }
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .disabled(!canEdit)
                .help("Aggiungi all'elenco con lo shim attivo o spento")
            }
        }
        .padding(.vertical, 1)
    }
}
