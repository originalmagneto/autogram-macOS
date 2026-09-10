import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers
import AutogramKit

// Usage: avm-probe <file.pdf|file.asice> [--level PAdES_BASELINE_B] [--container ASiC-E] [--base-url <url>] [--out <dir>] [--timeout <seconds>]
// Uploads the file to the AVM server, prints the QR link, writes avm-qr.png into the
// output directory, polls until the phone signs, then saves the signed file and prints signers.

var args = Array(CommandLine.arguments.dropFirst())
guard let inputPath = args.first else {
    FileHandle.standardError.write(Data("usage: avm-probe <file> [--level L] [--container C] [--base-url U] [--out DIR] [--timeout S]\n".utf8))
    exit(2)
}
args.removeFirst()
let options: [String] = args

func option(_ name: String) -> String? {
    guard let i = options.firstIndex(of: name), i + 1 < options.count else { return nil }
    return options[i + 1]
}

let input = URL(fileURLWithPath: inputPath)
let data = try Data(contentsOf: input)
let ext = input.pathExtension.lowercased()
let isContainer = ext == "asice" || ext == "sce"
let mimeType = isContainer ? AVMUploadRequest.asicEMimeType : AVMUploadRequest.pdfMimeType
let level = AVMSignatureLevel(rawValue: option("--level") ?? "") ?? (isContainer ? .xadesB : .padesB)
let container = option("--container").flatMap(AVMContainer.init(rawValue:))
let baseURL = option("--base-url").flatMap(URL.init(string:)) ?? AVMClient.publicBaseURL
let outDir = URL(fileURLWithPath: option("--out") ?? FileManager.default.currentDirectoryPath, isDirectory: true)
let timeoutSeconds = Double(option("--timeout") ?? "900") ?? 900

let client = AVMClient(baseURL: baseURL)
let key = AVMDocumentKey.generate()
let request = AVMUploadRequest(filename: input.lastPathComponent, data: data, mimeType: mimeType,
                               level: level, container: container)

func writePNG(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

// Top-level code runs on the main actor and the semaphore blocks it, so the work must be detached.
let semaphore = DispatchSemaphore(value: 0)
Task.detached {
    do {
        print("Uploading \(input.lastPathComponent) (\(data.count) bytes) as \(mimeType), level \(level.rawValue), container \(container?.rawValue ?? "none")")
        let reference = try await client.upload(request, key: key)
        let qrURL = client.qrCodeURL(for: reference)
        print("GUID: \(reference.guid)")
        print("QR link: \(qrURL.absoluteString)")
        if let image = QRCodeRenderer.image(for: qrURL.absoluteString, side: 512) {
            let qrPath = outDir.appendingPathComponent("avm-qr.png")
            writePNG(image, to: qrPath)
            print("QR image: \(qrPath.path) (open it and scan with the iPhone camera)")
            NSWorkspace.shared.open(qrPath)
        }
        let start = Date()
        while Date().timeIntervalSince(start) < timeoutSeconds {
            let result = try await client.fetchSigned(reference)
            if case .signed(let document) = result {
                guard let payload = document.data else { throw AVMError.invalidResponse }
                let name = document.filename ?? "signed-\(input.lastPathComponent)"
                let target = outDir.appendingPathComponent("avm-signed-\(name)")
                try payload.write(to: target)
                print("Signed file: \(target.path) (\(payload.count) bytes, \(document.mimeType ?? "unknown mime"))")
                for signer in document.signers ?? [] {
                    print("Signer: \(signer.signedBy ?? "?") issued by \(signer.issuedBy ?? "?")")
                }
                print("Qualified: \(AVMResultMapper.isQualified(signers: document.signers ?? []))")
                print("Mandate: \(AVMResultMapper.isMandate(signers: document.signers ?? []))")
                semaphore.signal()
                return
            }
            try await Task.sleep(for: .seconds(1))
        }
        print("Timed out, deleting document")
        try? await client.delete(reference)
        exit(1)
    } catch {
        FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}
semaphore.wait()
