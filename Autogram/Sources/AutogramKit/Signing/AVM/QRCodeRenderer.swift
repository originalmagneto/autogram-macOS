import Foundation
import CoreImage
import CoreGraphics

public enum QRCodeRenderer {
    /// Renders `text` as a QR code with medium error correction, scaled with
    /// nearest-neighbour sampling so modules stay crisp.
    public static func image(for text: String, side: Int) -> CGImage? {
        guard !text.isEmpty, side > 0,
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }

        let scale = (CGFloat(side) / output.extent.width).rounded(.up)
        let scaled = output
            .samplingNearest()
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext(options: [.useSoftwareRenderer: false])
        let target = CGRect(x: 0, y: 0, width: side, height: side)
        return context.createCGImage(scaled, from: target)
    }
}
