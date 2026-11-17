// "Log" section: live stream of the driver's messages (everything but "stats"), with history on open.
import AppKit
import SwiftUI

enum HistoryWindow: String, CaseIterable, Identifiable {
    case m10 = "10m", h1 = "1h", d1 = "1d"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .m10: "ultimi 10 minuti"
        case .h1: "ultima ora"
        case .d1: "ultimo giorno"
        }
    }
    var menuTitle: String {
        switch self {
        case .m10: "Ultimi 10 minuti"
        case .h1: "Ultima ora"
        case .d1: "Ultimo giorno"
        }
    }
    var seconds: TimeInterval {
        switch self {
        case .m10: 600
        case .h1: 3600
        case .d1: 86400
        }
    }
}

final class LogModel: ObservableObject {
    @Published private(set) var entries: [LogEntry] = [] { didSet { summarize() } }   // oldest first
    private(set) var counts: [LogFilter: Int] = [:]
    private(set) var processes: [String] = []
    @Published private(set) var pendingCount = 0
    @Published private(set) var historyLoading = false
    @Published private(set) var streaming = false
    @Published var paused = false { didSet { if !paused { flush() } } }
    @Published var filters: Set<LogFilter> = Set(LogFilter.allCases)
    @Published var search = ""
    @Published var process: String? = nil
    @Published var history: HistoryWindow = .h1 { didSet { if oldValue != history { reloadHistory() } } }

    static let cap = 5000
    private var stream: LogProcess?
    private var incoming: [LogEntry] = []
    private let lock = NSLock()
    private var flushTimer: Timer?
    private var historyGeneration = 0

    func start() {
        guard stream == nil else { return }
        let s = LogProcess(arguments: LogProcess.streamArgs(predicate: LogParser.predicate(excludingStats: true)), onLine: { [weak self] line in
            guard let self, let e = LogParser.parse(line), e.category != .stats else { return }
            self.lock.lock(); self.incoming.append(e); self.lock.unlock()
        }, onExit: { [weak self] _ in DispatchQueue.main.async { self?.streaming = false } })
        streaming = s.start()
        stream = s
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.flush() }
        RunLoop.main.add(t, forMode: .common)
        flushTimer = t
        reloadHistory()
    }

    /// Publishes only when something changed: every publish re-renders the whole table.
    private func flush() {
        lock.lock()
        if paused {
            let n = incoming.count
            lock.unlock()
            if n != pendingCount { pendingCount = n }
            return
        }
        let new = incoming
        incoming.removeAll()
        lock.unlock()
        if pendingCount != 0 { pendingCount = 0 }
        guard !new.isEmpty else { return }
        entries.append(contentsOf: new)
        if entries.count > LogModel.cap { entries.removeFirst(entries.count - LogModel.cap) }
    }

    func reloadHistory() {
        historyGeneration += 1
        let gen = historyGeneration
        historyLoading = true
        let window = history.rawValue
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let out = Shell.run(Paths.logTool, LogProcess.showArgs(predicate: LogParser.predicate(excludingStats: true), last: window))
            let hist = out.split(separator: "\n").compactMap { LogParser.parse($0) }.filter { $0.category != .stats }
            DispatchQueue.main.async {
                guard let self, gen == self.historyGeneration else { return }
                self.historyLoading = false
                // Merge with what the stream already delivered, dropping the overlap.
                struct Key: Hashable { let d: Date; let pid: Int; let m: String }
                let since = Date().addingTimeInterval(-self.history.seconds)
                let live = self.entries.filter { $0.date >= since }
                var seen = Set<Key>()
                var merged: [LogEntry] = []
                for e in (hist + live).sorted(by: { $0.date < $1.date }) where seen.insert(Key(d: e.date, pid: e.pid, m: e.message)).inserted {
                    merged.append(e)
                }
                self.entries = Array(merged.suffix(LogModel.cap))
            }
        }
    }

    func clear() {
        lock.lock(); incoming.removeAll(); lock.unlock()
        entries.removeAll()
        pendingCount = 0
    }

    private func summarize() {
        var c: [LogFilter: Int] = [:]
        var p = Set<String>()
        for e in entries {
            if let f = LogFilter.of(e.category) { c[f, default: 0] += 1 }
            p.insert(e.process)
        }
        counts = c
        processes = p.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func count(_ f: LogFilter) -> Int { counts[f] ?? 0 }

    /// Newest first.
    var visible: [LogEntry] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return entries.reversed().filter { e in
            guard let f = LogFilter.of(e.category), filters.contains(f) else { return false }
            if let process, e.process != process { return false }
            if !q.isEmpty, !e.message.localizedCaseInsensitiveContains(q), !e.process.localizedCaseInsensitiveContains(q) { return false }
            return true
        }
    }
}

