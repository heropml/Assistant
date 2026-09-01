#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

private struct IconSlot {
    let fileName: String
    let pixelSize: Int
    let logicalSize: Int
}

private let slots = [
    IconSlot(fileName: "appicon-16.png", pixelSize: 16, logicalSize: 16),
    IconSlot(fileName: "appicon-16@2x.png", pixelSize: 32, logicalSize: 16),
    IconSlot(fileName: "appicon-32.png", pixelSize: 32, logicalSize: 32),
    IconSlot(fileName: "appicon-32@2x.png", pixelSize: 64, logicalSize: 32),
    IconSlot(fileName: "appicon-128.png", pixelSize: 128, logicalSize: 128),
    IconSlot(fileName: "appicon-128@2x.png", pixelSize: 256, logicalSize: 128),
    IconSlot(fileName: "appicon-256.png", pixelSize: 256, logicalSize: 256),
    IconSlot(fileName: "appicon-256@2x.png", pixelSize: 512, logicalSize: 256),
    IconSlot(fileName: "appicon-512.png", pixelSize: 512, logicalSize: 512),
    IconSlot(fileName: "appicon-512@2x.png", pixelSize: 1_024, logicalSize: 512),
]

private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

private func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    let red = CGFloat((hex >> 16) & 0xff) / 255
    let green = CGFloat((hex >> 8) & 0xff) / 255
    let blue = CGFloat(hex & 0xff) / 255
    return CGColor(colorSpace: colorSpace, components: [red, green, blue, alpha])!
}

private func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

private func cutCornerRect(_ rect: CGRect, cut: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cut))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cut))
    path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX + cut, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - cut))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cut))
    path.closeSubpath()
    return path
}

private func drawBackground(in context: CGContext, logicalSize: Int, deviceScale: CGFloat) {
    let background = roundedRect(CGRect(x: 64, y: 64, width: 896, height: 896), radius: 216)

    if logicalSize > 32 {
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -18 * deviceScale),
            blur: (logicalSize >= 256 ? 30 : 16) * deviceScale,
            color: color(0x02030D, alpha: 0.62)
        )
        context.setFillColor(color(0x070A18))
        context.addPath(background)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(background)
        context.clip()
        let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [color(0x080B1C), color(0x17103D), color(0x32105B)] as CFArray,
            locations: [0, 0.56, 1]
        )!
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 110, y: 902),
            end: CGPoint(x: 914, y: 118),
            options: []
        )

        if logicalSize >= 128 {
            let cyanGlow = CGGradient(
                colorsSpace: colorSpace,
                colors: [color(0x00E5FF, alpha: 0.44), color(0x00E5FF, alpha: 0)] as CFArray,
                locations: [0, 1]
            )!
            context.drawRadialGradient(
                cyanGlow,
                startCenter: CGPoint(x: 238, y: 760),
                startRadius: 0,
                endCenter: CGPoint(x: 238, y: 760),
                endRadius: 520,
                options: [.drawsAfterEndLocation]
            )

            let magentaGlow = CGGradient(
                colorsSpace: colorSpace,
                colors: [color(0xFF2BD6, alpha: 0.34), color(0xFF2BD6, alpha: 0)] as CFArray,
                locations: [0, 1]
            )!
            context.drawRadialGradient(
                magentaGlow,
                startCenter: CGPoint(x: 812, y: 246),
                startRadius: 0,
                endCenter: CGPoint(x: 812, y: 246),
                endRadius: 470,
                options: [.drawsAfterEndLocation]
            )

        }
        context.restoreGState()

        let frame = cutCornerRect(CGRect(x: 146, y: 146, width: 732, height: 732), cut: 74)
        context.saveGState()
        context.setFillColor(color(0x070A1A, alpha: 0.38))
        context.addPath(frame)
        context.fillPath()
        context.setStrokeColor(color(0x64F3FF, alpha: 0.76))
        context.setLineWidth(logicalSize >= 256 ? 12 : 16)
        context.addPath(frame)
        context.strokePath()
        context.setStrokeColor(color(0xFF46DE, alpha: 0.76))
        context.setLineWidth(logicalSize >= 256 ? 8 : 12)
        context.move(to: CGPoint(x: 878, y: 330))
        context.addLine(to: CGPoint(x: 878, y: 804))
        context.addLine(to: CGPoint(x: 804, y: 878))
        context.addLine(to: CGPoint(x: 620, y: 878))
        context.strokePath()
        context.restoreGState()
    } else {
        context.setFillColor(color(0x15103D))
        context.addPath(background)
        context.fillPath()
    }
}

