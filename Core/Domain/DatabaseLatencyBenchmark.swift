import Foundation

public struct LatencySummary: Sendable, Equatable {
    public let sampleCount: Int
    public let minimumMilliseconds: Double
    public let p95Milliseconds: Double
    public let maximumMilliseconds: Double

    public init(samplesMilliseconds: [Double]) {
        let sorted = samplesMilliseconds.filter { $0.isFinite && $0 >= 0 }.sorted()
        sampleCount = sorted.count
        minimumMilliseconds = sorted.first ?? 0
        maximumMilliseconds = sorted.last ?? 0
        let rank = max(0, min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.95)) - 1))
        p95Milliseconds = sorted.isEmpty ? 0 : sorted[rank]
    }
}

public struct LocalDatabaseBenchmark: Sendable {
    private let repository: any MeetingRepository

    public init(repository: any MeetingRepository) {
        self.repository = repository
    }

    public func measureMeetings(profile: ProfileID, sampleCount: Int = 20) async throws -> LatencySummary {
        let count = min(100, max(5, sampleCount))
        var samples: [Double] = []
        samples.reserveCapacity(count)
        for _ in 0..<count {
            try Task.checkCancellation()
            let startedAt = ContinuousClock.now
            _ = try await repository.meetings(profile: profile)
            samples.append(Self.milliseconds(startedAt.duration(to: .now)))
        }
        return LatencySummary(samplesMilliseconds: samples)
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