extension LogCategory {
    var title: String {
        switch self {
        case .unimplemented: "Non implementata"
        case .error: "Errore"
        case .warning: "Avviso"
        case .general: "Generale"
        case .policy: "Policy"
        case .stats: "Statistiche"
        case .compute: "Compute"
        case .glass: "TeraScale Glass"
        case .swift: "TeraScale Swift"
        case .other: "Altro"
        }
    }

    var icon: String {
        switch self {
        case .unimplemented: "puzzlepiece.extension.fill"
        case .error: "xmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .general: "info.circle.fill"
        case .policy: "switch.2"
        case .stats: "chart.bar.fill"
        case .compute: "cpu.fill"
        case .glass: "drop.halffull"
        case .swift: "swift"
        case .other: "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .unimplemented: .purple
        case .error: .red
        case .warning: .orange
        case .general: .blue
        case .policy: .teal
        case .compute: .indigo
        case .glass: .cyan
        case .swift: .orange
        case .stats, .other: .secondary
        }
    }
}

extension LogFilter {
    var icon: String {
        switch self {
        case .warning: LogCategory.warning.icon
        case .unimplemented: LogCategory.unimplemented.icon
        case .error: LogCategory.error.icon
        case .general: LogCategory.general.icon
        case .compute: LogCategory.compute.icon
        case .glass: LogCategory.glass.icon
        case .swift: LogCategory.swift.icon
        }
    }
    var color: Color {
        switch self {
        case .warning: .orange
        case .unimplemented: .purple
        case .error: .red
        case .general: .blue
        case .compute: .indigo
        case .glass: .cyan
        case .swift: .orange
        }
    }
}

struct LogView: View {
    @ObservedObject var model: LogModel
    @State private var selection = Set<LogEntry.ID>()

