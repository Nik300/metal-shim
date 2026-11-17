# gen-conf.py [N]: writes conf.swift, the cold conformance-lookup bench (N non-Equatable structs + N generic instantiations).
# Build: xcrun swiftc -O conf.swift -o conf_ns (about 5 minutes on this iMac). Run: ./conf_ns plain,gen,again
# With SwiftUI's records too: DYLD_INSERT_LIBRARIES=/System/Library/Frameworks/SwiftUI.framework/SwiftUI ./conf_ns plain,gen
import sys
N = int(sys.argv[1]) if len(sys.argv) > 1 else 2000
L = ['import Foundation', 'import MachO', '#if UI', 'import SwiftUI', '#endif',
     'func now() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }']
for i in range(N): L.append(f'struct S{i} {{ var a: Int = {i} }}')
L.append('struct G<T> { var t: T }')
for i in range(N): L.append(f'enum E{i} {{ case a }}')
L.append('let plain: [Any] = [' + ','.join(f'S{i}()' for i in range(N)) + ']')
L.append('let gen: [Any] = [' + ','.join(f'G(t: E{i}.a)' for i in range(N)) + ']')
L.append('''
var inCache = 0, outCache = 0, imgs = 0
for i in 0..<_dyld_image_count() {
    guard let h = _dyld_get_image_header(i) else { continue }
    var size: UInt = 0
    let p = h.withMemoryRebound(to: mach_header_64.self, capacity: 1) { getsectiondata($0, "__TEXT", "__swift5_proto", &size) }
    if p == nil { continue }
    imgs += 1
    if (h.pointee.flags & 0x80000000) != 0 { inCache += Int(size) / 4 } else { outCache += Int(size) / 4 }
}
print("images \\(_dyld_image_count()), with conformances \\(imgs), records shared cache \\(inCache), outside \\(outCache)")
func run(_ name: String, _ xs: [Any]) {
    var ts: [Double] = []
    let t0 = now()
    for x in xs { let a = now(); let r = x is any Equatable; ts.append(Double(now() - a) / 1e6); if r { print("??") } }
    let tot = Double(now() - t0) / 1e6
    let s = ts.sorted()
    print(String(format: "%-8@ n=%d total %.0f ms  median %.3f  p10 %.3f  p90 %.3f ms", name, xs.count, tot, s[s.count/2], s[s.count/10], s[s.count*9/10]))
}
let which = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "plain,gen"
if which.contains("plain") { run("plain", plain) }
if which.contains("gen") { run("generic", gen) }
if which.contains("again") { run("again", plain) }
''')
open('conf.swift', 'w').write('\n'.join(L))
