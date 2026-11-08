#!/usr/bin/env swift
// make-icon.swift - draws the Unscrew app icon as a 1024x1024 transparent PNG.
//
//   swift tools/make-icon.swift build/AppIcon-1024.png
//
// Purple tile, glowing ring, a screw head with a tilted Phillips slot, sparkles around.

import AppKit

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: swift tools/make-icon.swift <out.png>\n".utf8))
    exit(2)
}
let outPath = CommandLine.arguments[1]

func color(_ rgb: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha)
}

let size = 1024
let center = CGPoint(x: 512, y: 512)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))

// Tile: rounded square, radial gradient deep purple -> near black.
let tile = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.addPath(tile)
ctx.clip()
let body = CGGradient(colorsSpace: space, colors: [color(0x3B1366), color(0x12051F)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(body, startCenter: center, startRadius: 0, endCenter: center, endRadius: 412, options: [.drawsAfterEndLocation])
ctx.restoreGState()

// Glowing ring.
let ringRadius: CGFloat = 250
let ring = CGPath(ellipseIn: CGRect(x: center.x - ringRadius, y: center.y - ringRadius, width: ringRadius * 2, height: ringRadius * 2), transform: nil)
for blur in [60, 30, 12, 0] as [CGFloat] {
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: blur, color: color(0x9D5CFF, 0.9))
    ctx.addPath(ring)
    ctx.setStrokeColor(color(0xC9A7FF))
    ctx.setLineWidth(34)
    ctx.strokePath()
    ctx.restoreGState()
}

// Screw head: light at the top, darker at the bottom, thin rim.
let headRadius: CGFloat = 175
let headRect = CGRect(x: center.x - headRadius, y: center.y - headRadius, width: headRadius * 2, height: headRadius * 2)
ctx.saveGState()
ctx.addEllipse(in: headRect)
ctx.clip()
let head = CGGradient(colorsSpace: space, colors: [color(0xE9DDFF), color(0x8E6BC7)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(head, start: CGPoint(x: center.x, y: headRect.maxY), end: CGPoint(x: center.x, y: headRect.minY), options: [])
ctx.restoreGState()
ctx.addEllipse(in: headRect)
ctx.setStrokeColor(color(0x4A2A7A))
ctx.setLineWidth(6)
ctx.strokePath()

// Phillips slot: two rounded bars rotated together by 20 degrees.
ctx.saveGState()
ctx.translateBy(x: center.x, y: center.y)
ctx.rotate(by: 20 * .pi / 180)
let slot = CGMutablePath()
slot.addRoundedRect(in: CGRect(x: -115, y: -23, width: 230, height: 46), cornerWidth: 23, cornerHeight: 23)
slot.addRoundedRect(in: CGRect(x: -23, y: -115, width: 46, height: 230), cornerWidth: 23, cornerHeight: 23)
ctx.addPath(slot)
ctx.setFillColor(color(0x2A0F48))
ctx.fillPath()
ctx.restoreGState()

// Eight four-point sparkles around the ring.
func sparkle(half h: CGFloat) -> CGPath {
    let q = h * 0.16, p = CGMutablePath()
    p.move(to: CGPoint(x: 0, y: h))
    p.addQuadCurve(to: CGPoint(x: h, y: 0), control: CGPoint(x: q, y: q))
    p.addQuadCurve(to: CGPoint(x: 0, y: -h), control: CGPoint(x: q, y: -q))
    p.addQuadCurve(to: CGPoint(x: -h, y: 0), control: CGPoint(x: -q, y: -q))
    p.addQuadCurve(to: CGPoint(x: 0, y: h), control: CGPoint(x: -q, y: q))
    p.closeSubpath()
    return p
}
for i in 0..<8 {
    let a = CGFloat(i) * .pi / 4
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 20, color: color(0xC9A7FF))
    ctx.translateBy(x: center.x + 335 * cos(a), y: center.y + 335 * sin(a))
    ctx.addPath(sparkle(half: 17))
    ctx.setFillColor(color(0xE9DDFF))
    ctx.fillPath()
    ctx.restoreGState()
}

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
let url = URL(fileURLWithPath: outPath)
try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
try! rep.representation(using: .png, properties: [:])!.write(to: url)
print("wrote \(url.path) \(rep.pixelsWide)x\(rep.pixelsHigh)")
