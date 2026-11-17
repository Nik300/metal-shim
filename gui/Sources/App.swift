// Entry point: CLI mode when the first argument is a tsmtl subcommand, otherwise the SwiftUI app.
import AppKit
import SwiftUI

@main
struct Entry {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if CLI.isCLI(args) { exit(CLI.run(args)) }
        LaunchOptions.parse(args)
        SwiftControl.startInThisApp()   // TeraScale Swift before SwiftUI builds the first views
        TeraScaleMetalApp.main()
    }
}

/// Hidden launch arguments (used for testing and by `tsmtl gui --section log`).
enum LaunchOptions {
    static var section: SidebarItem = .gpu
    static var appearance: NSAppearance.Name?
    static var size = CGSize(width: 1120, height: 760)
    static var sizeGiven = false
    static var about = false

    static func parse(_ args: [String]) {
        about = args.contains("--about")
        for (i, a) in args.enumerated() where i + 1 < args.count {
            if a == "--section", let s = SidebarItem(rawValue: args[i + 1]) { section = s }
            if a == "--appearance" { appearance = args[i + 1] == "dark" ? .darkAqua : .aqua }
            if a == "--size" {
                let p = args[i + 1].split(separator: "x").compactMap { Double($0) }
                if p.count == 2 { size = CGSize(width: p[0], height: p[1]); sizeGiven = true }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let a = LaunchOptions.appearance { NSApp.appearance = NSAppearance(named: a) }
        if LaunchOptions.sizeGiven {
            // A restored window frame wins over defaultSize: apply the requested size explicitly.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NSApp.windows.first { $0.isVisible && $0.styleMask.contains(.titled) }?.setContentSize(LaunchOptions.size)
            }
        }
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let s = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            s.setEventHandler { NSApp.terminate(nil) }
            s.resume()
            signalSources.append(s)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        StatsLease.shared.stopNow()   // state 0 + post: the bundle stops writing stats lines
        LogProcess.stopAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct TeraScaleMetalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("TeraScale Metal", id: "main") {
            ContentView()
        }
        .defaultSize(LaunchOptions.size)
        .commands { AboutCommand() }

        Window("Informazioni su TeraScale Metal", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}

struct AboutCommand: Commands {
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("Informazioni su TeraScale Metal") { openWindow(id: "about") }
        }
    }
}

// MARK: - Navigation

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case gpu, log, apps, spoof, status, glass, compute, swift
    var id: String { rawValue }

    var title: String {
        switch self {
        case .gpu: "GPU"
        case .log: "Log"
        case .apps: "App"
        case .spoof: "Spoofing"
        case .status: "Stato"
        case .glass: "TeraScale Glass"
        case .compute: "TeraScale Compute"
        case .swift: "TeraScale Swift"
        }
    }

    var icon: String {
        switch self {
        case .gpu: "gauge.with.dots.needle.50percent"
        case .log: "list.bullet.rectangle"
        case .apps: "square.grid.2x2"
        case .spoof: "theatermasks"
        case .status: "checkmark.seal"
        case .glass: "drop.halffull"
        case .compute: "cpu"
        case .swift: "swift"
        }
    }
}

