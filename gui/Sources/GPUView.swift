// "GPU" section: live IOAccelerator statistics with 2-minute charts, and the per-app shim stats table.
import Charts
import SwiftUI

final class GPUModel: ObservableObject {
    @Published private(set) var samples: [GPUSample] = []
    @Published private(set) var latest: GPUSample?
    @Published private(set) var rows: [AppStatsRow] = []
    @Published private(set) var statsActive = false

    let reader = GPUReader()
    private var timer: Timer?
    private let aggregator = StatsAggregator()   // main thread only
    private var stream: LogProcess?
    static let window: TimeInterval = 120

    func start() {
        guard timer == nil else { return }
        tick()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        if let s = reader.read() {
            latest = s
            samples.append(s)
            let cutoff = s.time.addingTimeInterval(-GPUModel.window - 2)
            if let first = samples.firstIndex(where: { $0.time >= cutoff }), first > 0 { samples.removeFirst(first) }
        }
        rows = aggregator.rows()
    }

    /// Holds the stats lease and streams the "stats" lines while the GPU section is visible.
    func startStats() {
        guard stream == nil else { return }
        let s = LogProcess(arguments: LogProcess.streamArgs(predicate: LogParser.predicate(categories: [.stats]), level: "default")) { [weak self] line in
            guard let e = LogParser.parse(line), e.category == .stats, let st = ShimStats.parse(e.message) else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.aggregator.add(st)
                self.rows = self.aggregator.rows()
            }
        }
        guard s.start() else { return }
        stream = s
        StatsLease.shared.acquire()
        statsActive = true
    }

    func stopStats() {
        guard let s = stream else { return }
        s.stop()
        stream = nil
        StatsLease.shared.release()
        statsActive = false
    }

    func series(_ key: (GPUSample) -> Double?) -> [ChartPoint] {
        let now = latest?.time ?? Date()
        return samples.compactMap { s in key(s).map { ChartPoint(t: s.time.timeIntervalSince(now), v: $0) } }
    }
}

struct ChartPoint: Identifiable {
    var id: Double { t }
    var t: Double   // seconds relative to the latest sample (<= 0)
    var v: Double
}

struct GPUView: View {
    @ObservedObject var model: GPUModel

    var body: some View {
        Group {
            if !model.reader.available {
                ContentUnavailableView("Radeon non trovata", systemImage: "exclamationmark.triangle",
                                       description: Text("Nessun IOAccelerator AMD in IORegistry: le statistiche della GPU non sono disponibili."))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 14) {
                            LoadCard(sample: model.latest)
                                .frame(width: 250)
                            MetricChart(title: "Carico · ultimi 2 minuti", subtitle: "stima dal tempo di lavoro dell'hardware",
                                        points: model.series { $0.load.map { $0 * 100 } },
                                        yMax: 100, format: { String(format: "%.0f %%", $0) }, tint: .accentColor, height: 118)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: 3), spacing: 14) {
                            MetricChart(title: "VRAM", subtitle: "allocata dalle app sulla Radeon",
                                        points: model.series { $0.vramUsed.map { Double($0) / 1_048_576 } },
                                        yMax: Double(model.latest?.vramTotal ?? 268_435_456) / 1_048_576,
                                        format: { String(format: "%.0f MB", $0) }, tint: .purple,
                                        valueText: "\(Fmt.rate(model.latest?.vramUsed.map { Double($0) / 1_048_576 })) / \(Fmt.mb(model.latest?.vramTotal))")
                            MetricChart(title: "Swap al secondo", subtitle: "presentazioni completate",
                                        points: model.series { $0.swapsPerSec },
                                        yMax: nil, format: { String(format: "%.1f", $0) }, tint: .teal)
                            MetricChart(title: "Comandi PM4 al secondo", subtitle: "pacchetti eseguiti dalla GPU",
                                        points: model.series { $0.pm4PerSec },
                                        yMax: nil, format: { String(format: "%.0f", $0) }, tint: .orange)
                        }
                        tiles
                        ShimStatsCard(rows: model.rows, active: model.statsActive)
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle("GPU")
        .navigationSubtitle(model.latest?.model ?? "")
        .onAppear { model.startStats() }
        .onDisappear { model.stopStats() }
    }

    private var tiles: some View {
        let s = model.latest
        let gartFrac: Double? = {
            guard let u = s?.gartUsed, let t = s?.gartSize, t > 0 else { return nil }
            return Double(u) / Double(t)
        }()
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: 5), spacing: 14) {
            MetricTile(title: "GART", icon: "arrow.left.arrow.right", value: "\(Fmt.mb(s?.gartUsed)) / \(Fmt.mb(s?.gartSize))",
                       detail: "RAM mappata per la GPU", progress: gartFrac)
            MetricTile(title: "Memoria di sistema", icon: "memorychip", value: Fmt.mb(s?.sysMemInUse),
                       detail: "usata dalla GPU")
            MetricTile(title: "Texture", icon: "photo.stack", value: s?.textures.map { "\($0)" } ?? "–",
                       detail: "allocate sulla Radeon")
            MetricTile(title: "Superfici", icon: "rectangle.on.rectangle", value: s?.surfaces.map { "\($0)" } ?? "–",
                       detail: "IOSurface e drawable")
            MetricTile(title: "Contesti GL", icon: "square.stack.3d.up", value: s?.glContexts.map { "\($0)" } ?? "–",
                       detail: "aperti")
        }
    }
}

struct LoadCard: View {
    var sample: GPUSample?

