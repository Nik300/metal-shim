// TeraScaleLogo.swift — master source for the "TeraScale Metal" app icon.
//
// A front view of the Mid-2011 21.5" aluminium iMac (iMac12,1) standing on a
// strip of macOS 26 "Liquid Glass", inside the standard macOS icon squircle.
//
// Own vector rendition (no Apple bitmap, no Apple logo). Rendering is done in
// two passes on a 1024-unit, y-down design space:
//   1. per-pixel pass (CPU, Double precision): tile background, the glass
//      strip (refraction with chromatic split, frost, Fresnel, specular rim),
//      and the iMac screen wallpaper;
//   2. CoreGraphics vector pass: contact shadow, iMac body, chin, stand, foot.
// Small icon sizes use a simplified, bolder variant rendered at 1024 and
// downsampled with vImage (Lanczos).
//
// Build:   swiftc -O TeraScaleLogo.swift -o terascale-logo
// Run:     ./terascale-logo <outdir>
//          writes <outdir>/logo-1024.png, <outdir>/AppIcon.iconset/*, <outdir>/preview.png

import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
import Accelerate

// MARK: - Small math helpers

@inline(__always) func clamp(_ v: Double, _ a: Double, _ b: Double) -> Double { min(max(v, a), b) }
@inline(__always) func mix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
@inline(__always) func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
    let t = clamp((x - e0) / (e1 - e0), 0, 1); return t * t * (3 - 2 * t)
}

struct C3 {
    var r: Double, g: Double, b: Double
    init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    init(hex: UInt32) {
        r = Double((hex >> 16) & 0xff) / 255; g = Double((hex >> 8) & 0xff) / 255; b = Double(hex & 0xff) / 255
    }
    static func + (a: C3, b: C3) -> C3 { C3(a.r + b.r, a.g + b.g, a.b + b.b) }
    static func * (a: C3, s: Double) -> C3 { C3(a.r * s, a.g * s, a.b * s) }
    func lerp(_ o: C3, _ t: Double) -> C3 { C3(mix(r, o.r, t), mix(g, o.g, t), mix(b, o.b, t)) }
    /// "screen" blend of a light colour with given strength
    func screen(_ o: C3, _ a: Double) -> C3 {
        C3(r + (1 - r) * o.r * a, g + (1 - g) * o.g * a, b + (1 - b) * o.b * a)
    }
    var luma: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }
    func saturated(_ s: Double) -> C3 { let l = luma; return C3(l + (r - l) * s, l + (g - l) * s, l + (b - l) * s) }
    var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: 1) }
    func cg(_ a: Double) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

@inline(__always) func gauss(_ dx: Double, _ dy: Double, _ rx: Double, _ ry: Double) -> Double {
    exp(-(dx * dx) / (2 * rx * rx) - (dy * dy) / (2 * ry * ry))
}

/// Signed distance to a rounded box (negative inside), all in design units.
@inline(__always) func sdRoundBox(_ x: Double, _ y: Double, _ cx: Double, _ cy: Double,
                                  _ hx: Double, _ hy: Double, _ r: Double) -> Double {
    let qx = abs(x - cx) - hx + r, qy = abs(y - cy) - hy + r
    return hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - r
}

// MARK: - Design parameters

enum Variant { case full, small }

/// Hand-placed geometry for the 16/32 px renditions, in design units. Edges sit on
/// multiples of 64 (16 px grid) or 32 (32 px grid) so a box downsample stays crisp.
struct SmallGeom {
    var body: (x0: Double, y0: Double, x1: Double, y1: Double)
    var panelBottom: Double                       // black glass ends, chin begins
    var screen: (x0: Double, y0: Double, x1: Double, y1: Double)
    var neck: (x0: Double, x1: Double, y0: Double, y1: Double, flare: Double)
    var foot: (x0: Double, x1: Double, y0: Double, y1: Double)
    var glass: (x0: Double, x1: Double, y0: Double, y1: Double)

    // 16 px: rows 3..9 body, 10..11 stand, 12..13 glass
    static let px16 = SmallGeom(body: (192, 192, 832, 640), panelBottom: 576, screen: (256, 224, 768, 512),
                                neck: (448, 576, 640, 736, 24), foot: (384, 640, 736, 768),
                                glass: (160, 864, 768, 896))
    // 32 px: rows 6..19 body, 20..22 stand, 23..26 glass
    static let px32 = SmallGeom(body: (192, 192, 832, 640), panelBottom: 576, screen: (240, 224, 784, 528),
                                neck: (448, 576, 640, 704, 24), foot: (384, 640, 704, 736),
                                glass: (160, 864, 736, 864))
}

struct Design {
    let variant: Variant
    // iMac placement: reference-space body (x 110…912, y 270…845, foot to 966)
    // is mapped with X = cx + (x-511)*s, Y = top + (y-270)*s
    var s: Double
    var cx: Double = 512
    var top: Double
    // Glass strip (capsule), design units
    var gx: Double = 512, gy: Double, ghw: Double, ghh: Double, gr: Double
    var bevel: Double, refraction: Double, chroma: Double, frost: Double
    var lens: Double                 // vertical magnification of what is behind (cylindrical lens)
    var lift: Double                 // milky white added to the glass body
    var glassShadow: Double          // shadow the glass casts on the tile
    var rimWidth: Double, rimTop: Double, rimBottom: Double
    // iMac detail
    var silverRim: Double            // aluminium edge around the black glass (ref units)
    var screenGain: Double           // brightness of the wallpaper
    var detail: Bool                 // camera, seams, sheen, grain
    var geom: SmallGeom? = nil       // grid-snapped geometry (16/32 px only)

    static let full = Design(variant: .full, s: 600.0 / 802.0, top: 196,
                             gy: 0, ghw: 348, ghh: 54, gr: 54,
                             bevel: 30, refraction: 40, chroma: 0.22, frost: 0.25,
                             lens: 1.38, lift: 0.10, glassShadow: 0.34,
                             rimWidth: 2.2, rimTop: 1.0, rimBottom: 0.6,
                             silverRim: 3.5, screenGain: 1.06, detail: true).placed()

