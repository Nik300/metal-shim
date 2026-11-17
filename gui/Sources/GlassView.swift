// "TeraScale Glass" section (Sistema): Apple's glass shader inside Moraea's OpenGL compositor in WindowServer
// ("System.Glass" in policy.plist, docs/PIANO-GLASS.md). A system feature: it acts on WindowServer, not on an app.
import AppKit
import SwiftUI

@MainActor
final class GlassModel: ObservableObject {
    @Published private(set) var report = GlassReport()
    @Published var error: String?

    func refresh(kextVersion: String?) { report = GlassReport.probe(kextVersion: kextVersion) }

    func perform(_ action: () throws -> Void, kextVersion: String?) {
        do { try action() } catch { self.error = error.localizedDescription }
        refresh(kextVersion: kextVersion)
    }
}

struct GlassView: View {
    @ObservedObject var status: StatusModel
    @StateObject private var model = GlassModel()
    @State private var confirmOn = false
    private let trialMinutes = 15

    var body: some View {
        let g = model.report
        let kext = status.report?.kextVersion
        Form {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "drop.halffull")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.tint)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.tint(.accentColor.opacity(0.18)), in: .circle)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TeraScale Glass").font(.title3.weight(.semibold))
                        Text("Il vetro delle finestre (pannelli Liquid Glass, barre laterali) lo disegna WindowServer con il compositore OpenGL di OCLP/Moraea, che ne usa un'imitazione. TeraScale Glass lascia tutto com'è e cambia solo lo shader del vetro: al suo posto gira quello di Apple, preso da QuartzCore e tradotto dallo shim. Nel laboratorio il risultato coincide con il renderer Metal di Apple (0,7% dei pixel diversi di più di 8/255, contro il 19% di Moraea).")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 6)
            }

            if let banner = banner(g, kext: kext) {
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
                        Text("Vetro di Apple in WindowServer").font(.headline)
                        Text(g.summary).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Toggle("Vetro di Apple in WindowServer", isOn: Binding(get: { g.policy.enabled && !g.killSwitch && !g.trialExpired }, set: { on in
                        if on { confirmOn = true } else { model.perform({ try GlassControl.off(reason: "spento dall'app") }, kextVersion: kext) }
                    }))
                    .toggleStyle(.switch).controlSize(.large).labelsHidden()
                }
                .padding(.vertical, 4)
                HStack {
                    Button("Prova per \(trialMinutes) minuti", systemImage: "timer") {
                        model.perform({ _ = try GlassControl.trial(minutes: trialMinutes) }, kextVersion: kext)
                    }
                    if g.trialActive {
                        Button("Tieni acceso", systemImage: "checkmark.circle") { model.perform({ try GlassControl.on() }, kextVersion: kext) }
                    }
                    Spacer()
                    Button("Ripristina il vetro di Moraea", systemImage: "arrow.uturn.backward", role: .destructive) {
                        model.perform({ try GlassControl.off(reason: "ripristinato dall'app") }, kextVersion: kext)
                    }
                    .disabled(!g.policy.enabled && g.killSwitch)
                }
            } footer: {
                Label("Spegnere vale subito, senza riavvio: il componente controlla l'interruttore ogni secondo. Accendere vale dal prossimo avvio di WindowServer, cioè dal prossimo riavvio del Mac (il logout non lo riavvia). Anche senza l'app: tsmtl glass off, oppure via SSH touch \(Paths.glassKill). Se WindowServer si riavvia tre volte in due minuti, il componente si spegne da solo.",
                      systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Stato") {
                LabeledContent("Componente in WindowServer") {
                    StatusBadge(state: g.active ? .ok : g.componentRunning ? .warning : .off,
                                text: g.active ? "attivo, \(g.replaced) programmi" : g.componentRunning ? (g.status["State"] as? String ?? "?") : "non caricato")
                }
                if let t = g.policy.trialDeadline {
                    LabeledContent("Prova", value: (g.trialActive ? "fino alle " : "scaduta alle ") + DateFormatter.localizedString(from: t, dateStyle: .none, timeStyle: .short))
                }
                LabeledContent("Kext") {
                    StatusBadge(state: g.kextReady ? .ok : .warning, text: g.kextVersion.map { g.kextReady ? $0 : "\($0): serve 1.2" } ?? "non caricato")
                }
                LabeledContent("Shader di Apple") {
                    StatusBadge(state: g.snippetPresent ? .ok : .warning,
                                text: g.snippetPresent ? "pronti\((g.snippetInfo["Translator"] as? String).map { ", traduttore \($0)" } ?? "")" : "da generare")
                }
                LabeledContent("Interruttore") {
                    StatusBadge(state: g.killSwitch ? .off : .ok, text: g.killSwitch ? (g.killReason ?? "presente") : "assente")
                }
                LabeledContent("Crash di WindowServer (24 ore)") {
                    StatusBadge(state: g.recentCrashes.isEmpty ? .ok : .warning, text: g.recentCrashes.isEmpty ? "nessuno" : "\(g.recentCrashes.count)")
                }
            }
        }
        .formStyle(.grouped)
        .alert("Accendere TeraScale Glass?", isPresented: $confirmOn) {
            Button("Prova per \(trialMinutes) minuti") { model.perform({ _ = try GlassControl.trial(minutes: trialMinutes) }, kextVersion: kext) }
            Button("Accendi") { model.perform({ try GlassControl.on() }, kextVersion: kext) }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Il driver entrerà in WindowServer, il processo che disegna tutto lo schermo: se qualcosa va storto si torna alla finestra di login. Con la prova, dopo \(trialMinutes) minuti torna da solo il vetro di Moraea se non scegli «Tieni acceso».")
        }
        .alert("Impossibile salvare la policy", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.error ?? "")
        }
        .navigationTitle("TeraScale Glass")
        .navigationSubtitle(g.active ? "attivo" : g.policy.enabled ? "acceso nella policy" : "spento")
        .toolbar {
            ToolbarItem {
                Button("Aggiorna", systemImage: "arrow.clockwise") { status.refresh(); model.refresh(kextVersion: kext) }
                    .help("Rileggi la policy e lo stato del componente")
            }
        }
        .onAppear {
            if status.report == nil { status.refresh() }
            model.refresh(kextVersion: kext)
        }
        .onChange(of: status.report?.kextVersion) { _, v in model.refresh(kextVersion: v) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refresh(kextVersion: kext) }
    }

    private func banner(_ g: GlassReport, kext: String?) -> String? {
        if !FileManager.default.isWritableFile(atPath: Paths.configDir) { return "La cartella \(Paths.configDir) non è scrivibile dal tuo utente: TeraScale Glass non si può impostare." }
        if !g.snippetPresent { return "Mancano gli shader di Apple tradotti: zsh metal-shim/system/glass.sh prepare (senza sudo)." }
        if kext != nil && !g.kextReady { return "Il kext caricato è il \(kext!): per far entrare il driver in WindowServer serve il kext 1.2 (zsh metal-shim/system/glass.sh kext, poi riavvio)." }
        if !g.recentCrashes.isEmpty && g.policy.enabled { return "WindowServer è andato in crash \(g.recentCrashes.count) volte nelle ultime 24 ore: se è successo con TeraScale Glass acceso, spegnilo e guarda tsmtl log --filter glass." }
        return nil
    }
}
