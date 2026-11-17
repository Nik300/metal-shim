// GPU statistics from the Radeon's IOAccelerator, and the Darwin-notify lease that turns on the
// bundle's per-process "stats" lines.
//
// Measured on this iMac (macOS 26.7.1, AMDRadeonX3000): "PerformanceStatistics" is reset on every
// read by any process (each read returns what accumulated since the previous reader), while
// "PerformanceStatisticsAccum" holds the same running totals and is NOT reset by reading it. So we
// read the Accum dictionary and take deltas; a negative delta means someone else read
// PerformanceStatistics (Activity Monitor, ioreg, ...) and the totals restarted from zero.
// "Device Utilization %" is not a load figure: it reads 100 with the desktop idle and with a 5 %
// synthetic load, so the main load estimate is hardwareWaitTime (ns) per elapsed second.
import Foundation
import IOKit
import notify

struct GPUSample: Identifiable, Codable {
    var id: Date { time }
    var time: Date
    var model: String?
    var load: Double?              // 0...1, hardwareWaitTime delta / elapsed (clamped)
    var driverUtilization: Int?    // "Device Utilization %" as reported (unreliable)
    var vramTotal: Int64?
    var vramFree: Int64?
    var vramInUse: Int64?          // inUseVidMemoryBytes
    var gartUsed: Int64?
    var gartSize: Int64?
    var sysMemInUse: Int64?
    var textures: Int?
    var surfaces: Int?
    var glContexts: Int?
    var swapsPerSec: Double?
    var pm4PerSec: Double?
    var hwWaitMsPerSec: Double?

    // VRAM in use: inUseVidMemoryBytes. vramFreeBytes is not usable for this: on this driver it always
    // equals 256 MB - inUseSysMemoryBytes - 139328 B, i.e. it follows system memory, not VRAM.
    var vramUsed: Int64? {
        if let v = vramInUse { return v }
        guard let t = vramTotal, let f = vramFree else { return nil }
        return max(0, t - f)
    }
}

final class GPUReader {
    private var accel: io_registry_entry_t = 0
    private var model: String?
    private var vramTotal: Int64?
    private var last: (time: TimeInterval, swaps: Int64, pm4: Int64, wait: Int64)?

    init() {
        accel = IOReg.radeonAccelerator()
        if accel != 0 {
            model = IOReg.string(IOReg.search(accel, "model"))
            if let mb = (IOReg.search(accel, "VRAM,totalMB") as? NSNumber)?.int64Value { vramTotal = mb * 1_048_576 }
        }
    }

    deinit { if accel != 0 { IOObjectRelease(accel) } }

    var available: Bool { accel != 0 }

    func read() -> GPUSample? {
        guard accel != 0 else { return nil }
        let accum = IOReg.property(accel, "PerformanceStatisticsAccum") as? [String: Any]
        guard let stats = accum ?? IOReg.property(accel, "PerformanceStatistics") as? [String: Any] else { return nil }
        func i64(_ k: String) -> Int64? { (stats[k] as? NSNumber)?.int64Value }
        let now = ProcessInfo.processInfo.systemUptime
        var s = GPUSample(time: Date(), model: model)
        s.driverUtilization = (stats["Device Utilization %"] as? NSNumber)?.intValue
        s.vramTotal = vramTotal
        s.vramFree = i64("vramFreeBytes")
        s.vramInUse = i64("inUseVidMemoryBytes")
        s.gartUsed = i64("gartUsedBytes")
        s.gartSize = i64("gartSizeBytes")
        s.sysMemInUse = i64("inUseSysMemoryBytes")
        s.textures = i64("textureCount").map(Int.init)
        s.surfaces = i64("surfaceCount").map(Int.init)
        s.glContexts = i64("contextGLCount").map(Int.init)
        let swaps = i64("bufferSwapCount") ?? 0, pm4 = i64("HWChannel PM4 | Commands Completed") ?? 0
        let wait = i64("hardwareWaitTime") ?? 0
        if accum == nil {
            // Reset-on-read dictionary: the values are already "since the previous read".
            if let l = last, now - l.time > 0.05 {
                let dt = now - l.time
                s.swapsPerSec = Double(swaps) / dt
                s.pm4PerSec = Double(pm4) / dt
                s.hwWaitMsPerSec = Double(wait) / 1e6 / dt
            }
        } else if let l = last, now - l.time > 0.05 {
            let dt = now - l.time
            func delta(_ cur: Int64, _ prev: Int64) -> Double { Double(cur >= prev ? cur - prev : cur) }
            s.swapsPerSec = delta(swaps, l.swaps) / dt
            s.pm4PerSec = delta(pm4, l.pm4) / dt
            s.hwWaitMsPerSec = delta(wait, l.wait) / 1e6 / dt
        }
        if let w = s.hwWaitMsPerSec { s.load = min(1, max(0, w / 1000)) }
        last = (now, swaps, pm4, wait)
        return s
    }
}

/// Keeps the stats lease alive: every 2 s state = Unix time + notify_post; on stop state = 0 + post.
final class StatsLease {
    static let shared = StatsLease()
    private var token: Int32 = NOTIFY_TOKEN_INVALID
    private var timer: DispatchSourceTimer?
    private var holders = 0
    private let queue = DispatchQueue(label: "com.terascale.mtlshim.monitor.lease")

    var active: Bool { queue.sync { timer != nil } }

    func acquire() {
        queue.sync {
            holders += 1
            guard timer == nil else { return }
            if token == NOTIFY_TOKEN_INVALID, notify_register_check(Paths.statsNotify, &token) != UInt32(NOTIFY_STATUS_OK) {
                token = NOTIFY_TOKEN_INVALID
                return
            }
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now(), repeating: 2.0, leeway: .milliseconds(100))
            t.setEventHandler { [weak self] in self?.renew() }
            t.resume()
            timer = t
        }
    }

    func release() {
        queue.sync {
            holders = max(0, holders - 1)
            if holders == 0 { stopLocked() }
        }
    }

    /// Ends the lease regardless of holders (app quit, Ctrl-C).
    func stopNow() { queue.sync { holders = 0; stopLocked() } }

    private func renew() {
        guard token != NOTIFY_TOKEN_INVALID else { return }
        notify_set_state(token, UInt64(time(nil)))
        notify_post(Paths.statsNotify)
    }

    private func stopLocked() {
        guard let t = timer else { return }
        t.cancel()
        timer = nil
        if token != NOTIFY_TOKEN_INVALID {
            notify_set_state(token, 0)
            notify_post(Paths.statsNotify)
        }
    }
}