    // Bolder variant for 16/32 px: bigger iMac, thicker bezel rim, thicker glass.
    static let small = Design(variant: .small, s: 660.0 / 802.0, top: 150,
                              gy: 0, ghw: 366, ghh: 66, gr: 66,
                              bevel: 36, refraction: 24, chroma: 0.08, frost: 0.6,
                              lens: 1.3, lift: 0.36, glassShadow: 0.62,
                              rimWidth: 12, rimTop: 1.0, rimBottom: 0.7,
                              silverRim: 9, screenGain: 1.25, detail: false).placed()

    /// the strip's top edge sits exactly under the iMac's foot
    func placed() -> Design { var d = self; d.gy = footBottom - 1 + ghh; return d }

    /// bold, grid-snapped variants for 16 px and 32 px
    static func tiny(_ g: SmallGeom, rim: Double, lift: Double) -> Design {
        var d = Design.small
        d.geom = g
        d.gx = (g.glass.x0 + g.glass.x1) / 2; d.gy = (g.glass.y0 + g.glass.y1) / 2
        d.ghw = (g.glass.x1 - g.glass.x0) / 2; d.ghh = (g.glass.y1 - g.glass.y0) / 2; d.gr = d.ghh
        d.bevel = d.ghh * 0.5; d.rimWidth = rim
        d.lift = lift
        return d
    }

    func X(_ x: Double) -> Double { cx + (x - 511) * s }
    func Y(_ y: Double) -> Double { top + (y - 270) * s }
    var footBottom: Double { geom?.foot.y1 ?? Y(966) }
    var screenRect: (x0: Double, y0: Double, x1: Double, y1: Double) { geom?.screen ?? (X(151), Y(308), X(873), Y(714)) }
}

// MARK: - Background (tile) — calm deep blue → violet with soft light

func background(_ x: Double, _ y: Double, _ d: Design) -> C3 {
    let top = C3(hex: 0x1B2C78), bottom = C3(hex: 0x43207A)
    let t = smoothstep(80, 960, y + 0.18 * (x - 512))
    var c = top.lerp(bottom, t)
    // halo behind the iMac so the black bezel separates from the tile
    c = c.screen(C3(hex: 0x6F8CFF), 0.42 * gauss(x - 512, y - 400, 330, 250))
    // soft colour pools that the glass picks up and bends
    c = c.screen(C3(hex: 0xF25BC0), 0.58 * gauss(x - 260, y - 790, 160, 110))
    c = c.screen(C3(hex: 0xFFA052), 0.50 * gauss(x - 620, y - 860, 150, 80))
    c = c.screen(C3(hex: 0x3CD6FF), 0.55 * gauss(x - 840, y - 760, 120, 110))
    // two slow light ribbons crossing behind the strip (they make the refraction legible)
    let band = gauss(0, y - d.gy, 1, 150)
    let r1 = d.gy - 30 + 80 * sin((x - 100) / 824 * .pi * 1.25 + 0.2)
    c = c.screen(C3(hex: 0xD6C8FF), 0.46 * band * exp(-pow((y - r1) / 11, 2)))
    let r2 = d.gy + 40 - 60 * sin((x - 100) / 824 * .pi * 1.6 + 1.0)
    c = c.screen(C3(hex: 0xA6ECFF), 0.30 * band * exp(-pow((y - r2) / 8, 2)))
    // very soft vignette toward the tile corners
    let v = gauss(x - 512, y - 512, 520, 520)
    return c * (0.82 + 0.18 * v)
}

// MARK: - iMac wallpaper (per pixel, u/v in 0…1 over the screen rect)

func wallpaper(_ u: Double, _ v: Double, _ d: Design) -> C3 {
    var c = C3(hex: 0x10205A).lerp(C3(hex: 0x1F45A6), smoothstep(0, 1, v))
    c = c.screen(C3(hex: 0x3FA9FF), 0.75 * gauss(u - 0.30, v - 1.02, 0.42, 0.34))
    c = c.screen(C3(hex: 0xC251E8), 0.55 * gauss(u - 0.86, v - 0.80, 0.30, 0.30))
    c = c.screen(C3(hex: 0x6FD3FF), 0.18 * gauss(u - 0.08, v - 0.15, 0.25, 0.22))
    // understated "hello triangle": soft, RGB-tinted light
    let ax = 0.5, ay = 0.20, bx = 0.335, by = 0.80, cx = 0.665, cy = 0.80
    let px = u, py = v
    // barycentric (screen is 16:9, triangle defined in uv so it looks equilateral-ish)
    let den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
    let w1 = ((by - cy) * (px - cx) + (cx - bx) * (py - cy)) / den
    let w2 = ((cy - ay) * (px - cx) + (ax - cx) * (py - cy)) / den
    let w3 = 1 - w1 - w2
    let inside = min(w1, min(w2, w3))
    let tri = smoothstep(-0.12, 0.08, inside)
    if tri > 0 {
        let tc = C3(1.0, 0.35, 0.45) * max(w1, 0) + C3(0.35, 1.0, 0.55) * max(w2, 0) + C3(0.40, 0.55, 1.0) * max(w3, 0)
        c = c.screen(tc, 0.21 * tri)
    }
    return (c * d.screenGain)
}

// MARK: - Float RGB canvas

struct Canvas {
    let n: Int
    var px: [Double]      // RGB
    init(n: Int) { self.n = n; px = [Double](repeating: 0, count: n * n * 3) }

    @inline(__always) func at(_ i: Int, _ j: Int) -> C3 {
        let o = (j * n + i) * 3; return C3(px[o], px[o + 1], px[o + 2])
    }
    @inline(__always) mutating func set(_ i: Int, _ j: Int, _ c: C3) {
        let o = (j * n + i) * 3; px[o] = c.r; px[o + 1] = c.g; px[o + 2] = c.b
    }
    /// bilinear sample in pixel coordinates (pixel centres at i+0.5), one channel
    @inline(__always) func sample(_ x: Double, _ y: Double, _ ch: Int) -> Double {
        let fx = clamp(x - 0.5, 0, Double(n - 1)), fy = clamp(y - 0.5, 0, Double(n - 1))
        let i0 = Int(fx), j0 = Int(fy), i1 = min(i0 + 1, n - 1), j1 = min(j0 + 1, n - 1)
        let tx = fx - Double(i0), ty = fy - Double(j0)
        let a = px[(j0 * n + i0) * 3 + ch], b = px[(j0 * n + i1) * 3 + ch]
        let c = px[(j1 * n + i0) * 3 + ch], d = px[(j1 * n + i1) * 3 + ch]
        return mix(mix(a, b, tx), mix(c, d, tx), ty)
    }

