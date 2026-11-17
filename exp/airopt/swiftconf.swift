import SwiftUI
import Foundation
// Cold protocol-conformance lookups, as AttributeGraph does for each view type (is it Equatable?).
struct V1: View { var body: some View { Text("a") } }
struct V2: View { var body: some View { Text("b").padding() } }
struct P<T> { var t: T }
func t() -> Double { Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1e6 }
func probe(_ name: String, _ x: Any) {
    let a = t(); let r1 = x is any Equatable; let b = t(); let r2 = x is any Equatable; let c = t()
    print(String(format: "%-28@ first %7.3f ms  second %6.3f ms  equatable=%@", name, b - a, c - b, r1 && r2 ? "yes" : "no"))
}
var images: UInt32 = _dyld_image_count()
print("images loaded:", images)
probe("local struct V1", V1())
probe("local struct V2", V2())
probe("generic P<Int>", P(t: 1))
probe("SwiftUI Text", Text("x"))
probe("SwiftUI ModifiedContent", Text("x").padding())
probe("Int (conforms)", 1)
probe("URLRequest", URLRequest(url: URL(string: "http://a")!))
