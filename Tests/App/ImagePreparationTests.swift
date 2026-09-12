import XCTest
import CoreGraphics

final class ImagePreparationTests: XCTestCase {
    private func fixture() throws -> CGImage {
        var bytes = [UInt8]()
        for y in 0..<32 {
            for x in 0..<32 {
                bytes += y < 16 ? (x < 16 ? [255, 0, 0, 255] : [0, 255, 0, 255]) : [0, 0, 255, 255]
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        return try XCTUnwrap(CGImage(width: 32, height: 32, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 128,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }
    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        let data = try XCTUnwrap(image.dataProvider?.data)
        let pointer = try XCTUnwrap(CFDataGetBytePtr(data))
        let start = y * image.bytesPerRow + x * (image.bitsPerPixel / 8)
        return [pointer[start], pointer[start + 1], pointer[start + 2]]
    }
    @MainActor
    func testCropMatchesTopLeftPreviewCoordinates() throws {
        let crop = try ImagePreparation.crop(fixture(), normalized: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        XCTAssertEqual(crop.width, 16); XCTAssertEqual(crop.height, 16)
        XCTAssertEqual(try pixel(crop, x: 4, y: 4), [255, 0, 0])
    }
    @MainActor
    func testRedactionChangesTopLeftAndPreservesBottom() throws {
        let output = try ImagePreparation.redact(fixture(), normalized: CGRect(x: 0, y: 0, width: 0.25, height: 0.25))
        XCTAssertEqual(try pixel(output, x: 3, y: 3), [0, 0, 0])
        XCTAssertEqual(try pixel(output, x: 3, y: 28), [0, 0, 255])
        XCTAssertEqual(try pixel(output, x: 28, y: 3), [0, 255, 0])
    }
    @MainActor
    func testInvalidRegionRejectedAndPNGDimensionsPreserved() throws {
        let image = try fixture()
        XCTAssertThrowsError(try ImagePreparation.crop(image, normalized: CGRect(x: 2, y: 2, width: 1, height: 1)))
        XCTAssertThrowsError(try ImagePreparation.crop(image, normalized: .zero))
        let attachment = try ImagePreparation.encode(image, format: .png)
        let decoded = try ImagePreparation.decode(attachment)
        XCTAssertEqual(attachment.mimeType, "image/png")
        XCTAssertEqual(decoded.width, 32); XCTAssertEqual(decoded.height, 32)
        XCTAssertEqual(try pixel(decoded, x: 3, y: 3), [255, 0, 0])
    }
}
