// "Stato" section: kext, Metal plugin registration on the GPU, driver bundle, configuration folder.
import SwiftUI

final class StatusModel: ObservableObject {
    @Published private(set) var report: StatusReport?
    @Published private(set) var loading = false

    func refresh() {
        guard !loading else { return }
        loading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let r = StatusReport.probe(withCodesign: true)
            DispatchQueue.main.async {
                self?.report = r
                self?.loading = false
            }
        }
    }
}

struct StatusView: View {
    @ObservedObject var model: StatusModel

    var body: some View {
        Group {
            if let r = model.report {
                form(r)
            } else {
                ProgressView("Verifico l'installazione…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Stato")
        .navigationSubtitle(model.report.map { $0.installed ? "Shim installato" : "Shim non installato" } ?? "")
        .toolbar {
            ToolbarItem {
                Button("Aggiorna", systemImage: "arrow.clockwise") { model.refresh() }
                    .disabled(model.loading)
                    .help("Ricontrolla kext, bundle e configurazione")
            }
        }
        .onAppear { model.refresh() }
    }

    private func form(_ r: StatusReport) -> some View {
        Form {
            Section { summary(r) }

            Section("Kext TSMetalEnabler") {
                LabeledContent("Stato") {
                    StatusBadge(state: r.bootOff ? .warning : r.kextLoaded ? .ok : .off,
                                text: r.kextLoaded ? "Caricato" : r.bootOff ? "Spento da -tsmtloff" : "Non caricato")
                }
                if r.kextLoaded {
                    LabeledContent("Versione", value: r.kextVersion ?? "–")
                    LabeledContent("Acceleratore modificato", value: r.kextAcceleratorPatched.map { $0 ? "Sì" : "No" } ?? "–")
                    LabeledContent("Deroga alla library validation", value: r.lvHook.map { $0 == "installed" ? "Attiva" : $0 } ?? "–")
                        .help("TSLVHook: senza deroga il driver si carica solo nelle app senza hardened runtime")
                    LabeledContent("Caricamenti consentiti in deroga", value: r.lvAllowed.map { "\($0)" } ?? "–")
                        .help("Caricamenti del bundle permessi nonostante la library validation (TSLVAllowed)")
                    LabeledContent("Rifiutati (processi critici)", value: r.lvRefused.map { "\($0)" } ?? "–")
                    LabeledContent("Ultimo processo", value: r.lvLastProcess ?? "–")
                    LabeledContent("Spoofing del modello") {
                        StatusBadge(state: r.spoofActive ? .ok : .warning, text: r.spoofState ?? "assente (serve la versione 1.1)")
                    }
                    if r.spoofActive {
                        LabeledContent("Letture falsificate", value: r.spoofCount.map { "\($0)" } ?? "–")
                        LabeledContent("Ultimo processo spoofato", value: r.spoofLastProcess ?? "–")
                    }
                } else {
                    Text("Il kext non è in IORegistry (nessun servizio TSMetalEnabler). Viene iniettato da OpenCore: va copiato in EFI/OC/Kexts e abilitato in config.plist, dopo Lilu.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }

            Section("GPU") {
                LabeledContent("Modello", value: r.gpuModel ?? (r.gpuFound ? "–" : "Non trovata"))
                LabeledContent("VRAM", value: r.vramTotalMB.map { "\($0) MB" } ?? "–")
                LabeledContent("Acceleratore", value: r.acceleratorClass ?? "–")
                LabeledContent("Plugin Metal") {
                    StatusBadge(state: r.pluginActive ? .ok : .off,
                                text: r.pluginActive ? "Registrato" : "Non registrato")
                }
                mono("MetalPluginName", r.metalPluginName ?? "assente")
                mono("MetalPluginClassName", r.metalPluginClassName ?? "assente")
            }

            Section("Bundle del driver") {
                LabeledContent("Stato") {
                    StatusBadge(state: r.bundleInstalled ? .ok : .off, text: r.bundleInstalled ? "Installato" : "Non installato")
                }
                mono("Percorso", r.bundlePath)
                if r.bundleInstalled {
                    LabeledContent("Identificatore", value: r.bundleId ?? "–")
                    LabeledContent("Versione", value: r.bundleVersion ?? "–")
                    mono("CDHash", r.bundleCDHash ?? "–")
                }
            }

            Section("Configurazione") {
                LabeledContent("Cartella") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(r.configDir).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                        if r.configFromEnv { Text("da TSMTL_CONFIG_DIR").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                LabeledContent("Stato") {
                    StatusBadge(state: !r.configDirExists ? .off : r.configDirWritable ? .ok : .warning,
                                text: !r.configDirExists ? "Assente" : r.configDirWritable ? "Presente e scrivibile" : "Presente ma non scrivibile")
                }
                LabeledContent("policy.plist") {
                    if let e = r.policyError {
                        StatusBadge(state: .error, text: "Illeggibile").help(e)
                    } else {
                        Text(r.policyExists ? "Presente" : "Assente: valori predefiniti")
                    }
                }
                LabeledContent("Automatico su tutte le app", value: r.autoEnable ? "Sì" : "No")
                LabeledContent("App nell'elenco", value: "\(r.policyEntries)")
            }

            Section("Avvio") {
                LabeledContent("Boot-arg dello shim") {
                    if r.bootOff || r.bootNoLV || r.bootNoSpoof {
                        VStack(alignment: .trailing, spacing: 2) {
                            if r.bootOff { Text("-tsmtloff: kext spento").foregroundStyle(.orange) }
                            if r.bootNoLV { Text("-tsmtlnolv: nessuna deroga alla library validation").foregroundStyle(.orange) }
                            if r.bootNoSpoof { Text("-tsmtlnospoof: nessuno spoofing").foregroundStyle(.orange) }
                        }
                    } else {
                        Text("Nessuno")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func summary(_ r: StatusReport) -> some View {
        let missing = [r.kextLoaded ? nil : "il kext TSMetalEnabler",
                       r.pluginActive ? nil : "la registrazione del plugin sulla Radeon",
                       r.bundleInstalled ? nil : "il bundle TeraScaleMTLDriver"].compactMap { $0 }
            + (r.configDirExists ? [] : ["la cartella di configurazione"])
        let systemParts = [r.kextLoaded, r.pluginActive, r.bundleInstalled].filter { $0 }.count
        let state: StatusState = r.installed ? .ok : (systemParts > 0 ? .warning : .off)
        let title = r.installed ? "Lo shim è installato e attivo"
            : systemParts == 0 ? "Lo shim non è ancora installato" : "Installazione incompleta"
        let text = r.installed
            ? "Le app nelle cartelle Applicazioni vedono un device Metal secondo la policy della sezione App."
            : "Manca: " + ListFormatter.localizedString(byJoining: missing) + ". Finché non è installato le app si comportano come oggi (nessun device Metal); qui puoi già controllare la GPU e il log."
        return HStack(alignment: .top, spacing: 14) {
            Image(systemName: r.installed ? "checkmark.seal.fill" : state == .warning ? "exclamationmark.triangle.fill" : "shippingbox")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(state == .off ? Color.secondary : state.color)
                .frame(width: 48, height: 48)
                .glassEffect(.regular, in: .circle)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title3.weight(.semibold))
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
    }
}

private func mono(_ label: String, _ value: String) -> some View {
    LabeledContent(label) {
        Text(value).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
    }
}
