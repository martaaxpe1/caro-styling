// Cuts pieces out of photos on the Mac, with the same Apple feature the app uses on the iPhone
// (app/Caro/Features/Wardrobe/CutOut.swift), so test 7 sees what the server would see.
//
// swift cutout.swift in1.jpg out1.png in2.jpg out2.png ...
// Prints "lifted" or "nothing lifted" for each. Nothing leaves this Mac.

import AppKit
import CoreImage
import Vision

func cutOut(_ input: String, _ output: String) -> Bool {
    guard let image = NSImage(contentsOfFile: input),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
    let request = VNGenerateForegroundInstanceMaskRequest()
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    do {
        try handler.perform([request])
        guard let result = request.results?.first, !result.allInstances.isEmpty else { return false }
        let buffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: true)
        let lifted = CIImage(cvPixelBuffer: buffer)
        guard let out = CIContext().createCGImage(lifted, from: lifted.extent),
              let png = NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:]) else { return false }
        try png.write(to: URL(fileURLWithPath: output))
        return true
    } catch {
        return false
    }
}

let files = Array(CommandLine.arguments.dropFirst())
for i in stride(from: 0, to: files.count - 1, by: 2) {
    print(cutOut(files[i], files[i + 1]) ? "lifted" : "nothing lifted")
}