    func blurred(sigma: Double) -> Canvas {
        let r = max(1, Int(ceil(sigma * 3)))
        var k = [Double](repeating: 0, count: 2 * r + 1)
        var sum = 0.0
        for i in -r...r { k[i + r] = exp(-Double(i * i) / (2 * sigma * sigma)); sum += k[i + r] }
        for i in 0..<k.count { k[i] /= sum }
        var tmp = Canvas(n: n), out = Canvas(n: n)
        for j in 0..<n { for i in 0..<n { for ch in 0..<3 {
            var acc = 0.0
            for t in -r...r { let ii = min(max(i + t, 0), n - 1); acc += k[t + r] * px[(j * n + ii) * 3 + ch] }
            tmp.px[(j * n + i) * 3 + ch] = acc
        } } }
        for j in 0..<n { for i in 0..<n { for ch in 0..<3 {
            var acc = 0.0
            for t in -r...r { let jj = min(max(j + t, 0), n - 1); acc += k[t + r] * tmp.px[(jj * n + i) * 3 + ch] }
            out.px[(j * n + i) * 3 + ch] = acc
        } } }
        return out
    }
}

// MARK: - Pass 1: per-pixel scene (background, glass, wallpaper)

func perPixelScene(n: Int, d: Design) -> Canvas {
    let k = Double(n) / 1024
    var bg = Canvas(n: n)
    for j in 0..<n { for i in 0..<n {
        bg.set(i, j, background((Double(i) + 0.5) / k, (Double(j) + 0.5) / k, d))
    } }
    let frosted = bg.blurred(sigma: 9 * k)
    var out = bg

    let sd = { (x: Double, y: Double) -> Double in sdRoundBox(x, y, d.gx, d.gy, d.ghw, d.ghh, d.gr) }
    let px1 = 1 / k   // one output pixel in design units

    for j in 0..<n { for i in 0..<n {
        let x = (Double(i) + 0.5) / k, y = (Double(j) + 0.5) / k
        // --- soft shadow the glass casts on the tile (below / around it)
        let sh = sdRoundBox(x, y - 16, d.gx, d.gy, d.ghw - 10, d.ghh, d.gr)
        let shadow = d.glassShadow * (1 - smoothstep(-26, 34, sh))
        var c = out.at(i, j) * (1 - shadow)

        let s = sd(x, y)
        let cov = clamp(0.5 - s / px1, 0, 1)
        if cov > 0 {
            // outward normal from the SDF gradient
            let e = 0.75
            var nx = sd(x + e, y) - sd(x - e, y), ny = sd(x, y + e) - sd(x, y - e)
            let nl = max(hypot(nx, ny), 1e-9); nx /= nl; ny /= nl
            let depth = max(-s, 0)
            let t = clamp(depth / d.bevel, 0, 1)
            // 1) cylindrical lens: the strip magnifies what is behind it vertically
            let lx = x, ly = d.gy + (y - d.gy) / d.lens
            // 2) bevel: near the rim the image is pulled inward hard (compressed, folded band)
            let mag = d.refraction * pow(1 - t, 2.0)
            let dx = lx - nx * mag - x, dy = ly - ny * mag - y
            // 3) chromatic split grows with the displacement
            var ch3 = [0.0, 0.0, 0.0]
            for ch in 0..<3 {
                let f = 1 + d.chroma * Double(ch - 1)
                let sx = (x + dx * f) * k, sy = (y + dy * f) * k
                ch3[ch] = mix(bg.sample(sx, sy, ch), frosted.sample(sx, sy, ch), d.frost)
            }
            var g = C3(ch3[0], ch3[1], ch3[2]).saturated(1.15)
            // material: clear, slightly milky and brighter than what is behind
            g = g * (1 - d.lift) + C3(1, 1, 1) * d.lift
            g = g * 1.06
            // body shading: lighter under the top surface, a little deeper toward the bottom
            let vy = clamp((y - (d.gy - d.ghh)) / (2 * d.ghh), 0, 1)
            g = g * (1.05 - 0.12 * vy)
            // Fresnel: edges reflect more
            g = g.screen(C3(1, 1, 1), 0.22 * pow(1 - t, 3))
            // thin dark refraction line just inside the bright rim (edge of the bevel)
            g = g * (1 - 0.22 * exp(-pow((depth - 5.5) / 2.6, 2)))
            // specular: key light from the upper left, counter light from the lower right
            let lx0 = -0.42, ly0 = -0.91
            let key = max(0, nx * lx0 + ny * ly0), back = max(0, -(nx * lx0 + ny * ly0))
            let rimW = max(d.rimWidth, 0.9 * px1)
            let rim = exp(-depth / rimW)
            let spec = rim * (d.rimTop * pow(key, 2.2) + d.rimBottom * pow(back, 2.6) + 0.22)
            // broad soft sheen hugging the inside of the top edge
            let sheen = 0.20 * exp(-depth / (d.ghh * 0.32)) * pow(max(0, -ny), 1.5)
            // a crisp glint on the upper-left shoulder of the capsule
            let glint = 0.9 * rim * pow(key, 14)
            g = g.screen(C3(1, 1, 1), clamp(spec + sheen + glint, 0, 1))
            c = c.lerp(g, cov)
        } else if s < 3 * px1 {
            // hairline of darker refracted light just outside the glass edge
            c = c * (1 - 0.07 * (1 - smoothstep(0, 3 * px1, s)))
        }
        out.set(i, j, c)
    } }

    // wallpaper inside the iMac screen (slightly oversized; the bezel is drawn on top)
    let sr = d.screenRect
    let i0 = max(0, Int(floor(sr.x0 * k)) - 1), i1 = min(n - 1, Int(ceil(sr.x1 * k)) + 1)
    let j0 = max(0, Int(floor(sr.y0 * k)) - 1), j1 = min(n - 1, Int(ceil(sr.y1 * k)) + 1)
    if i1 > i0 && j1 > j0 {
        for j in j0...j1 { for i in i0...i1 {
            let x = (Double(i) + 0.5) / k, y = (Double(j) + 0.5) / k
            let u = (x - sr.x0) / (sr.x1 - sr.x0), v = (y - sr.y0) / (sr.y1 - sr.y0)
            out.set(i, j, wallpaper(clamp(u, 0, 1), clamp(v, 0, 1), d))
        } }
    }
    return out
}

