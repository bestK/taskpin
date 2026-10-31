// render_icon.swift: draws the TaskPin app icon with CoreGraphics.
//
// The icon is a "T" monogram that is also a pin seen side-on: a pill head
// (the design system's signature pill shape) over a tapered needle, white on a
// near-black squircle. Black/white only, matching DESIGN.md's palette.
//
// Usage (macOS, no dependencies):
//   xcrun swiftc -O tool/icon/render_icon.swift -o /tmp/render_icon
//   /tmp/render_icon A <px> <out.png>        # macOS: squircle with shadow margin
//   /tmp/render_icon A <px> <out.png> flat   # Windows: full-bleed tile
//
// Outputs in the repo: macos/Runner/Assets.xcassets/AppIcon.appiconset/
// app_icon_{16,32,64,128,256,512,1024}.png, and windows/runner/resources/
// app_icon.ico + taskpin.ico (16/32/48/256 "flat" PNGs packed into one ICO).
// Concepts B and C are kept for comparison; A is the shipped mark.
import AppKit
import CoreGraphics

// Usage: render <concept A|B|C> <size> <out.png>
let args = CommandLine.arguments
let concept = args[1], px = Int(args[2])!, out = args[3]
// "flat": Windows-style full-bleed tile with no macOS shadow margin.
let flat = args.count > 4 && args[4] == "flat"
let S = CGFloat(px) / 1024.0

func squircle(_ r: CGRect, n: CGFloat = 5) -> CGPath {
    let p = CGMutablePath(); let a = r.width/2, b = r.height/2, cx = r.midX, cy = r.midY
    for i in 0...720 {
        let t = CGFloat(i) / 720 * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = cx + a * (c < 0 ? -1 : 1) * pow(abs(c), 2/n)
        let y = cy + b * (s < 0 ? -1 : 1) * pow(abs(s), 2/n)
        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    p.closeSubpath(); return p
}
func pill(_ r: CGRect) -> CGPath { CGPath(roundedRect: r, cornerWidth: r.height/2, cornerHeight: r.height/2, transform: nil) }

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.scaleBy(x: S, y: S)
// Top-down coordinates, matching how the geometry is specified.
ctx.translateBy(x: 0, y: 1024); ctx.scaleBy(x: 1, y: -1)

let tile = flat ? CGRect(x: 24, y: 24, width: 976, height: 976) : CGRect(x: 100, y: 100, width: 824, height: 824)
if !flat {
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 22, color: CGColor(gray: 0, alpha: 0.30))
ctx.addPath(squircle(tile)); ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fillPath()
ctx.restoreGState()
}
ctx.saveGState(); ctx.addPath(squircle(tile)); ctx.clip()
let g = CGGradient(colorsSpace: cs, colors: [CGColor(srgbRed: 0.17, green: 0.17, blue: 0.18, alpha: 1),
                                             CGColor(srgbRed: 0.02, green: 0.02, blue: 0.02, alpha: 1)] as CFArray,
                   locations: [0, 1])!
ctx.drawLinearGradient(g, start: CGPoint(x: 512, y: tile.minY), end: CGPoint(x: 512, y: tile.maxY), options: [])
ctx.restoreGState()

let white = CGColor(gray: 1, alpha: 1)
if flat { let k = tile.width / 824; ctx.translateBy(x: 512, y: 512); ctx.scaleBy(x: k, y: k); ctx.translateBy(x: -512, y: -512) }
ctx.setFillColor(white)
switch concept {
case "A": // T monogram = pill head + tapered needle (a pin seen side-on)
    ctx.addPath(pill(CGRect(x: 262, y: 276, width: 500, height: 148))); ctx.fillPath()
    let st = CGMutablePath()
    st.move(to: CGPoint(x: 452, y: 410)); st.addLine(to: CGPoint(x: 572, y: 410))
    st.addLine(to: CGPoint(x: 518, y: 770)); st.addQuadCurve(to: CGPoint(x: 506, y: 770), control: CGPoint(x: 512, y: 786))
    st.closeSubpath(); ctx.addPath(st); ctx.fillPath()
case "B": // the strip itself: a pill with a live dot and a value bar
    ctx.addPath(pill(CGRect(x: 212, y: 412, width: 600, height: 200))); ctx.fillPath()
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: 272, y: 472, width: 80, height: 80))
    ctx.addPath(pill(CGRect(x: 392, y: 486, width: 340, height: 52))); ctx.fillPath()
case "C": // the strip, pinned: pill strip with a pin head through it
    ctx.addPath(pill(CGRect(x: 192, y: 470, width: 640, height: 168))); ctx.fillPath()
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: 248, y: 506, width: 96, height: 96))
    ctx.setFillColor(white)
    let n = CGMutablePath()
    n.move(to: CGPoint(x: 278, y: 330)); n.addLine(to: CGPoint(x: 314, y: 330)); n.addLine(to: CGPoint(x: 300, y: 520)); n.addLine(to: CGPoint(x: 292, y: 520)); n.closeSubpath()
    ctx.addPath(n); ctx.fillPath()
    ctx.fillEllipse(in: CGRect(x: 236, y: 250, width: 120, height: 120))
default: break
}
let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
