import XCTest
import CopilotCore

final class AudioContinuityTests: XCTestCase {
    private func frame(_ time: Double, source: AudioSource = .microphone, level: Float = 0.2) -> AudioFrame {
        AudioFrame(timestamp: time, source: source, sampleRate: 16_000,
                   samples: Array(repeating: level, count: 1_600))
    }

    func testGapInterruptsInsteadOfJoiningDisconnectedSpeech() async throws {
        let pipeline = AudioPipeline()
        await pipeline.beginManual()
        _ = try await pipeline.process(frame(1))
        do {
            _ = try await pipeline.process(frame(2))
            XCTFail("Разрыв доставки не должен превращаться в непрерывную запись")
        } catch AudioPipelineError.interrupted { }
        let segments = await pipeline.finishManual()
        XCTAssertEqual(segments.first?.samples.count, 1_600)
    }

    func testIndependentSourcesAndRecordedSilenceAreAccepted() async throws {
        let pipeline = AudioPipeline()
        _ = try await pipeline.process(frame(1))
        _ = try await pipeline.process(frame(10, source: .system))
        for index in 1...10 {
            _ = try await pipeline.process(frame(1 + Double(index) * 0.1, level: 0))
            _ = try await pipeline.process(frame(10 + Double(index) * 0.1, source: .system, level: 0))
        }
        let segments = await pipeline.oneShot()
        XCTAssertEqual(Set(segments.map(\.source)), Set(AudioSource.allCases))
    }

    func testClearResetsContinuityForNewSession() async throws {
        let pipeline = AudioPipeline()
        _ = try await pipeline.process(frame(1))
        await pipeline.clear()
        let update = try await pipeline.process(frame(50))
        XCTAssertEqual(update.bufferedSeconds, 0.1, accuracy: 0.001)
    }
}
