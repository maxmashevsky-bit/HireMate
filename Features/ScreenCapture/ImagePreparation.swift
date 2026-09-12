import AppKit
import ImageIO
import UniformTypeIdentifiers
import CopilotCore

enum ScreenshotEncoding: String, CaseIterable, Identifiable {
    case png, jpeg
    var id: String { rawValue }
    var title: String { self == .png ? "PNG · текст и код" : "JPEG · фотографии" }
}

@MainActor
enum ImagePreparation {
    static func encode(_ image: CGImage, format: ScreenshotEncoding) throws -> ImageAttachment {
        let bytes = NSMutableData()
        let type = format == .png ? UTType.png.identifier : UTType.jpeg.identifier
        guard let destination = CGImageDestinationCreateWithData(bytes, type as CFString, 1, nil) else { throw ScreenCaptureError.emptyImage }
        // Переносим только pixels: EXIF, URL и названия окон не включаются.
        let options = format == .jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary : nil
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else { throw ScreenCaptureError.emptyImage }
        return try ImageAttachment(data: bytes as Data, mimeType: format == .png ? "image/png" : "image/jpeg", width: image.width, height: image.height)
    }
    static func decode(_ attachment: ImageAttachment) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(attachment.data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ScreenCaptureError.emptyImage }
        return image
    }
    static func crop(_ image: CGImage, normalized rect: CGRect) throws -> CGImage {
        let pixels = try region(rect, width: image.width, height: image.height)
        guard let result = image.cropping(to: pixels) else { throw ScreenCaptureError.invalidRegion }
        return result
    }
    static func redact(_ image: CGImage, normalized rect: CGRect) throws -> CGImage {
        let bounds = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
        let pixels = try region(rect, width: image.width, height: image.height).insetBy(dx: -4, dy: -4).intersection(bounds)
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ScreenCaptureError.emptyImage }
        context.draw(image, in: bounds)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: pixels.minX, y: CGFloat(image.height) - pixels.maxY, width: pixels.width, height: pixels.height))
        guard let result = context.makeImage() else { throw ScreenCaptureError.emptyImage }
        return result
    }
    private static func region(_ rect: CGRect, width: Int, height: Int) throws -> CGRect {
        guard rect.minX.isFinite, rect.minY.isFinite, rect.width.isFinite, rect.height.isFinite else { throw ScreenCaptureError.invalidRegion }
        let bounded = rect.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !bounded.isNull else { throw ScreenCaptureError.invalidRegion }
        let pixels = CGRect(x: bounded.minX * CGFloat(width), y: bounded.minY * CGFloat(height),
                            width: bounded.width * CGFloat(width), height: bounded.height * CGFloat(height)).integral
            .intersection(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        guard pixels.width >= 2, pixels.height >= 2 else { throw ScreenCaptureError.invalidRegion }
        return pixels
    }
}