    var body: some View {
        Card {
            Text("Carico GPU").font(.headline)
            HStack(alignment: .center, spacing: 14) {
                Gauge(value: sample?.load ?? 0) {
                    EmptyView()
                } currentValueLabel: {
                    Text(Fmt.pct(sample?.load)).font(.system(size: 15, weight: .semibold)).monospacedDigit()
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(loadColor)
                .scaleEffect(1.25)
                .frame(width: 76, height: 76)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Fmt.rate(sample?.hwWaitMsPerSec)) ms/s")
                        .font(.title3.weight(.semibold)).monospacedDigit()
                    Text("tempo di lavoro della GPU in ogni secondo")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider()
            HStack(spacing: 4) {
                Text("Valore del driver: \(sample?.driverUtilization.map { "\($0) %" } ?? "–")")
                Image(systemName: "info.circle")
            }
            .font(.caption).foregroundStyle(.secondary)
            .help("Il campo «Device Utilization %» del driver AMD vale 100 anche a GPU quasi ferma: non è una misura del carico. Il carico mostrato è il tempo di attesa dell'hardware (hardwareWaitTime) diviso per il tempo trascorso.")
        }
    }

    private var loadColor: Color {
        let l = sample?.load ?? 0
        return l > 0.85 ? .red : l > 0.6 ? .orange : .accentColor
    }
}

struct MetricTile: View {
    var title: String
    var icon: String
    var value: String
    var detail: String? = nil
    var progress: Double? = nil

    var body: some View {
        Card(padding: 14) {
            Label(title, systemImage: icon).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            // Same height with or without a bar, so tiles line up.
            ProgressView(value: min(1, max(0, progress ?? 0))).progressViewStyle(.linear)
                .tint((progress ?? 0) > 0.9 ? .red : (progress ?? 0) > 0.75 ? .orange : .accentColor)
                .opacity(progress == nil ? 0 : 1)
                .accessibilityHidden(progress == nil)
            Text(detail ?? " ").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                .help(detail ?? "")
        }
    }
}

struct MetricChart: View {
    var title: String
    var subtitle: String? = nil
    var points: [ChartPoint]
    var yMax: Double?
    var format: (Double) -> String
    var tint: Color
    var valueText: String? = nil
    var height: CGFloat = 92
    @State private var hoverT: Double?

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer(minLength: 8)
                Text(valueText ?? points.last.map { format($0.v) } ?? "–")
                    .font(.title3.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            }
            Chart {
                ForEach(points) { p in
                    AreaMark(x: .value("Secondi", p.t), y: .value(title, p.v))
                        .foregroundStyle(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Secondi", p.t), y: .value(title, p.v))
                        .foregroundStyle(tint)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
                if let h = hoverT, let p = points.min(by: { abs($0.t - h) < abs($1.t - h) }) {
                    RuleMark(x: .value("Secondi", p.t)).foregroundStyle(.secondary.opacity(0.5))
                    PointMark(x: .value("Secondi", p.t), y: .value(title, p.v))
                        .symbolSize(60).foregroundStyle(tint)
                        .annotation(position: .top, alignment: .center, spacing: 6,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            Text("\(format(p.v)) · \(Int(-p.t.rounded())) s fa")
                                .font(.caption.weight(.medium)).monospacedDigit()
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.regularMaterial, in: Capsule())
                        }
                }
            }
            .chartXScale(domain: -GPUModel.window...0)
            .chartYScale(domain: 0...max(yMax ?? 0, (points.map(\.v).max() ?? 0) * 1.15, 1))
            .chartXAxis {
                AxisMarks(values: height >= 100 ? [-120, -90, -60, -30, 0] : [-120, -60, 0]) { v in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    if v.as(Double.self) == 0 {
                        AxisValueLabel(anchor: .topTrailing) { Text("ora") }
                    } else {
                        AxisValueLabel { Text(verbatim: "\(Int(v.as(Double.self) ?? 0)) s") }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    AxisValueLabel()
                }
            }
            .chartXSelection(value: $hoverT)
            .frame(height: height)
        }
    }
}

struct ShimStatsCard: View {
    var rows: [AppStatsRow]
    var active: Bool

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                Text("App con lo shim").font(.headline)
                Spacer()
                Label(active ? "statistiche richieste alle app" : "statistiche ferme",
                      systemImage: active ? "dot.radiowaves.left.and.right" : "pause.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if rows.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "app.dashed").font(.title2).foregroundStyle(.tertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nessuna app sta usando lo shim in questo momento.")
                        Text("Le righe compaiono quando un'app avviata con lo shim attivo disegna con Metal; spariscono dopo 5 secondi senza dati.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            } else {
                Grid(alignment: .trailing, horizontalSpacing: 18, verticalSpacing: 8) {
                    GridRow {
                        Text("App").gridColumnAlignment(.leading)
                        Text("FPS"); Text("Draw/s"); Text("GPU"); Text("Upload KB/s"); Text("Pipeline"); Text("Ripieghi"); Text("Memoria")
                    }
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Divider()
                    ForEach(rows) { r in
                        GridRow {
                            HStack(spacing: 8) {
                                Image(nsImage: AppIcons.icon(id: r.app)).resizable().frame(width: 22, height: 22)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(r.name).lineLimit(1)
                                    Text(verbatim: r.pids.count > 1 ? "\(r.app) · \(r.pids.count) processi" : "\(r.app) · pid \(r.pids.first ?? 0)")
                                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            .gridColumnAlignment(.leading)
                            Text(String(format: "%.1f", r.fps))
                            Text(String(format: "%.0f", r.draws))
                            Text(String(format: "%.0f %%", min(1, r.gpuBusy) * 100))
                            Text(String(format: "%.0f", r.uploadKBps))
                            Text(String(format: "%.0f", r.pipelines))
                            Text(String(format: "%.0f", r.fallbacks)).foregroundStyle(r.fallbacks > 0 ? .orange : .primary)
                            Text(String(format: "%.1f MB", r.memMB))
                        }
                        .monospacedDigit()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
