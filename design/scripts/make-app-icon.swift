// Makes Caro's app icon: the CARO wordmark in ink, centred on paper, 1024 by 1024 pixels.
// The iPhone rounds the corners itself, and App Store Connect refuses transparency, so the
// background is solid paper.
//
// From the Wardrobe folder:
//   swift design/scripts/make-app-icon.swift design/assets/caro-wordmark-ink.png app/Caro/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
//
// T8 uses the small PNG wordmark, so the letters are a little soft. When Sara's vector file
// arrives, export it as a large PNG (2000 pixels wide or more) and run this again with it.

import AppKit
import CoreGraphics

let arguments = CommandLine.arguments
guard arguments.count == 3,
      let source = NSImage(contentsOfFile: arguments[1]),
      let wordmark = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("Use: swift make-app-icon.swift <wordmark.png> <AppIcon.png>")
    exit(1)
}

let size = 1024
let paper = CGColor(red: 0xF7 / 255, green: 0xF2 / 255, blue: 0xE9 / 255, alpha: 1)
// The wordmark spans 62% of the icon, so it stays clear of the rounded corners.
let width = CGFloat(size) * 0.62
let height = width * CGFloat(wordmark.height) / CGFloat(wordmark.width)

let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!
context.setFillColor(paper)
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
context.interpolationQuality = .high
context.draw(wordmark, in: CGRect(x: (CGFloat(size) - width) / 2, y: (CGFloat(size) - height) / 2, width: width, height: height))

let icon = NSBitmapImageRep(cgImage: context.makeImage()!)
try! icon.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: arguments[2]))
print("Saved \(arguments[2])")