struct ContentView: View {
    @State private var selection: SidebarItem? = LaunchOptions.section
    @StateObject private var gpu = GPUModel()
    @StateObject private var logs = LogModel()
    @StateObject private var apps = AppsModel()
    @StateObject private var status = StatusModel()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Monitor") {
                    ForEach([SidebarItem.gpu, .log]) { item in
                        Label(item.title, systemImage: item.icon).tag(item)
                    }
                }
                Section("Impostazioni") {
                    ForEach([SidebarItem.apps, .spoof, .status]) { item in
                        Label(item.title, systemImage: item.icon).tag(item)
                    }
                }
                Section("Sistema") {
                    ForEach([SidebarItem.glass, .compute, .swift]) { item in
                        Label(item.title, systemImage: item.icon).tag(item)
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { SidebarHeader() }
            .safeAreaInset(edge: .bottom, spacing: 0) { SidebarFooter(report: status.report) }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 300)
        } detail: {
            switch selection ?? .gpu {
            case .gpu: GPUView(model: gpu)
            case .log: LogView(model: logs)
            case .apps: AppsView(model: apps)
            case .spoof: SpoofView(model: apps, status: status)
            case .status: StatusView(model: status)
            case .glass: GlassView(status: status)
            case .compute: ComputeView(model: apps, status: status)
            case .swift: SwiftAccelView()
            }
        }
        .frame(minWidth: 940, minHeight: 620)
        .onAppear {
            gpu.start()
            status.refresh()
            if LaunchOptions.about { openWindow(id: "about") }
        }
    }
}

// MARK: - Branding

enum Brand {
    /// gui/logo/logo-1024.png copied into the bundle by build.sh (optional).
    static let logo: NSImage? = Bundle.main.url(forResource: "logo-1024", withExtension: "png").flatMap(NSImage.init(contentsOf:))
}

struct LogoView: View {
    var size: CGFloat

    var body: some View {
        if let logo = Brand.logo {
            Image(nsImage: logo).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.86, green: 0.17, blue: 0.16), Color(red: 0.55, green: 0.05, blue: 0.12)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Image(systemName: "cpu").font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white))
                .frame(width: size, height: size)
        }
    }
}

struct SidebarHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            LogoView(size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text("TeraScale Metal").font(.headline)
                Text("Metal su OpenGL 4.1").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }
}

struct SidebarFooter: View {
    var report: StatusReport?

    var body: some View {
        let (text, state): (String, StatusState) = {
            guard let r = report else { return ("Verifica in corso…", .unknown) }
            if r.installed { return ("Shim attivo", .ok) }
            if r.kextLoaded || r.bundleInstalled || r.pluginActive { return ("Installazione incompleta", .warning) }
            return ("Shim non installato", .off)
        }()
        HStack(spacing: 8) {
            Image(systemName: state.icon).foregroundStyle(state.color)
            Text(text).font(.callout)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .padding(12)
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            LogoView(size: 112)
            Text("TeraScale Metal").font(.title.weight(.semibold))
            Text("Versione \(CLI.appVersion)").font(.callout).foregroundStyle(.secondary)
            Text("Driver Metal di compatibilità su OpenGL 4.1 per la AMD Radeon HD 6750M (TeraScale 2) di iMac12,1 con macOS 26 Tahoe e OpenCore Legacy Patcher.")
                .multilineTextAlignment(.center)
                .font(.callout)
                .frame(width: 320)
            Text("Monitor e impostazioni dello shim · comando tsmtl")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: 400)
    }
}

// MARK: - Shared components

enum StatusState {
    case ok, warning, error, off, unknown

    var icon: String {
        switch self {
        case .ok: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        case .off: "minus.circle.fill"
        case .unknown: "circle.dotted"
        }
    }

    var color: Color {
        switch self {
        case .ok: .green
        case .warning: .orange
        case .error: .red
        case .off, .unknown: .secondary
        }
    }
}

struct StatusBadge: View {
    var state: StatusState
    var text: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: state.icon).foregroundStyle(state.color)
        }
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: .rect(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
    }
}

/// App icons by bundle id, cached (LaunchServices lookups are not free).
enum AppIcons {
    nonisolated(unsafe) private static var cache: [String: NSImage] = [:]

    static func icon(id: String, path: String? = nil) -> NSImage {
        if let i = cache[id] { return i }
        let existing = path.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }
        let i = id.hasPrefix("proc:") && existing == nil
            ? NSWorkspace.shared.icon(for: .unixExecutable)
            : AppIdentity.icon(path: existing ?? AppIdentity.locate(id: id))
        cache[id] = i
        return i
    }
}
