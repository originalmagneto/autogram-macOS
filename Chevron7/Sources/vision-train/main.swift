// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Combine
import CoreGraphics
import CoreML
import CreateML
import Foundation
import Vision
import Chevron7Kit
import Darwin

// Phase 0 spike: train an object detector on the train partition of an
// exported dataset (CreateMLExporter output with annotations.json and
// splits.json), compile it, and score the compiled model on the validation
// and test partitions with DetectionEvaluator (IoU 0.4 default).
//
// Usage: vision-train <dataset-folder> [--iterations N] [--iou 0.4] [--out <dir>]

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("\(message)\n".data(using: .utf8)!)
    exit(2)
}

func peakRSSBytes() -> Int {
    var ru = rusage()
    guard getrusage(RUSAGE_SELF, &ru) == 0 else { return 0 }
    return Int(ru.ru_maxrss)
}

// Unbuffered so progress survives a crash and pipes show live output.
setbuf(stdout, nil)

var args = Array(CommandLine.arguments.dropFirst())
guard let folderPath = args.first, !folderPath.hasPrefix("--") else {
    fail("usage: vision-train <dataset-folder> [--iterations N] [--iou 0.4] [--out <dir>]")
}
args.removeFirst()
var maxIterations = 20
var iou = 0.4
var outDir: URL?
if let i = args.firstIndex(of: "--iterations"), i + 1 < args.count, let v = Int(args[i + 1]) { maxIterations = v }
if let i = args.firstIndex(of: "--iou"), i + 1 < args.count, let v = Double(args[i + 1]) { iou = v }
if let i = args.firstIndex(of: "--out"), i + 1 < args.count {
    outDir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
}

let folder = URL(fileURLWithPath: folderPath, isDirectory: true)
let allAnnotations: [CreateMLImageAnnotation]
let splits: [CreateMLDocumentSplit]
do {
    allAnnotations = try JSONDecoder().decode(
        [CreateMLImageAnnotation].self,
        from: Data(contentsOf: folder.appendingPathComponent("annotations.json")))
    splits = try JSONDecoder().decode(
        [CreateMLDocumentSplit].self,
        from: Data(contentsOf: folder.appendingPathComponent("splits.json")))
} catch {
    fail("cannot read dataset: \(error)")
}

let trainImages = VisionTrainSplit.images(in: "train", splits: splits)
let validationImages = VisionTrainSplit.images(in: "validation", splits: splits)
let testImages = VisionTrainSplit.images(in: "test", splits: splits)
if trainImages.isEmpty { fail("train partition is empty, nothing to train on") }
let trainAnnotations = VisionTrainSplit.annotations(for: trainImages, from: allAnnotations)
let trainEmpty = trainAnnotations.filter { $0.annotations.isEmpty }.count
print("dataset: \(folder.path)")
print("train: \(trainImages.count) pages (\(trainEmpty) empty)  validation: \(validationImages.count)  test: \(testImages.count)")
print("labels in train: \(Set(trainAnnotations.flatMap { $0.annotations.map(\.label) }).sorted().joined(separator: ", "))")

