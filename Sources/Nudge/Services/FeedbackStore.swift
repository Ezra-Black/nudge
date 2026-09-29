import Foundation

/// One answer to "Did I do good?", with what Nudge said, so the answer can be judged later.
struct FeedbackEntry: Codable, Equatable {
    struct Said: Codable, Equatable {
        var title: String
        var explanation: String
    }
    var date: Date
    var app: String
    /// "tour", "area" or "goal".
    var guide: String
    var helpful: Bool
    var note: String
    var overview: String
    var steps: [Said]
}

/// Keeps feedback in a JSON-lines file on this Mac only. Nothing is ever sent anywhere.
struct FeedbackStore {
    /// `~/Library/Application Support/Nudge/Feedback.jsonl`.
    static let standard = FeedbackStore(
        file: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nudge/Feedback.jsonl"))

    let file: URL

    var exists: Bool { FileManager.default.fileExists(atPath: file.path) }

    /// Adds one entry as a line of JSON at the end of the file, creating it when needed.
    func append(_ entry: FeedbackEntry) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var line = try encoder.encode(entry)
        line.append(0x0A)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: file)
        }
    }

    /// Every entry in the file, oldest first. Lines that can't be read are skipped.
    func entries() -> [FeedbackEntry] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text.split(separator: "\n").compactMap { try? decoder.decode(FeedbackEntry.self, from: Data($0.utf8)) }
    }
}