    var body: some View {
        let rows = model.visible
        Table(rows, selection: $selection) {
            TableColumn("Ora") { e in
                Text(e.timeString).monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 86, ideal: 92, max: 110)
            TableColumn("Tipo") { e in
                Label {
                    Text(e.category.title)
                } icon: {
                    Image(systemName: e.category.icon).foregroundStyle(e.category.color)
                }
            }
            .width(min: 152, ideal: 158, max: 190)
            TableColumn("Processo") { e in
                Text(verbatim: "\(e.process) [\(e.pid)]").lineLimit(1).help(Text(verbatim: "\(e.process), pid \(e.pid)"))
            }
            .width(min: 90, ideal: 150, max: 260)
            TableColumn("Messaggio") { e in
                Text(e.message)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(e.category == .error ? Color.red : Color.primary)
                    .lineLimit(1).truncationMode(.tail)
                    .help(e.message)
            }
        }
        .contextMenu(forSelectionType: LogEntry.ID.self) { ids in
            Button("Copia") { copy(ids, from: rows) }.disabled(ids.isEmpty)
        }
        .onCopyCommand { copyProviders(rows) }
        .overlay {
            if rows.isEmpty && !model.historyLoading {
                ContentUnavailableView {
                    Label(model.entries.isEmpty ? "Nessun messaggio dallo shim" : "Nessun messaggio con questi filtri",
                          systemImage: "text.page.slash")
                } description: {
                    Text(model.entries.isEmpty
                         ? "Qui compaiono in diretta gli avvisi, le funzioni non implementate e gli errori del driver Metal, insieme allo storico (\(model.history.title))."
                         : "Cambia i filtri o la ricerca per vedere altri messaggi.")
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { filterBar }
        .safeAreaInset(edge: .bottom, spacing: 0) { statusBar(visible: rows.count) }
        .searchable(text: $model.search, placement: .toolbar, prompt: "Cerca nei messaggi")
        .navigationTitle("Log")
        .navigationSubtitle("com.terascale.mtlshim")
        .toolbar {
            ToolbarItem {
                Menu {
                    Picker("Storico da caricare", selection: $model.history) {
                        ForEach(HistoryWindow.allCases) { h in Text(h.menuTitle).tag(h) }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Button("Ricarica lo storico", systemImage: "arrow.clockwise") { model.reloadHistory() }
                } label: {
                    Label("Storico", systemImage: "clock.arrow.circlepath")
                }
                .help("Messaggi già registrati da caricare (\(model.history.title))")
            }
            ToolbarItemGroup {
                Button {
                    model.paused.toggle()
                } label: {
                    Label(model.paused ? "Riprendi" : "Pausa", systemImage: model.paused ? "play.fill" : "pause.fill")
                }
                .help(model.paused ? "Riprendi il flusso in diretta" : "Metti in pausa il flusso in diretta")
                Button {
                    copy(selection, from: rows)
                } label: {
                    Label("Copia", systemImage: "doc.on.doc")
                }
                .disabled(selection.isEmpty)
                .help("Copia le righe selezionate")
                Button {
                    selection.removeAll()
                    model.clear()
                } label: {
                    Label("Svuota", systemImage: "trash")
                }
                .help("Svuota l'elenco")
            }
        }
        .onAppear { model.start() }
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(LogFilter.allCases) { f in
                        FilterChip(filter: f, count: model.count(f), isOn: Binding(
                            get: { model.filters.contains(f) },
                            set: { on in if on { model.filters.insert(f) } else { model.filters.remove(f) } }))
                    }
                }
            }
            Spacer(minLength: 8)
            Picker("Processo", selection: $model.process) {
                Text("Tutti i processi").tag(String?.none)
                Divider()
                ForEach(model.processes, id: \.self) { p in Text(p).tag(String?.some(p)) }
            }
            .labelsHidden()
            .fixedSize()
            .help("Mostra solo un processo")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func statusBar(visible: Int) -> some View {
        HStack(spacing: 8) {
            Circle().fill(model.paused ? Color.orange : model.streaming ? Color.green : Color.secondary).frame(width: 8, height: 8)
            Text(model.paused ? "In pausa" + (model.pendingCount > 0 ? " · \(model.pendingCount) nuovi in attesa" : "")
                 : model.streaming ? "In diretta" : "Flusso fermo")
            Text("·").foregroundStyle(.tertiary)
            Text("\(visible) di \(model.entries.count) righe (max \(LogModel.cap))").monospacedDigit()
            Spacer()
            if model.historyLoading {
                ProgressView().controlSize(.small)
                Text("Carico lo storico (\(model.history.title))…")
            } else {
                Text("Storico: \(model.history.title) · più recenti in alto")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func selectedLines(_ ids: Set<LogEntry.ID>, from rows: [LogEntry]) -> String {
        rows.filter { ids.contains($0.id) }.reversed().map(\.line).joined(separator: "\n")
    }

    private func copy(_ ids: Set<LogEntry.ID>, from rows: [LogEntry]) {
        let text = selectedLines(ids, from: rows)
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func copyProviders(_ rows: [LogEntry]) -> [NSItemProvider] {
        let text = selectedLines(selection, from: rows)
        return text.isEmpty ? [] : [NSItemProvider(object: text as NSString)]
    }
}

struct FilterChip: View {
    var filter: LogFilter
    var count: Int
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: filter.icon)
                    .foregroundStyle(isOn ? filter.color : Color.secondary)
                Text(filter.title)
                Text("\(count)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(isOn ? Color.primary : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(isOn ? .regular.tint(filter.color.opacity(0.22)).interactive() : .regular.interactive(), in: .capsule)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .help(isOn ? "Nascondi: \(filter.title)" : "Mostra: \(filter.title)")
    }
}