// Build the train-only folder CreateML expects: images plus annotations.json.
let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("vision-train-\(UUID().uuidString)", isDirectory: true)
let trainDir = scratch.appendingPathComponent("train", isDirectory: true)
do {
    try FileManager.default.createDirectory(at: trainDir, withIntermediateDirectories: true)
    for name in trainImages {
        try FileManager.default.copyItem(at: folder.appendingPathComponent(name),
                                         to: trainDir.appendingPathComponent(name))
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(trainAnnotations).write(to: trainDir.appendingPathComponent("annotations.json"), options: .atomic)
} catch {
    fail("cannot stage train data: \(error)")
}

var parameters = MLObjectDetector.ModelParameters()
parameters.maxIterations = maxIterations
parameters.algorithm = .transferLearning(.objectPrint(revision: 1))
print("training: transferLearning(objectPrint) maxIterations=\(maxIterations)")

let trainStart = Date()
let job: MLJob<MLObjectDetector>
do {
    job = try MLObjectDetector.train(
        trainingData: .directoryWithImagesAndJsonAnnotation(at: trainDir),
        annotationType: .boundingBox(units: .pixel, origin: .topLeft, anchor: .center),
        parameters: parameters)
} catch {
    fail("training failed to start (empty pages in train: \(trainEmpty)): \(error)")
}
// Written by the Combine callback on a background executor, read after the
// semaphore fires, so the semaphore is the only synchronisation needed.
nonisolated(unsafe) var trainedBox: MLObjectDetector?
nonisolated(unsafe) var trainErrorBox: Error?
let done = DispatchSemaphore(value: 0)
let cancellable = job.result.sink(
    receiveCompletion: { @Sendable completion in
        if case .failure(let error) = completion { trainErrorBox = error }
        done.signal()
    },
    receiveValue: { @Sendable model in trainedBox = model; done.signal() })
var lastProgressLine = ""
while done.wait(timeout: .now() + 10) == .timedOut {
    let doneCount = job.progress.completedUnitCount
    let total = job.progress.totalUnitCount
    let line = "progress: \(doneCount)/\(total)  \(job.progress.localizedDescription)"
    if line != lastProgressLine { print(line); lastProgressLine = line }
}
cancellable.cancel()
let trainSeconds = Date().timeIntervalSince(trainStart)
if let trainErrorBox { fail("training failed: \(trainErrorBox)") }
guard let detector = trainedBox else { fail("training finished without a model and without an error") }
let peakAfterTrain = peakRSSBytes()
print(String(format: "trained in %.0f s (%.1f s/page, %.1f s/page/iteration)  peak RSS %.1f GB",
             trainSeconds, trainSeconds / Double(max(trainImages.count, 1)),
             trainSeconds / Double(max(trainImages.count, 1)) / Double(maxIterations),
             Double(peakAfterTrain) / 1e9))

let modelsDir = outDir ?? scratch.appendingPathComponent("models", isDirectory: true)
try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
let modelURL = modelsDir.appendingPathComponent("Detector.mlmodel")
do {
    try detector.write(to: modelURL)
} catch {
    fail("cannot write model: \(error)")
}
let compiledURL: URL
do {
    compiledURL = try MLModel.compileModel(at: modelURL)
} catch {
    fail("cannot compile model: \(error)")
}
print("model: \(modelURL.path)")
print("compiled: \(compiledURL.path)")

let vnModel: VNCoreMLModel
do {
    vnModel = try VNCoreMLModel(for: MLModel(contentsOf: compiledURL))
} catch {
    fail("cannot load compiled model: \(error)")
}

@MainActor
func predict(imageNames: [String]) throws -> [SecurityElement] {
    var predicted: [SecurityElement] = []
    for (index, name) in imageNames.enumerated() {
        let imageURL = folder.appendingPathComponent(name)
        let request = VNCoreMLRequest(model: vnModel)
        try VNImageRequestHandler(url: imageURL).perform([request])
        for observation in (request.results as? [VNRecognizedObjectObservation]) ?? [] {
            guard let top = observation.labels.first else { continue }
            guard let kind = VisionTrainSplit.kind(forTrainingLabel: top.identifier) else { continue }
            let box = observation.boundingBox
            predicted.append(SecurityElement(
                kind: kind, pageIndex: index,
                boundingBox: NormalizedRect(x: Double(box.minX), y: Double(box.minY),
                                            width: Double(box.width), height: Double(box.height)),
                confidence: Double(top.confidence), detectionSource: "learned(spike)"))
        }
    }
    return predicted
}

@MainActor
func report(partition: String, imageNames: [String]) throws {
    if imageNames.isEmpty { print("\(partition): empty partition"); return }
    let truth = VisionTrainSplit.annotations(for: imageNames, from: allAnnotations)
    var sizes: [String: CGSize] = [:]
    for name in imageNames {
        guard let size = CreateMLExporter.imageSize(at: folder.appendingPathComponent(name)) else {
            fail("cannot read size of \(name)")
        }
        sizes[name] = size
    }
    let predicted = try predict(imageNames: imageNames)
    let perLabel = DetectionEvaluator.score(predicted: predicted, truth: truth,
                                            imageSizes: sizes, pageOrder: imageNames, iouThreshold: iou)
    print("\(partition): \(imageNames.count) pages, \(predicted.count) predicted boxes (iou \(iou))")
    for (label, m) in perLabel.sorted(by: { $0.key < $1.key }) {
        print(String(format: "  %-22s TP %4d FP %4d FN %4d  P %.2f R %.2f F1 %.2f",
                     label, m.truePositives, m.falsePositives, m.falseNegatives,
                     m.precision, m.recall, m.f1))
    }
}

let scoreStart = Date()
try report(partition: "validation", imageNames: validationImages)
try report(partition: "test", imageNames: testImages)
print(String(format: "scored in %.0f s  peak RSS %.1f GB",
             Date().timeIntervalSince(scoreStart), Double(peakRSSBytes()) / 1e9))
