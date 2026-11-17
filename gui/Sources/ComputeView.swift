// "TeraScale Compute" section (Sistema): Metal compute encoders run on the GPU through OpenCL 1.2 or as GL passes
// ("System.Compute" in policy.plist, docs/PIANO-COMPUTE.md).
import AppKit
import SwiftUI

struct ComputeView: View {
    @ObservedObject var model: AppsModel
    @ObservedObject var status: StatusModel
    @State private var dropTargeted = false

    var body: some View {
        let c = model.policy.compute
        Form {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "cpu")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.tint)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.tint(.accentColor.opacity(0.18)), in: .circle)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TeraScale Compute").font(.title3.weight(.semibold))
                        Text("Esegue sulla GPU i kernel compute di Metal, che altrimenti lo shim ignora: quelli che scrivono una sola texture diventano passate OpenGL, gli altri (buffer, atomiche, memoria threadgroup, barriere) girano su OpenCL 1.2. Serve alle app e ai giochi che calcolano sulla GPU (Mappe ne usa uno per ridurre le texture); CoreAnimation e CoreImage non ne hanno bisogno. Senza, quei kernel non scrivono nulla e l'app mostra risultati sbagliati (in Mappe i monumenti 3D restano neri). I kernel che usano funzioni delle sole GPU Apple (simdgroup, imageblock) restano spenti. Le modifiche valgono per le app avviate dopo.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 6)
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
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Attiva per tutte le app").font(.headline)
                        Text("Compute acceso in ogni app in cui lo shim è attivo, salvo le eccezioni qui sotto (è il predefinito). Spento: solo le app dell'elenco impostate su acceso.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Toggle("Attiva per tutte le app", isOn: Binding(get: { c.enabled }, set: { model.setComputeAll($0) }))
                        .toggleStyle(.switch).controlSize(.large).labelsHidden()
                        .disabled(!model.canEdit)
                }
                .padding(.vertical, 4)
            } footer: {
                Label("OpenCL viene caricato solo nelle app che usano un kernel che ne ha bisogno; la prima compilazione di un kernel può richiedere qualche decimo di secondo. Righe del log: filtro «Compute» nella sezione Log, oppure tsmtl log --filter compute.",
                      systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                if c.sortedEntries.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.down.on.square").font(.title2).foregroundStyle(.tertiary)
                        Text(c.enabled ? "Nessuna eccezione. Usa «Aggiungi app…» oppure trascina qui un'app dal Finder per spegnere il compute solo per lei."
                                       : "Nessuna app. Usa «Aggiungi app…» oppure trascina qui un'app dal Finder per accendere il compute solo per lei.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                ForEach(c.sortedEntries) { e in
                    ComputeRow(entry: e, decision: c.decide(id: e.id, shimOn: model.policy.decide(id: e.id, path: e.path).on),
                               canEdit: model.canEdit, setOn: { model.setComputeEnabled(e.id, $0) },
                               reset: { model.setComputeEnabled(e.id, nil) }, remove: { model.removeCompute(e.id) })
                }
            } header: {
                HStack {
                    Text(c.enabled ? "Eccezioni" : "App")
                    Spacer()
                    Button("Aggiungi app…", systemImage: "plus") { openPanel() }
                        .disabled(!model.canEdit)
                }
            }

            Section("Driver") {
                if let r = status.report {
                    LabeledContent("Driver installato") {
                        StatusBadge(state: r.bundleInstalled ? .ok : .warning, text: r.bundleInstalled ? "versione \(r.bundleVersion ?? "?")" : "non installato")
                    }
                    LabeledContent("OpenCL", value: FileManager.default.fileExists(atPath: "/System/Library/Frameworks/OpenCL.framework") ? "presente (1.2)" : "assente")
                } else {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
        .dropDestination(for: URL.self) { urls, _ in
            model.addCompute(urls: urls)
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
        .navigationTitle("TeraScale Compute")
        .navigationSubtitle(c.enabled ? "acceso per tutte le app" : "spento salvo le app dell'elenco")
        .toolbar {
            ToolbarItem {
                Button("Aggiorna", systemImage: "arrow.clockwise") { model.reload(); status.refresh() }
                    .help("Rileggi la policy e lo stato del driver")
            }
        }
        .onAppear {
            model.reload()
            if status.report == nil { status.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.reload() }
    }

    private var banner: String? {
        if let e = model.loadError { return e.prefix(1).uppercased() + e.dropFirst() + "." }
        if !model.configExists { return "La cartella di configurazione \(Paths.configDir) non esiste: il compute non si può impostare." }
        if !model.configWritable { return "La cartella \(Paths.configDir) non è scrivibile dal tuo utente." }
        return nil
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.title = model.policy.compute.enabled ? "Spegni il compute per un'app" : "Accendi il compute per un'app"
        panel.prompt = "Aggiungi"
        panel.message = model.policy.compute.enabled ? "Scegli una o più app: i loro kernel compute Metal verranno ignorati, come senza TeraScale Compute."
                                                     : "Scegli una o più app: i loro kernel compute Metal gireranno sulla GPU."
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.begin { response in
            if response == .OK { model.addCompute(urls: panel.urls) }
        }
    }
}

struct ComputeRow: View {
    var entry: PolicyEntry
    var decision: Decision
    var canEdit: Bool
    var setOn: (Bool) -> Void
    var reset: () -> Void
    var remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: AppIcons.icon(id: entry.id, path: entry.path)).resizable().frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName).font(.body.weight(.medium)).lineLimit(1)
                Text(entry.id).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            }
            Spacer(minLength: 8)
            Text((decision.on ? "Compute acceso" : "Spento") + " · " + decision.reason.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(decision.on ? Color.green : Color.secondary)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background((decision.on ? Color.green : Color.secondary).opacity(0.12), in: Capsule())
                .lineLimit(1)
            Toggle("Compute per \(entry.displayName)", isOn: Binding(get: { decision.on }, set: { setOn($0) }))
                .toggleStyle(.switch).labelsHidden().disabled(!canEdit || decision.reason == .shimOff)
            Menu {
                Button("Segui l'interruttore generale", systemImage: "arrow.uturn.backward") { reset() }
                    .disabled(entry.enabled == nil || !canEdit)
                Divider()
                Button("Rimuovi dall'elenco", systemImage: "trash", role: .destructive) { remove() }.disabled(!canEdit)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden).fixedSize()
            .help("Altre azioni")
        }
        .padding(.vertical, 2)
    }
}
