#!/bin/sh
# Renders ios/SFDesk/AppIcon.svg to the opaque 1024px PNG the app icon needs (iOS rejects icons with transparency).
set -eu
cd "$(dirname "$0")/SFDesk"
cat > /tmp/sfdesk-make-icon.swift <<'SWIFT'
import AppKit
let args = CommandLine.arguments
guard let image = NSImage(contentsOfFile: args[1]) else { fatalError("Can't read \(args[1])") }
let size = 1024
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
SWIFT
swift /tmp/sfdesk-make-icon.swift AppIcon.svg Assets.xcassets/AppIcon.appiconset/AppIcon.png
echo "Wrote ios/SFDesk/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