// MARK: - CoreGraphics helpers

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func makeContext(_ n: Int) -> CGContext {
    CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: sRGB,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func gradient(_ stops: [(Double, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: sRGB, colors: stops.map { $0.1 } as CFArray, locations: stops.map { CGFloat($0.0) })!
}

func fillLinear(_ ctx: CGContext, _ path: CGPath, _ stops: [(Double, CGColor)], _ p0: CGPoint, _ p1: CGPoint,
                evenOdd: Bool = false) {
    ctx.saveGState(); ctx.addPath(path)
    if evenOdd { ctx.clip(using: .evenOdd) } else { ctx.clip() }
    ctx.drawLinearGradient(gradient(stops), start: p0, end: p1, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

func roundedRect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double,
                 tl: Double, tr: Double, br: Double, bl: Double) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: x0 + tl, y: y0))
    p.addLine(to: CGPoint(x: x1 - tr, y: y0))
    if tr > 0 { p.addArc(tangent1End: CGPoint(x: x1, y: y0), tangent2End: CGPoint(x: x1, y: y0 + tr), radius: tr) }
    p.addLine(to: CGPoint(x: x1, y: y1 - br))
    if br > 0 { p.addArc(tangent1End: CGPoint(x: x1, y: y1), tangent2End: CGPoint(x: x1 - br, y: y1), radius: br) } else { p.addLine(to: CGPoint(x: x1, y: y1)) }
    p.addLine(to: CGPoint(x: x0 + bl, y: y1))
    if bl > 0 { p.addArc(tangent1End: CGPoint(x: x0, y: y1), tangent2End: CGPoint(x: x0, y: y1 - bl), radius: bl) } else { p.addLine(to: CGPoint(x: x0, y: y1)) }
    p.addLine(to: CGPoint(x: x0, y: y0 + tl))
    if tl > 0 { p.addArc(tangent1End: CGPoint(x: x0, y: y0), tangent2End: CGPoint(x: x0 + tl, y: y0), radius: tl) }
    p.closeSubpath()
    return p
}

/// macOS icon tile: continuous-curvature ("squircle") rounded rect.
func squircle(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ radius: Double) -> CGPath {
    let r = min(radius, min(w, h) / 2 / 1.52866483)
    let minX = x, minY = y, maxX = x + w, maxY = y + h
    func TL(_ a: Double, _ b: Double) -> CGPoint { CGPoint(x: minX + a * r, y: minY + b * r) }
    func TR(_ a: Double, _ b: Double) -> CGPoint { CGPoint(x: maxX - a * r, y: minY + b * r) }
    func BR(_ a: Double, _ b: Double) -> CGPoint { CGPoint(x: maxX - a * r, y: maxY - b * r) }
    func BL(_ a: Double, _ b: Double) -> CGPoint { CGPoint(x: minX + a * r, y: maxY - b * r) }
    let p = CGMutablePath()
    p.move(to: TL(1.52866483, 0))
    p.addLine(to: TR(1.52866471, 0))
    p.addCurve(to: TR(0.66993427, 0.06549600), control1: TR(1.08849323, 0), control2: TR(0.86840689, 0))
    p.addCurve(to: TR(0.06549569, 0.66993493), control1: TR(0.37620656, 0.17923143), control2: TR(0.17923073, 0.37620750))
    p.addCurve(to: TR(0, 1.52866483), control1: TR(0, 0.86840701), control2: TR(0, 1.08849299))
    p.addLine(to: BR(0, 1.52866471))
    p.addCurve(to: BR(0.06549600, 0.66993427), control1: BR(0, 1.08849323), control2: BR(0, 0.86840689))
    p.addCurve(to: BR(0.66993493, 0.06549569), control1: BR(0.17923143, 0.37620656), control2: BR(0.37620750, 0.17923073))
    p.addCurve(to: BR(1.52866483, 0), control1: BR(0.86840701, 0), control2: BR(1.08849299, 0))
    p.addLine(to: BL(1.52866471, 0))
    p.addCurve(to: BL(0.66993427, 0.06549600), control1: BL(1.08849323, 0), control2: BL(0.86840689, 0))
    p.addCurve(to: BL(0.06549569, 0.66993493), control1: BL(0.37620656, 0.17923143), control2: BL(0.17923073, 0.37620750))
    p.addCurve(to: BL(0, 1.52866483), control1: BL(0, 0.86840701), control2: BL(0, 1.08849299))
    p.addLine(to: TL(0, 1.52866471))
    p.addCurve(to: TL(0.06549600, 0.66993427), control1: TL(0, 1.08849323), control2: TL(0, 0.86840689))
    p.addCurve(to: TL(0.66993493, 0.06549569), control1: TL(0.17923143, 0.37620656), control2: TL(0.37620750, 0.17923073))
    p.addCurve(to: TL(1.52866483, 0), control1: TL(0.86840701, 0), control2: TL(1.08849299, 0))
    p.closeSubpath()
    return p
}

func softEllipse(_ ctx: CGContext, cx: Double, cy: Double, rx: Double, ry: Double, alpha: Double) {
    ctx.saveGState()
    ctx.translateBy(x: cx, y: cy); ctx.scaleBy(x: rx, y: ry)
    ctx.drawRadialGradient(gradient([(0, CGColor(gray: 0, alpha: alpha)), (0.45, CGColor(gray: 0, alpha: alpha * 0.55)),
                                     (1, CGColor(gray: 0, alpha: 0))]),
                           startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 1, options: [])
    ctx.restoreGState()
}

