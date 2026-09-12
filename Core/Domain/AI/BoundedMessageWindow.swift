import Foundation

public struct MessageWindowResult: Sendable, Equatable {
    public let messages: [ChatMessage]
    public let omittedCount: Int
    public let clippedCount: Int
}

public struct BoundedMessageWindow: Sendable {
    public let maximumMessages: Int
    public let maximumCharacters: Int

    public init(maximumMessages: Int = 200, maximumCharacters: Int = 1_000_000) {
        self.maximumMessages = max(2, maximumMessages)
        self.maximumCharacters = max(1_024, maximumCharacters)
    }

    public func apply(to history: [ChatMessage]) -> MessageWindowResult {
        var remaining = maximumCharacters
        var newestFirst: [ChatMessage] = []
        var omitted = 0
        var clipped = 0
        for message in history.reversed() {
            guard newestFirst.count < maximumMessages else { omitted += 1; continue }
            if message.content.count <= remaining {
                newestFirst.append(message)
                remaining -= message.content.count
                continue
            }
            guard newestFirst.isEmpty else { omitted += 1; continue }
            var bounded = message
            let marker = "\n\n[Сообщение сокращено в окне; полная версия остаётся в сохраняемой истории.]"
            bounded.content = String(message.content.prefix(max(0, maximumCharacters - marker.count))) + marker
            newestFirst.append(bounded)
            clipped += 1
            remaining = 0
        }
        return MessageWindowResult(messages: newestFirst.reversed(), omittedCount: omitted, clippedCount: clipped)
    }
}
