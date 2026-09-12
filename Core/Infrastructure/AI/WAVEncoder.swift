import Foundation

public enum WAVEncoder {
    public static func encode(_ segment: AudioSegment) throws -> Data {
        guard segment.sampleRate == 16_000, !segment.samples.isEmpty,
              segment.samples.count <= 960_000 else { throw AudioPipelineError.invalidFormat }
        let byteCount = UInt32(segment.samples.count * 2)
        var output = Data()
        output.append(Data("RIFF".utf8)); append(UInt32(36) + byteCount, to: &output)
        output.append(Data("WAVEfmt ".utf8)); append(UInt32(16), to: &output)
        append(UInt16(1), to: &output); append(UInt16(1), to: &output)
        append(UInt32(16_000), to: &output); append(UInt32(32_000), to: &output)
        append(UInt16(2), to: &output); append(UInt16(16), to: &output)
        output.append(Data("data".utf8)); append(byteCount, to: &output)
        for sample in segment.samples {
            let bounded = sample.isFinite ? min(1, max(-1, sample)) : 0
            append(Int16(bounded * 32_767), to: &output)
        }
        return output
    }
    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }
}
