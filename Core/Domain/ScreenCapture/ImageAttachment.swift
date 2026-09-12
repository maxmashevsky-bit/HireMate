import Foundation

/// Изображение живёт только в памяти. Намеренно не Codable: история не сохраняет bytes снимка.
public struct ImageAttachment: Sendable, Identifiable {
    public let id: UUID
    public let data: Data
    public let mimeType: String
    public let width: Int
    public let height: Int
    public init(data: Data, mimeType: String, width: Int, height: Int) throws {
        guard ["image/png", "image/jpeg"].contains(mimeType), !data.isEmpty, data.count <= 8_388_608,
              width > 0, height > 0, width <= 4096, height <= 4096 else { throw ProviderError.responseTooLarge }
        id = UUID(); self.data = data; self.mimeType = mimeType; self.width = width; self.height = height
    }
    public var dataURL: String { "data:\(mimeType);base64,\(data.base64EncodedString())" }
}
