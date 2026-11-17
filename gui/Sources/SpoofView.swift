// "Spoofing" section: which processes see a newer Mac model (kext TSMetalEnabler 1.1, "Spoof" in policy.plist).
import AppKit
import SwiftUI

struct SpoofView: View {
    @ObservedObject var model: AppsModel
    @ObservedObject var status: StatusModel
    @State private var modelText = ""
    @State private var dropTargeted = false

    var body: some View {
        let sp = model.policy.spoof
        Form {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "theatermasks")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.tint)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.tint(.accentColor.opacity(0.18)), in: .circle)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Spoofing del modello del Mac").font(.title3.weight(.semibold))
                        Text("Chrome e il WebGL di Safari rifiutano Metal perché leggono il modello del Mac (iMac12,1, troppo vecchio). Per i processi qui sotto il kext risponde con un modello più recente. Cambia solo la lettura della proprietà «model» da parte di quei processi: il resto del sistema e le altre app vedono il modello vero. Le modifiche valgono dopo aver riavviato l'app.")
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
                        Text("Automatico su Safari e Chrome").font(.headline)
                        Text("Spoofing su Google Chrome, Safari e i processi web di WebKit, salvo le eccezioni qui sotto.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Toggle("Automatico su Safari e Chrome", isOn: Binding(get: { sp.auto }, set: { model.setSpoofAuto($0) }))
                        .toggleStyle(.switch).controlSize(.large).labelsHidden()
                        .disabled(!model.canEdit)
                }
                .padding(.vertical, 4)
                LabeledContent("Modello mostrato") {
                    HStack(spacing: 8) {
                        TextField("Modello", text: $modelText, prompt: Text(SpoofPolicy.defaultModel))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 140)
                            .onSubmit { model.setSpoofModel(modelText) }
                        Button("Applica") { model.setSpoofModel(modelText) }
                            .disabled(!model.canEdit || modelText == sp.model)
                    }
                    .disabled(!model.canEdit)
                }
            } footer: {
                Label("Le modifiche valgono per le app avviate dopo: chiudi e riapri Safari o Chrome.", systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section("Regole automatiche") {
                ForEach(SpoofPolicy.autoRules, id: \.id) { rule in
                    SpoofRow(id: rule.id, name: rule.name, detail: "\(rule.id) · percorso con «\(rule.match)»",
                             iconPath: nil, decision: sp.decide(id: rule.id), isOverridden: sp.apps[rule.id]?.enabled != nil,
                             canEdit: model.canEdit, setOn: { model.setSpoofAutoRule(rule.id, $0) },
                             reset: { model.setSpoofEnabled(rule.id, nil) }, remove: nil)
                }
            }

            Section {
                if sp.manualEntries.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.down.on.square").font(.title2).foregroundStyle(.tertiary)
                        Text("Nessun'altra app. Usa «Aggiungi app…» oppure trascina qui un'app dal Finder (per esempio un altro browser basato su Chromium).")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                ForEach(sp.manualEntries) { e in
                    SpoofRow(id: e.id, name: e.displayName, detail: "\(e.id) · \(e.match ?? e.path.map { $0 + "/" } ?? "nessun percorso")",
                             iconPath: e.path, decision: sp.decide(id: e.id), isOverridden: e.enabled != nil,
                             canEdit: model.canEdit, setOn: { model.setSpoofEnabled(e.id, $0) },
                             reset: { model.setSpoofEnabled(e.id, nil) }, remove: { model.removeSpoof(e.id) })
                }
            } header: {
                HStack {
                    Text("Altre app")
                    Spacer()
                    Button("Aggiungi app…", systemImage: "plus") { openPanel() }
                        .disabled(!model.canEdit)
                }
            }

            Section("Kext") {
                if let r = status.report {
                    LabeledContent("Spoofing nel kext") {
                        StatusBadge(state: r.spoofActive ? .ok : .warning,
                                    text: !r.kextLoaded ? "TSMetalEnabler non caricato" : (r.spoofState ?? "assente (serve la versione 1.1)"))
                    }
                    LabeledContent("Versione del kext", value: r.kextVersion ?? "–")
                    LabeledContent("Letture falsificate", value: r.spoofCount.map { "\($0)" } ?? "–")
                    LabeledContent("Ultimo processo", value: r.spoofLastProcess ?? "–")
                } else {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
        .dropDestination(for: URL.self) { urls, _ in
            model.addSpoof(urls: urls)
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
        .navigationTitle("Spoofing")
        .navigationSubtitle("modello mostrato: \(sp.model)")
        .toolbar {
            ToolbarItem {
                Button("Aggiorna", systemImage: "arrow.clockwise") { model.reload(); status.refresh() }
                    .help("Rileggi la policy e lo stato del kext")
            }
        }
        .onAppear {
            model.reload()
            modelText = model.policy.spoof.model
            if status.report == nil { status.refresh() }
        }
        .onChange(of: model.policy.spoof.model) { _, m in modelText = m }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.reload() }
    }

    private var banner: String? {
        if let e = model.loadError { return e.prefix(1).uppercased() + e.dropFirst() + "." }
        if !model.configExists { return "La cartella di configurazione \(Paths.configDir) non esiste: lo spoofing non si può impostare." }
        if !model.configWritable { return "La cartella \(Paths.configDir) non è scrivibile dal tuo utente." }
        guard let r = status.report else { return nil }
        if !r.kextLoaded { return "Il kext TSMetalEnabler non è caricato: queste impostazioni non hanno effetto finché non è installato (versione 1.1 o successiva) e il Mac non è stato riavviato." }
        if r.bootNoSpoof { return "Il boot-arg -tsmtlnospoof spegne lo spoofing: queste impostazioni non hanno effetto." }
        if r.spoofState == nil { return "Il kext caricato (versione \(r.kextVersion ?? "?")) non ha lo spoofing: serve TSMetalEnabler 1.1. Fino ad allora questa sezione non ha effetto." }
        if r.spoofState != "installed" { return "Lo spoofing del kext non è attivo (\(r.spoofState ?? "")): queste impostazioni non hanno effetto." }
        return nil
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.title = "Aggiungi app allo spoofing"
        panel.prompt = "Aggiungi"
        panel.message = "Scegli una o più app: i loro processi vedranno il modello \(model.policy.spoof.model)."
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.begin { response in
            if response == .OK { model.addSpoof(urls: panel.urls) }
        }
    }
}

struct SpoofRow: View {
    var id: String
    var name: String
    var detail: String
    var iconPath: String?
    var decision: Decision
    var isOverridden: Bool
    var canEdit: Bool
    var setOn: (Bool) -> Void
    var reset: () -> Void
    var remove: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if id == "com.apple.WebKit" {
                    Image(systemName: "globe").font(.system(size: 20)).foregroundStyle(.blue).frame(width: 32, height: 32)
                } else {
                    Image(nsImage: AppIcons.icon(id: id, path: iconPath)).resizable().frame(width: 32, height: 32)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.body.weight(.medium)).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            }
            Spacer(minLength: 8)
            Text((decision.on ? "Spoofing attivo" : "Spento") + " · " + (decision.reason == .auto ? "automatico" : decision.reason == .list ? "impostato a mano" : "non impostato"))
                .font(.caption.weight(.medium))
                .foregroundStyle(decision.on ? Color.green : Color.secondary)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background((decision.on ? Color.green : Color.secondary).opacity(0.12), in: Capsule())
                .lineLimit(1)
            Toggle("Spoofing per \(name)", isOn: Binding(get: { decision.on }, set: { setOn($0) }))
                .toggleStyle(.switch).labelsHidden().disabled(!canEdit)
            Menu {
                Button(remove == nil ? "Torna automatico" : "Togli l'impostazione", systemImage: "arrow.uturn.backward") { reset() }
                    .disabled(!isOverridden || !canEdit)
                if let remove {
                    Divider()
                    Button("Rimuovi dall'elenco", systemImage: "trash", role: .destructive) { remove() }.disabled(!canEdit)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden).fixedSize()
            .help("Altre azioni")
        }
        .padding(.vertical, 2)
    }
}
