import Foundation
import AppKit
import PDFKit
import AutogramKit

// Usage: vision-eval <dataset-folder> [--builtin-only] [--no-fm] [--iou 0.4] [--json]
var args = Array(CommandLine.arguments.dropFirst())
guard let folderPath = args.first else {
    FileHandle.standardError.write("usage: vision-eval <dataset-folder> [--builtin-only] [--no-fm] [--iou 0.4] [--json]\n".data(using: .utf8)!)
    exit(2)
}
args.removeFirst()
let builtinOnly = args.contains("--builtin-only")
let useFM = !args.contains("--no-fm")
let json = args.contains("--json")
var iou = 0.4
if let i = args.firstIndex(of: "--iou"), i + 1 < args.count, let v = Double(args[i + 1]) { iou = v }

let folder = URL(fileURLWithPath: folderPath)
let annotationsURL = folder.appendingPathComponent("annotations.json")
let truth = try JSONDecoder().decode([CreateMLImageAnnotation].self, from: Data(contentsOf: annotationsURL))
let pageOrder = truth.map(\.image)

// Build one PDF page per image so the provider sees the same input as the app.
let document = PDFDocument()
var sizes: [String: CGSize] = [:]
for (index, name) in pageOrder.enumerated() {
    let source = folder.appendingPathComponent(name)
    guard let image = NSImage(contentsOf: source),
          let page = PDFPage(image: image) else { fatalError("cannot load \(name)") }
    guard let pixelSize = CreateMLExporter.imageSize(at: source) else { fatalError("cannot read pixel size for \(name)") }
    sizes[name] = pixelSize
    document.insert(page, at: index)
}

/// PDFDocument/PDFPage are not Sendable; wrap for the single async detect() call below.
struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
}

let bank = ExampleBank(directory: ExampleBank.defaultDirectory)
let provider: any SecurityElementsProviding = builtinOnly
    ? BuiltInVisionProvider()
    : LayeredDetectionProvider.makeDefault(bank: bank, useFoundationModel: useFM)
let analyses = PDFAnalysisEngine().analyze(document: document).pageAnalyses

let documentBox = UncheckedSendableBox(value: document)
let start = Date()
let predicted = await provider.detect(in: documentBox.value, pageAnalyses: analyses)
let elapsed = Date().timeIntervalSince(start) * 1000

let perLabel = DetectionEvaluator.score(predicted: predicted, truth: truth, imageSizes: sizes, pageOrder: pageOrder, iouThreshold: iou)
let metrics = EvaluationMetrics(perLabel: perLabel, meanMillisecondsPerPage: elapsed / Double(max(pageOrder.count, 1)), pages: pageOrder.count)

if json {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try encoder.encode(metrics), as: UTF8.self))
} else {
    print("provider: \(provider.providerName)")
    print(String(format: "pages: %d   mean ms/page: %.0f", metrics.pages, metrics.meanMillisecondsPerPage))
    func pad(_ s: String, _ width: Int) -> String { s.padding(toLength: max(s.count, width), withPad: " ", startingAt: 0) }
    print("\(pad("label", 22)) \(pad("TP", 5)) \(pad("FP", 5)) \(pad("FN", 5)) \(pad("P", 7)) \(pad("R", 7)) \(pad("F1", 7))")
    for (label, m) in perLabel.sorted(by: { $0.key < $1.key }) {
        let row = String(format: "%5d %5d %5d %7.2f %7.2f %7.2f", m.truePositives, m.falsePositives, m.falseNegatives, m.precision, m.recall, m.f1)
        print("\(pad(label, 22)) \(row)")
    }
}