/// deterministic grain image (gray, alpha) for the bead-blasted aluminium
func grainImage(_ n: Int) -> CGImage {
    var bytes = [UInt8](repeating: 0, count: n * n * 4)
    var state: UInt64 = 0x9E3779B97F4A7C15
    for i in 0..<(n * n) {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        let v = UInt8(truncatingIfNeeded: state >> 56)
        let a: UInt8 = 255
        let g = v > 128 ? UInt8(255) : UInt8(0)
        let alpha = UInt8(Double(abs(Int(v) - 128)) / 128 * Double(a) * 0.5)
        let pm = UInt8(Double(g) * Double(alpha) / 255)
        bytes[i * 4] = pm; bytes[i * 4 + 1] = pm; bytes[i * 4 + 2] = pm; bytes[i * 4 + 3] = alpha
    }
    let ctx = CGContext(data: &bytes, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return ctx.makeImage()!
}

// MARK: - Pass 2: the iMac (vector, reference coordinates)

func drawIMac(_ ctx: CGContext, _ d: Design, n: Int) {
    let al = { (h: UInt32) in C3(hex: h).cg }
    // contact shadow on the glass, under the foot (design coords)
    let fb = d.footBottom
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: CGRect(x: d.gx - d.ghw, y: d.gy - d.ghh, width: 2 * d.ghw, height: 2 * d.ghh),
                       cornerWidth: d.gr, cornerHeight: d.gr, transform: nil))
    ctx.clip()
    let fw = (662 - 362) / 2 * d.s
    softEllipse(ctx, cx: d.cx, cy: fb, rx: fw * 1.30, ry: d.variant == .full ? 26 : 34, alpha: 0.42)
    softEllipse(ctx, cx: d.cx, cy: fb, rx: fw * 1.02, ry: d.variant == .full ? 7 : 12, alpha: 0.60)
    ctx.restoreGState()

    ctx.saveGState()
    ctx.translateBy(x: d.cx, y: d.top); ctx.scaleBy(x: d.s, y: d.s); ctx.translateBy(x: -511, y: -270)

    // ---------- stand (behind the body) ----------
    let neck = CGMutablePath()
    if d.detail {
        neck.move(to: CGPoint(x: 421, y: 838))
        neck.addLine(to: CGPoint(x: 603, y: 838))
        neck.addLine(to: CGPoint(x: 609, y: 902))
        neck.addCurve(to: CGPoint(x: 652, y: 948), control1: CGPoint(x: 612, y: 934), control2: CGPoint(x: 628, y: 945))
        neck.addLine(to: CGPoint(x: 372, y: 948))
        neck.addCurve(to: CGPoint(x: 415, y: 902), control1: CGPoint(x: 396, y: 945), control2: CGPoint(x: 412, y: 934))
        neck.closeSubpath()
    } else {
        neck.move(to: CGPoint(x: 410, y: 838))
        neck.addLine(to: CGPoint(x: 614, y: 838))
        neck.addLine(to: CGPoint(x: 620, y: 900))
        neck.addCurve(to: CGPoint(x: 670, y: 950), control1: CGPoint(x: 624, y: 935), control2: CGPoint(x: 640, y: 946))
        neck.addLine(to: CGPoint(x: 354, y: 950))
        neck.addCurve(to: CGPoint(x: 404, y: 900), control1: CGPoint(x: 384, y: 946), control2: CGPoint(x: 400, y: 935))
        neck.closeSubpath()
    }
    fillLinear(ctx, neck, [(0, al(0x7E7F84)), (0.10, al(0xA9AAAF)), (0.38, al(0xC9CACE)), (0.70, al(0xB4B5BA)),
                           (0.83, al(0x9C9DA2)), (0.93, al(0xC3C4C8)), (1, al(0xDCDDE0))],
               CGPoint(x: 0, y: 838), CGPoint(x: 0, y: 948))
    // side shading of the neck (it is a curved sheet)
    fillLinear(ctx, neck, [(0, CGColor(gray: 0, alpha: 0.22)), (0.22, CGColor(gray: 0, alpha: 0.0)),
                           (0.5, CGColor(gray: 1, alpha: 0.06)), (0.78, CGColor(gray: 0, alpha: 0.0)), (1, CGColor(gray: 0, alpha: 0.22))],
               CGPoint(x: 405, y: 0), CGPoint(x: 619, y: 0))

    // foot: top face (seen slightly from above) + bright front lip
    let fx0 = d.detail ? 362.0 : 336.0, fx1 = d.detail ? 662.0 : 688.0
    let footTop = CGMutablePath()
    footTop.move(to: CGPoint(x: fx0 + 26, y: 945))
    footTop.addLine(to: CGPoint(x: fx1 - 26, y: 945))
    footTop.addCurve(to: CGPoint(x: fx1, y: 957), control1: CGPoint(x: fx1 - 8, y: 948), control2: CGPoint(x: fx1, y: 951))
    footTop.addLine(to: CGPoint(x: fx0, y: 957))
    footTop.addCurve(to: CGPoint(x: fx0 + 26, y: 945), control1: CGPoint(x: fx0, y: 951), control2: CGPoint(x: fx0 + 8, y: 948))
    footTop.closeSubpath()
    fillLinear(ctx, footTop, [(0, al(0xC9CACE)), (1, al(0xE6E7EA))], CGPoint(x: 0, y: 945), CGPoint(x: 0, y: 957))
    let lip = roundedRect(fx0, 955.5, fx1, 966, tl: 4, tr: 4, br: 6, bl: 6)
    fillLinear(ctx, lip, [(0, al(0xFAFAFB)), (0.35, al(0xE9EAEC)), (1, al(0xA6A7AB))], CGPoint(x: 0, y: 955.5), CGPoint(x: 0, y: 966))
    if d.detail {
        // subtle end shading on the lip
        fillLinear(ctx, lip, [(0, CGColor(gray: 0, alpha: 0.18)), (0.12, CGColor(gray: 0, alpha: 0)),
                              (0.88, CGColor(gray: 0, alpha: 0)), (1, CGColor(gray: 0, alpha: 0.18))],
                   CGPoint(x: fx0, y: 0), CGPoint(x: fx1, y: 0))
    }
    // shadow cast by the chin on the top of the neck
    ctx.saveGState(); ctx.addPath(neck); ctx.clip()
    ctx.drawLinearGradient(gradient([(0, CGColor(gray: 0, alpha: 0.45)), (1, CGColor(gray: 0, alpha: 0))]),
                           start: CGPoint(x: 0, y: 845), end: CGPoint(x: 0, y: 866), options: [.drawsBeforeStartLocation])
    ctx.restoreGState()

    // ---------- body ----------
    let rim = d.silverRim
    let body = roundedRect(110, 270, 912, 845, tl: 30, tr: 30, br: 30, bl: 30)
    let sr = (x0: 151.0, y0: 308.0, x1: 873.0, y1: 714.0)
    let screenHole = CGPath(rect: CGRect(x: sr.x0, y: sr.y0, width: sr.x1 - sr.x0, height: sr.y1 - sr.y0), transform: nil)
    // aluminium edge (shows as a thin bright rim around the black glass)
    let bodyMinusScreen = CGMutablePath(); bodyMinusScreen.addPath(body); bodyMinusScreen.addPath(screenHole)
    fillLinear(ctx, bodyMinusScreen, [(0, al(0xEDEEF0)), (0.5, al(0xB9BABE)), (1, al(0x9FA0A4))],
               CGPoint(x: 0, y: 270), CGPoint(x: 0, y: 845), evenOdd: true)
    // black glass panel
    let glassPanel = roundedRect(110 + rim, 270 + rim, 912 - rim, 756, tl: 30 - rim, tr: 30 - rim, br: 0, bl: 0)
    let panel = CGMutablePath(); panel.addPath(glassPanel); panel.addPath(screenHole)
    fillLinear(ctx, panel, [(0, al(0x1A1B1F)), (0.5, al(0x0B0B0D)), (1, al(0x050506))],
               CGPoint(x: 0, y: 270), CGPoint(x: 0, y: 756), evenOdd: true)
    // chin
    let chin = roundedRect(110, 756, 912, 845, tl: 0, tr: 0, br: 30, bl: 30)
    fillLinear(ctx, chin, [(0, al(0xE7E8EA)), (0.45, al(0xD3D4D7)), (1, al(0xBCBDC1))],
               CGPoint(x: 0, y: 756), CGPoint(x: 0, y: 845))
    fillLinear(ctx, chin, [(0, CGColor(gray: 0, alpha: 0.16)), (0.18, CGColor(gray: 0, alpha: 0)),
                           (0.5, CGColor(gray: 1, alpha: 0.10)), (0.82, CGColor(gray: 0, alpha: 0)), (1, CGColor(gray: 0, alpha: 0.16))],
               CGPoint(x: 110, y: 0), CGPoint(x: 912, y: 0))
    if d.detail {
        // bead-blasted grain on the aluminium
        ctx.saveGState(); ctx.addPath(chin); ctx.addPath(neck); ctx.clip(); ctx.setAlpha(0.06)
        ctx.draw(grainImage(n), in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
        ctx.restoreGState()
        // seam between glass and aluminium + bevel highlight
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.55)); ctx.fill(CGRect(x: 110, y: 755.2, width: 802, height: 1.6))
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.65)); ctx.fill(CGRect(x: 113, y: 756.8, width: 796, height: 1.6))
        // chin bottom edge darkening
        ctx.saveGState(); ctx.addPath(chin); ctx.clip()
        ctx.drawLinearGradient(gradient([(0, CGColor(gray: 0, alpha: 0)), (1, CGColor(gray: 0, alpha: 0.22))]),
                               start: CGPoint(x: 0, y: 836), end: CGPoint(x: 0, y: 845), options: [])
        ctx.restoreGState()
        // FaceTime HD camera
        ctx.setFillColor(CGColor(gray: 0.20, alpha: 1)); ctx.fillEllipse(in: CGRect(x: 508, y: 286, width: 6, height: 6))
        ctx.setFillColor(CGColor(gray: 0.45, alpha: 1)); ctx.fillEllipse(in: CGRect(x: 510, y: 287.5, width: 2, height: 2))
        // a thin inner shadow at the screen edge (screen sits under the glass)
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.6)); ctx.setLineWidth(2)
        ctx.stroke(CGRect(x: sr.x0 + 1, y: sr.y0 + 1, width: sr.x1 - sr.x0 - 2, height: sr.y1 - sr.y0 - 2))
    }
    // diagonal reflection on the front glass (panel + screen)
    let sheen = CGMutablePath()
    sheen.move(to: CGPoint(x: 110, y: 270)); sheen.addLine(to: CGPoint(x: 600, y: 270))
    sheen.addLine(to: CGPoint(x: 300, y: 756)); sheen.addLine(to: CGPoint(x: 110, y: 756)); sheen.closeSubpath()
    ctx.saveGState(); ctx.addPath(glassPanel); ctx.clip(); ctx.addPath(sheen); ctx.clip()
    ctx.drawLinearGradient(gradient([(0, CGColor(gray: 1, alpha: 0.10)), (1, CGColor(gray: 1, alpha: 0.02))]),
                           start: CGPoint(x: 110, y: 270), end: CGPoint(x: 450, y: 600), options: [])
    ctx.restoreGState()
    ctx.restoreGState()
}

