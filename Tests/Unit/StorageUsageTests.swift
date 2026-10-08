import XCTest
import CopilotCore

@MainActor
final class StorageUsageTests: XCTestCase {
    func testCountsNestedFilesAndDatabaseWithoutFollowingLinks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hiremate-storage-" + UUID().uuidString)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("hiremate-storage-outside-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        let paths = AppStoragePaths(root: root)
        let inspector = LocalStorageInspector(paths: paths)
        let audio = try await inspector.prepareDirectory(for: .audio)
        let database = try await inspector.prepareDirectory(for: .database)
        try FileManager.default.createDirectory(at: audio.appendingPathComponent("nested"), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 20).write(to: audio.appendingPathComponent("nested/test.wav"))
        try Data(repeating: 2, count: 30).write(to: database.appendingPathComponent("copilot.sqlite"))
        try Data(repeating: 3, count: 10).write(to: root.appendingPathComponent("other.bin"))
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data(repeating: 4, count: 500).write(to: outside.appendingPathComponent("private.bin"))
        try FileManager.default.createSymbolicLink(at: audio.appendingPathComponent("external"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: audio.appendingPathComponent("loop"), withDestinationURL: root)
        try FileManager.default.createSymbolicLink(at: audio.appendingPathComponent("file-link"), withDestinationURL: outside.appendingPathComponent("private.bin"))
        let snapshot = try await inspector.snapshot()
        XCTAssertEqual(snapshot.bytes[.audio], 20)
        XCTAssertEqual(snapshot.bytes[.database], 30)
        XCTAssertEqual(snapshot.bytes[.other], 10)
        XCTAssertEqual(snapshot.totalBytes, 60)
        XCTAssertEqual(snapshot.fileCount, 3)
        XCTAssertEqual(snapshot.unreadableCount, 0)
        XCTAssertEqual(StorageArea.allCases.reduce(0) { $0 + snapshot.fraction(for: $1) }, 1, accuracy: 0.00001)
        try Data(repeating: 5, count: 40).write(to: audio.appendingPathComponent("nested/test.wav"))
        let updated = try await inspector.snapshot()
        XCTAssertEqual(updated.totalBytes, 80)
    }

    func testMissingFolderDoesNotGetCreatedUntilRequestedAndRejectsLinks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hiremate-empty-storage-" + UUID().uuidString)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("hiremate-link-storage-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        let paths = AppStoragePaths(root: root)
        let inspector = LocalStorageInspector(paths: paths)
        let empty = try await inspector.snapshot()
        XCTAssertEqual(empty.totalBytes, 0)
        XCTAssertEqual(empty.fileCount, 0)
        XCTAssertEqual(empty.fraction(for: .audio), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        let logs = try await inspector.prepareDirectory(for: .logs)
        XCTAssertEqual(logs, paths.directory(for: .logs))
        let permissions = try FileManager.default.attributesOfItem(atPath: logs.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o700)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: paths.directory(for: .screenshots), withDestinationURL: outside)
        do { _ = try await inspector.prepareDirectory(for: .screenshots); XCTFail("Ссылку нельзя открывать как папку приложения") }
        catch { XCTAssertTrue(error is StorageInspectionError) }
    }

    func testActualDatabaseFilesAreIncluded() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hiremate-db-storage-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppStoragePaths(root: root)
        let repository = GRDBMeetingRepository(directory: paths.directory(for: .database))
        _ = try await repository.profiles()
        let snapshot = try await LocalStorageInspector(paths: paths).snapshot()
        XCTAssertGreaterThan(snapshot.bytes[.database, default: 0], 0)
        XCTAssertEqual(snapshot.totalBytes, snapshot.bytes[.database])
        XCTAssertGreaterThanOrEqual(snapshot.fileCount, 1)
        XCTAssertEqual(snapshot.unreadableCount, 0)
    }

    func testCancelledInspectionDoesNotTraverseFiles() async throws {
        let inspector = LocalStorageInspector()
        let task = Task { try Task.checkCancellation(); return try await inspector.snapshot() }
        task.cancel()
        do { _ = try await task.value; XCTFail("Ожидалась отмена") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}
