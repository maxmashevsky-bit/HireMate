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

    func testTenMinuteManualSessionKeepsAudioMemoryBounded() async throws {
        let pipeline = AudioPipeline()
        await pipeline.configure(AudioPipelineConfiguration(), mode: .manual)
        await pipeline.beginManual()
        let frameSamples = Array(repeating: Float(0.2), count: 8_000)
        var completedSegments = 0
        var maximumBufferedSeconds = 0.0
        for index in 0..<1_200 {
            let update = try await pipeline.process(AudioFrame(timestamp: Double(index) * 0.5,
                                                               source: .microphone, sampleRate: 16_000,
                                                               samples: frameSamples))
            maximumBufferedSeconds = max(maximumBufferedSeconds, update.bufferedSeconds)
            if let segment = update.segment {
                completedSegments += 1
                XCTAssertLessThanOrEqual(segment.samples.count, 960_000)
                XCTAssertLessThanOrEqual(segment.duration, 60)
            }
        }
        XCTAssertEqual(completedSegments, 10)
        XCTAssertLessThanOrEqual(maximumBufferedSeconds, 60)
        let recent = await pipeline.oneShot()
        XCTAssertEqual(recent.first?.duration ?? 0, 20, accuracy: 0.001)
    }
}