/// Simplified iMac for 16/32 px (design units, grid-snapped).
func drawIMacTiny(_ ctx: CGContext, _ d: Design, _ g: SmallGeom) {
    let al = { (h: UInt32) in C3(hex: h).cg }
    // contact shadow, on the glass only
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: CGRect(x: d.gx - d.ghw, y: d.gy - d.ghh, width: 2 * d.ghw, height: 2 * d.ghh),
                       cornerWidth: d.gr, cornerHeight: d.gr, transform: nil))
    ctx.clip()
    softEllipse(ctx, cx: d.cx, cy: g.foot.y1, rx: (g.foot.x1 - g.foot.x0) * 0.62, ry: 30, alpha: 0.55)
    ctx.restoreGState()
    // neck
    let n = g.neck
    let neck = CGMutablePath()
    neck.move(to: CGPoint(x: n.x0, y: n.y0)); neck.addLine(to: CGPoint(x: n.x1, y: n.y0))
    neck.addLine(to: CGPoint(x: n.x1 + n.flare * 0.3, y: n.y1 - n.flare))
    neck.addQuadCurve(to: CGPoint(x: n.x1 + n.flare * 2, y: n.y1), control: CGPoint(x: n.x1 + n.flare * 0.4, y: n.y1))
    neck.addLine(to: CGPoint(x: n.x0 - n.flare * 2, y: n.y1))
    neck.addQuadCurve(to: CGPoint(x: n.x0 - n.flare * 0.3, y: n.y1 - n.flare), control: CGPoint(x: n.x0 - n.flare * 0.4, y: n.y1))
    neck.closeSubpath()
    fillLinear(ctx, neck, [(0, al(0x8C8D92)), (0.3, al(0xBFC0C4)), (1, al(0xD4D5D8))],
               CGPoint(x: 0, y: n.y0), CGPoint(x: 0, y: n.y1))
    // foot (bright lip — it catches the light)
    let f = g.foot
    fillLinear(ctx, roundedRect(f.x0, f.y0, f.x1, f.y1, tl: 8, tr: 8, br: 10, bl: 10),
               [(0, al(0xF4F4F6)), (1, al(0xC4C5C9))], CGPoint(x: 0, y: f.y0), CGPoint(x: 0, y: f.y1))
    // body: aluminium edge, black glass, screen hole, chin
    let b = g.body, sc = g.screen, rim = d.silverRim
    let body = roundedRect(b.x0, b.y0, b.x1, b.y1, tl: 28, tr: 28, br: 28, bl: 28)
    let hole = CGPath(rect: CGRect(x: sc.x0, y: sc.y0, width: sc.x1 - sc.x0, height: sc.y1 - sc.y0), transform: nil)
    let bm = CGMutablePath(); bm.addPath(body); bm.addPath(hole)
    fillLinear(ctx, bm, [(0, al(0xF2F3F5)), (1, al(0xA9AAAE))], CGPoint(x: 0, y: b.y0), CGPoint(x: 0, y: b.y1), evenOdd: true)
    let panel = CGMutablePath()
    panel.addPath(roundedRect(b.x0 + rim, b.y0 + rim, b.x1 - rim, g.panelBottom, tl: 28 - rim, tr: 28 - rim, br: 0, bl: 0))
    panel.addPath(hole)
    ctx.addPath(panel); ctx.setFillColor(al(0x070709)); ctx.fillPath(using: .evenOdd)
    let chin = roundedRect(b.x0, g.panelBottom, b.x1, b.y1, tl: 0, tr: 0, br: 28, bl: 28)
    fillLinear(ctx, chin, [(0, al(0xEEEFF1)), (1, al(0xC9CACD))], CGPoint(x: 0, y: g.panelBottom), CGPoint(x: 0, y: b.y1))
}

