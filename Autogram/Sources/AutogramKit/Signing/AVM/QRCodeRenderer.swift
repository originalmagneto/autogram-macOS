import Foundation
import CoreImage
import CoreGraphics

public enum QRCodeRenderer {
    /// Renders `text` as a QR code with medium error correction. Modules are scaled by
    /// an integer factor with nearest-neighbour sampling and the whole code (including
    /// its quiet zone) is centred on a white square of `side` pixels, so nothing is cropped.
    public static func image(for text: String, side: Int) -> CGImage? {
        guard !text.isEmpty, side > 0,
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }

        let moduleWidth = output.extent.width
        guard moduleWidth > 0 else { return nil }
        let scale = max(1, (CGFloat(side) / moduleWidth).rounded(.down))
        let scaledSize = moduleWidth * scale
        let offset = ((CGFloat(side) - scaledSize) / 2).rounded(.down)

        let code = output
            .samplingNearest()
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: offset - output.extent.minX * scale,
                                               y: offset - output.extent.minY * scale))
        let target = CGRect(x: 0, y: 0, width: side, height: side)
        let composed = code.composited(over: CIImage(color: .white).cropped(to: target))
        let context = CIContext(options: [.useSoftwareRenderer: false])
        return context.createCGImage(composed, from: target)
    }
}
