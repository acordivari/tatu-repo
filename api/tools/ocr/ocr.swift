// Batch OCR over local image files using Apple's Vision framework.
//
// macOS-only and deliberately so: this runs on the operator's machine as part
// of the local pipeline (same pattern as bin/add-artists), never on the Linux
// API host. No API cost, no network, ~200ms per image.
//
// Usage:  ocr <file> [<file> ...]
// Output: one JSON object per line — {"path","area","chars","text"}
//         "area" is the summed bounding-box area of detected text as a
//         fraction of the frame, which is what separates a burned-in Reel
//         overlay from an incidental caption in a photo of real work.
//
// Build:  swiftc -O tools/ocr/ocr.swift -o tmp/ocr   (rake does this for you)

import Vision
import AppKit
import Foundation

func emit(_ obj: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: obj),
          let line = String(data: data, encoding: .utf8) else { return }
    print(line)
}

let paths = Array(CommandLine.arguments.dropFirst())
if paths.isEmpty {
    FileHandle.standardError.write("usage: ocr <file> [<file> ...]\n".data(using: .utf8)!)
    exit(64)
}

for path in paths {
    guard let img = NSImage(contentsOfFile: path),
          let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        emit(["path": path, "error": "unreadable"])
        continue
    }
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = .accurate
    req.usesLanguageCorrection = true
    do {
        try VNImageRequestHandler(cgImage: cg, options: [:]).perform([req])
    } catch {
        emit(["path": path, "error": "\(error)"])
        continue
    }
    var area = 0.0
    var parts: [String] = []
    var heights: [Double] = []
    var elongations: [Double] = []
    for obs in (req.results ?? []) {
        guard let c = obs.topCandidates(1).first else { continue }
        // Vision returns normalised boxes, so these are already frame fractions.
        let w = Double(obs.boundingBox.width), h = Double(obs.boundingBox.height)
        area += w * h
        heights.append(h)
        if h > 0 { elongations.append(w / h) }
        parts.append(c.string)
    }
    let text = parts.joined(separator: "\n")
    // Geometry is what separates a burned-in overlay from lettering tattooed on
    // skin — both are "text", and area alone cannot tell them apart. Rendered UI
    // and caption text is many short, wide lines (small meanHeight, high
    // elongation); tattooed script is a few tall, chunky ones.
    let meanHeight = heights.isEmpty ? 0 : heights.reduce(0, +) / Double(heights.count)
    let meanElong = elongations.isEmpty ? 0 : elongations.reduce(0, +) / Double(elongations.count)
    emit([
        "path": path, "area": area, "chars": text.count, "text": text,
        "lines": heights.count, "mean_height": meanHeight, "mean_elongation": meanElong
    ])
}