private func drawTinyMark(in context: CGContext, logicalSize: Int) {
    let unit: CGFloat = 64
    let cursor = CGMutablePath()
    cursor.move(to: CGPoint(x: 3 * unit, y: 2.4 * unit))
    cursor.addLine(to: CGPoint(x: 3 * unit, y: 12.6 * unit))
    cursor.addLine(to: CGPoint(x: 5.4 * unit, y: 10.2 * unit))
    cursor.addLine(to: CGPoint(x: 7 * unit, y: 13.8 * unit))
    cursor.addLine(to: CGPoint(x: 8.6 * unit, y: 13.1 * unit))
    cursor.addLine(to: CGPoint(x: 7 * unit, y: 9.6 * unit))
    cursor.addLine(to: CGPoint(x: 9.9 * unit, y: 9.1 * unit))
    cursor.closeSubpath()

    context.setFillColor(color(0xD9FBFF))
    context.addPath(cursor)
    context.fillPath()

    let rails: [CGRect] = logicalSize <= 16
        ? [
            CGRect(x: 9.5 * unit, y: 3.8 * unit, width: 4.1 * unit, height: 1.35 * unit),
            CGRect(x: 10.5 * unit, y: 6.3 * unit, width: 3.1 * unit, height: 1.35 * unit),
        ]
        : [
            CGRect(x: 9.3 * unit, y: 3.7 * unit, width: 4.5 * unit, height: 1.45 * unit),
            CGRect(x: 10.1 * unit, y: 6.1 * unit, width: 3.7 * unit, height: 1.45 * unit),
            CGRect(x: 11 * unit, y: 8.5 * unit, width: 2.8 * unit, height: 1.45 * unit),
        ]
    let railColors = [color(0x00E5FF), color(0xD9FBFF), color(0xFF2BD6)]
    for (index, rail) in rails.enumerated() {
        context.setFillColor(railColors[index])
        context.addPath(roundedRect(rail, radius: rail.height / 2))
        context.fillPath()
    }
}

