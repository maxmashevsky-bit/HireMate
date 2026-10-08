import Foundation

public enum StorageArea: String, CaseIterable, Identifiable, Sendable {
    case audio, interviews, screenshots, logs, database, other
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .audio: "Аудиозаписи"
        case .interviews: "Записи собеседований"
        case .screenshots: "Скриншоты"
        case .logs: "Логи приложения"
        case .database: "База встреч и заметок"
        case .other: "Прочие файлы"
        }
    }
    fileprivate var directoryName: String? {
        switch self {
        case .audio: "Audio"
        case .interviews: "Interviews"
        case .screenshots: "Screenshots"
        case .logs: "Logs"
        case .database: "Database"
        case .other: nil
        }
    }
}

public struct AppStoragePaths: Sendable {
    public let root: URL
    public init(root: URL) { self.root = root.standardizedFileURL }
    public static var standard: Self {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return Self(root: support.appendingPathComponent("dev.maxmashevsky.MaxInterviewCopilot", isDirectory: true))
    }
    public func directory(for area: StorageArea) -> URL {
        area.directoryName.map { root.appendingPathComponent($0, isDirectory: true) } ?? root
    }
    fileprivate func area(for url: URL) -> StorageArea {
        let rootComponents = root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let component = url.resolvingSymlinksInPath().standardizedFileURL.pathComponents.dropFirst(rootComponents.count).first
        return StorageArea.allCases.first { $0.directoryName == component } ?? .other
    }
}

public struct StorageSnapshot: Sendable {
    public let bytes: [StorageArea: Int64]
    public let fileCount: Int
    public let unreadableCount: Int
    public let inspectedAt: Date
    public init(bytes: [StorageArea: Int64], fileCount: Int, unreadableCount: Int = 0, inspectedAt: Date = Date()) {
        self.bytes = bytes.mapValues { max(0, $0) }
        self.fileCount = max(0, fileCount)
        self.unreadableCount = max(0, unreadableCount)
        self.inspectedAt = inspectedAt
    }
    public var totalBytes: Int64 { bytes.values.reduce(0, +) }
    public func fraction(for area: StorageArea) -> Double {
        totalBytes > 0 ? Double(bytes[area, default: 0]) / Double(totalBytes) : 0
    }
}

public protocol StorageInspecting: Sendable {
    func snapshot() async throws -> StorageSnapshot
    func prepareDirectory(for area: StorageArea) async throws -> URL
}

public enum StorageInspectionError: LocalizedError {
    case invalidDirectory
    public var errorDescription: String? { "Папка данных недоступна или заменена символической ссылкой." }
}

/// Читает только метаданные внутри папки приложения. Ссылки не обходятся; содержимое файлов не читается.
public actor LocalStorageInspector: StorageInspecting {
    private let paths: AppStoragePaths
    private let files = FileManager()
    public init(paths: AppStoragePaths = .standard) { self.paths = paths }

    public func snapshot() async throws -> StorageSnapshot {
        try Task.checkCancellation()
        var bytes: [StorageArea: Int64] = [:]
        var fileCount = 0, unreadableCount = 0
        if files.fileExists(atPath: paths.root.path) {
            try validateDirectory(paths.root)
            var pending = [paths.root]
            let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]
            while let directory = pending.popLast() {
                try Task.checkCancellation()
                guard isContained(directory) else { continue }
                let children: [URL]
                do { children = try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys)) }
                catch { unreadableCount += 1; continue }
                for url in children {
                    try Task.checkCancellation()
                    do {
                        let values = try url.resourceValues(forKeys: keys)
                        guard values.isSymbolicLink != true, isContained(url) else { continue }
                        if values.isDirectory == true { pending.append(url) }
                        else if values.isRegularFile == true {
                            bytes[paths.area(for: url), default: 0] += Int64(max(0, values.fileSize ?? 0))
                            fileCount += 1
                        }
                    } catch { unreadableCount += 1 }
                }
            }
        }
        return StorageSnapshot(bytes: bytes, fileCount: fileCount, unreadableCount: unreadableCount, inspectedAt: Date())
    }

    public func prepareDirectory(for area: StorageArea) async throws -> URL {
        try Task.checkCancellation()
        if files.fileExists(atPath: paths.root.path) { try validateDirectory(paths.root) }
        let target = paths.directory(for: area)
        guard isContained(target) else { throw StorageInspectionError.invalidDirectory }
        if files.fileExists(atPath: target.path) { try validateDirectory(target) }
        try files.createDirectory(at: target, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try validateDirectory(target)
        return target
    }

    private func validateDirectory(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw StorageInspectionError.invalidDirectory }
    }

    private func isContained(_ url: URL) -> Bool {
        url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
            .starts(with: paths.root.resolvingSymlinksInPath().standardizedFileURL.pathComponents)
    }
}