// MARK: - Icon assembly

func renderScene(n: Int, d: Design) -> CGImage {
    let canvas = perPixelScene(n: n, d: d)
    let ctx = makeContext(n)
    let data = ctx.data!.bindMemory(to: UInt8.self, capacity: n * n * 4)
    // CG bitmap rows are top-down in memory, same as our canvas
    for j in 0..<n { for i in 0..<n {
        let c = canvas.at(i, j), o = (j * n + i) * 4
        data[o] = UInt8(clamp(c.r, 0, 1) * 255 + 0.5)
        data[o + 1] = UInt8(clamp(c.g, 0, 1) * 255 + 0.5)
        data[o + 2] = UInt8(clamp(c.b, 0, 1) * 255 + 0.5)
        data[o + 3] = 255
    } }
    let k = Double(n) / 1024
    ctx.translateBy(x: 0, y: Double(n)); ctx.scaleBy(x: k, y: -k)   // y-down design space
    ctx.interpolationQuality = .high
    if let g = d.geom { drawIMacTiny(ctx, d, g) } else { drawIMac(ctx, d, n: n) }
    return ctx.makeImage()!
}

func renderIcon(n: Int, d: Design) -> CGImage {
    let scene = renderScene(n: n, d: d)
    let k = Double(n) / 1024
    let ctx = makeContext(n)
    ctx.interpolationQuality = .high
    let tile = squircle(100, 100, 824, 824, 185.4)
    // drop shadow (the usual macOS icon shadow), offsets are in device space
    ctx.saveGState()
    ctx.translateBy(x: 0, y: Double(n)); ctx.scaleBy(x: k, y: -k)
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 24 * k, color: CGColor(gray: 0, alpha: 0.42))
    ctx.addPath(tile); ctx.setFillColor(C3(hex: 0x1B2C78).cg); ctx.fillPath()
    ctx.restoreGState()
    // scene clipped to the tile
    ctx.saveGState()
    ctx.translateBy(x: 0, y: Double(n)); ctx.scaleBy(x: k, y: -k)
    ctx.addPath(tile); ctx.clip()
    ctx.scaleBy(x: 1, y: -1); ctx.translateBy(x: 0, y: -1024)          // back to y-up for drawing the image
    ctx.draw(scene, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
    ctx.restoreGState()
    // Tahoe-style light edge on the tile
    ctx.saveGState()
    ctx.translateBy(x: 0, y: Double(n)); ctx.scaleBy(x: k, y: -k)
    let lw = max(3.0, 1.2 / k)
    let ring = CGMutablePath(); ring.addPath(tile)
    ring.addPath(squircle(100 + lw, 100 + lw, 824 - 2 * lw, 824 - 2 * lw, 185.4 - lw))
    ctx.addPath(ring); ctx.clip(using: .evenOdd)
    ctx.drawLinearGradient(gradient([(0, CGColor(gray: 1, alpha: 0.55)), (0.35, CGColor(gray: 1, alpha: 0.10)),
                                     (0.7, CGColor(gray: 1, alpha: 0.04)), (1, CGColor(gray: 1, alpha: 0.22))]),
                           start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 924), options: [])
    ctx.restoreGState()
    return ctx.makeImage()!
}