private func drawFullMark(in context: CGContext, logicalSize: Int, deviceScale: CGFloat) {
    let railRects = [
        CGRect(x: 552, y: 286, width: 236, height: 62),
        CGRect(x: 574, y: 426, width: 214, height: 62),
        CGRect(x: 596, y: 566, width: 192, height: 62),
    ]

    context.saveGState()
    if logicalSize >= 256 {
        context.setShadow(
            offset: CGSize(width: 0, height: -14 * deviceScale),
            blur: 28 * deviceScale,
            color: color(0x00E5FF, alpha: 0.64)
        )
    }
    for (index, rect) in railRects.enumerated() {
        let railColor = [color(0x00E5FF), color(0xD9FBFF), color(0xFF2BD6)][index]
        context.setFillColor(railColor)
        context.addPath(cutCornerRect(rect, cut: 16))
        context.fillPath()
        let nodeSize: CGFloat = 52
        let node = CGRect(x: rect.maxX + 20, y: rect.midY - nodeSize / 2, width: nodeSize, height: nodeSize)
        context.addPath(cutCornerRect(node, cut: 9))
        context.fillPath()
    }
    context.restoreGState()

    let cursor = CGMutablePath()
    cursor.move(to: CGPoint(x: 206, y: 190))
    cursor.addLine(to: CGPoint(x: 206, y: 704))
    cursor.addLine(to: CGPoint(x: 335, y: 575))
    cursor.addLine(to: CGPoint(x: 424, y: 780))
    cursor.addLine(to: CGPoint(x: 509, y: 743))
    cursor.addLine(to: CGPoint(x: 421, y: 540))
    cursor.addLine(to: CGPoint(x: 590, y: 520))
    cursor.closeSubpath()

    context.saveGState()
    if logicalSize >= 128 {
        context.setShadow(
            offset: CGSize(width: 0, height: -14 * deviceScale),
            blur: (logicalSize >= 256 ? 30 : 14) * deviceScale,
            color: color(0x00E5FF, alpha: 0.72)
        )
    }
    context.addPath(cursor)
    context.clip()
    let cursorGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(0xFFFFFF), color(0x8AF7FF), color(0x00E5FF)] as CFArray,
        locations: [0, 0.52, 1]
    )!
    context.drawLinearGradient(
        cursorGradient,
        start: CGPoint(x: 210, y: 760),
        end: CGPoint(x: 550, y: 250),
        options: []
    )
    context.restoreGState()

    context.setStrokeColor(color(0xFFFFFF, alpha: 0.86))
    context.setLineWidth(logicalSize >= 256 ? 8 : 12)
    context.addPath(cursor)
    context.strokePath()
}

private func renderIcon(pixelSize: Int, logicalSize: Int) -> CGImage {
    let context = CGContext(
        data: nil,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: pixelSize * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setShouldAntialias(true)
    context.setAllowsAntialiasing(true)
    context.translateBy(x: 0, y: CGFloat(pixelSize))
    let scale = CGFloat(pixelSize) / 1_024
    context.scaleBy(x: scale, y: -scale)

    drawBackground(in: context, logicalSize: logicalSize, deviceScale: scale)
    if logicalSize <= 32 {
        drawTinyMark(in: context, logicalSize: logicalSize)
    } else {
        drawFullMark(in: context, logicalSize: logicalSize, deviceScale: scale)
    }
    return context.makeImage()!
}

private func validateClearEdges(of image: CGImage, fileName: String) {
    let bitmap = NSBitmapImageRep(cgImage: image)
    let maxX = bitmap.pixelsWide - 1
    let maxY = bitmap.pixelsHigh - 1
    let horizontalEdgesAreClear = (0...maxX).allSatisfy { x in
        bitmap.colorAt(x: x, y: 0)?.alphaComponent == 0
            && bitmap.colorAt(x: x, y: maxY)?.alphaComponent == 0
    }
    let verticalEdgesAreClear = (0...maxY).allSatisfy { y in
        bitmap.colorAt(x: 0, y: y)?.alphaComponent == 0
            && bitmap.colorAt(x: maxX, y: y)?.alphaComponent == 0
    }
    precondition(
        horizontalEdgesAreClear && verticalEdgesAreClear,
        "图标阴影触及画布边缘：\(fileName)"
    )
}

private let scriptURL = URL(fileURLWithPath: #filePath)
private let projectURL = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
private let outputURL = projectURL
    .appendingPathComponent("RightClickAssistant/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
for slot in slots {
    let image = renderIcon(pixelSize: slot.pixelSize, logicalSize: slot.logicalSize)
    validateClearEdges(of: image, fileName: slot.fileName)
    let representation = NSBitmapImageRep(cgImage: image)
    guard let data = representation.representation(using: .png, properties: [:]) else {
        fatalError("无法编码图标：\(slot.fileName)")
    }
    try data.write(to: outputURL.appendingPathComponent(slot.fileName), options: .atomic)
}

print("已生成 \(slots.count) 个 AppIcon 文件：\(outputURL.path)")