// MARK: - Resampling and I/O

func rgbaBytes(_ img: CGImage) -> [UInt8] {
    let w = img.width, h = img.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return buf
}

func imageFrom(_ bytes: [UInt8], _ w: Int, _ h: Int) -> CGImage {
    var b = bytes
    let ctx = CGContext(data: &b, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return ctx.makeImage()!
}

/// High-quality (Lanczos) downsample with vImage on premultiplied data.
func downscale(_ img: CGImage, to n: Int) -> CGImage {
    if img.width == n { return img }
    var src = rgbaBytes(img)
    var dst = [UInt8](repeating: 0, count: n * n * 4)
    src.withUnsafeMutableBytes { sp in
        dst.withUnsafeMutableBytes { dp in
            var s = vImage_Buffer(data: sp.baseAddress, height: vImagePixelCount(img.height), width: vImagePixelCount(img.width), rowBytes: img.width * 4)
            var d = vImage_Buffer(data: dp.baseAddress, height: vImagePixelCount(n), width: vImagePixelCount(n), rowBytes: n * 4)
            _ = vImageScale_ARGB8888(&s, &d, nil, vImage_Flags(kvImageHighQualityResampling))
        }
    }
    return imageFrom(dst, n, n)
}

/// Exact area-average downsample (integer factor) — keeps grid-snapped edges crisp.
func boxDownscale(_ img: CGImage, to n: Int) -> CGImage {
    let w = img.width, f = w / n
    let src = rgbaBytes(img)
    var dst = [UInt8](repeating: 0, count: n * n * 4)
    for j in 0..<n { for i in 0..<n { for ch in 0..<4 {
        var acc = 0
        for y in (j * f)..<((j + 1) * f) { for x in (i * f)..<((i + 1) * f) { acc += Int(src[(y * w + x) * 4 + ch]) } }
        dst[(j * n + i) * 4 + ch] = UInt8((acc + f * f / 2) / (f * f))
    } } }
    return imageFrom(dst, n, n)
}

func writePNG(_ img: CGImage, _ path: String) {
    let url = URL(fileURLWithPath: path)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, [kCGImagePropertyDPIWidth: 72, kCGImagePropertyDPIHeight: 72] as CFDictionary)
    CGImageDestinationFinalize(dest)
}

// MARK: - Contact sheet

func drawLabel(_ ctx: CGContext, _ text: String, x: Double, y: Double, size: Double, gray: Double) {
    let font = CTFontCreateUIFontForLanguage(.system, size, nil)!
    let attrs: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: gray, alpha: 1)]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
    ctx.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(line, ctx)
}

func contactSheet(_ icons: [Int: CGImage]) -> CGImage {
    let sizes = [1024, 256, 64, 32, 16]
    let gap = 48.0, pad = 56.0, labelH = 40.0, zoom = 6.0
    // per row: icons at actual size, then 32 and 16 magnified (nearest neighbour) for pixel inspection
    let zoomW = 32 * zoom + gap + 16 * zoom
    let rowW = pad * 2 + sizes.reduce(0.0) { $0 + Double($1) } + gap * Double(sizes.count - 1) + gap * 1.5 + zoomW
    let rowH = 1024 + pad * 2 + labelH
    let W = Int(rowW), H = Int(rowH * 2)
    let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    for (row, bgGray) in [(0, 0.96), (1, 0.11)].map({ ($0.0, $0.1) }) {
        let y0 = Double(H) - rowH * Double(row + 1)       // CG is y-up
        ctx.setFillColor(CGColor(gray: bgGray, alpha: 1))
        ctx.fill(CGRect(x: 0, y: y0, width: rowW, height: rowH))
        let textGray = bgGray > 0.5 ? 0.35 : 0.70
        var x = pad
        let baseY = y0 + pad + labelH          // icons bottom-aligned on this line
        for s in sizes {
            ctx.interpolationQuality = .none
            ctx.draw(icons[s]!, in: CGRect(x: x, y: baseY, width: Double(s), height: Double(s)))
            drawLabel(ctx, "\(s)", x: x, y: y0 + pad, size: 20, gray: textGray)
            x += Double(s) + gap
        }
        x += gap * 0.5
        for s in [32, 16] {
            ctx.interpolationQuality = .none
            ctx.draw(icons[s]!, in: CGRect(x: x, y: baseY, width: Double(s) * zoom, height: Double(s) * zoom))
            drawLabel(ctx, "\(s) ×\(Int(zoom))", x: x, y: y0 + pad, size: 20, gray: textGray)
            x += Double(s) * zoom + gap
        }
        drawLabel(ctx, row == 0 ? "TeraScale Metal — light" : "TeraScale Metal — dark",
                  x: pad, y: y0 + rowH - pad + 8, size: 22, gray: textGray)
    }
    return ctx.makeImage()!
}

// MARK: - main

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: terascale-logo <outdir>\n".data(using: .utf8)!); exit(2)
}
let outDir = args[1]
let fm = FileManager.default
let iconset = outDir + "/AppIcon.iconset"
try? fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)

let master = renderIcon(n: 1024, d: .full)
let master16 = renderIcon(n: 1024, d: .tiny(.px16, rim: 26, lift: 0.46))   // whiter glass at 16 px
let master32 = renderIcon(n: 1024, d: .tiny(.px32, rim: 16, lift: 0.36))
writePNG(master, outDir + "/logo-1024.png")

// pixel size -> image; 16 and 32 px use the bold grid-snapped variants
var bySize: [Int: CGImage] = [:]
for px in [64, 128, 256, 512, 1024] { bySize[px] = downscale(master, to: px) }
bySize[16] = boxDownscale(master16, to: 16)
bySize[32] = boxDownscale(master32, to: 32)
let entries: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)]
for (name, px) in entries { writePNG(bySize[px]!, iconset + "/" + name) }

writePNG(contactSheet(bySize), outDir + "/preview.png")
if args.count >= 3 && args[2] == "--debug" {
    writePNG(master16, outDir + "/debug-16-master.png"); writePNG(master32, outDir + "/debug-32-master.png")
}
print("ok: \(outDir)")
