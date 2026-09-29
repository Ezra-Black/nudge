import Foundation
import Testing

@testable import Nudge

@Suite("Feedback store")
struct FeedbackStoreTests {
    private func temporaryStore() -> FeedbackStore {
        FeedbackStore(
            file: FileManager.default.temporaryDirectory.appendingPathComponent("nudge-tests-\(UUID().uuidString)/Feedback.jsonl"))
    }

    @Test("Entries are appended one per line and read back in order")
    func appendAndRead() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.file.deletingLastPathComponent()) }
        #expect(!store.exists)
        let first = FeedbackEntry(
            date: Date(timeIntervalSince1970: 1_800_000_000), app: "Safari", guide: "tour", helpful: true, note: "", overview: "A page.",
            steps: [.init(title: "Back", explanation: "Goes to the previous page.")])
        var second = first
        second.helpful = false
        second.note = "The Share button was explained wrong."
        try store.append(first)
        try store.append(second)
        #expect(store.exists)
        #expect(store.entries() == [first, second])
        let lines = try String(contentsOf: store.file, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 2)
    }

    @Test("A damaged line doesn't hide the others")
    func skipsDamagedLines() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.file.deletingLastPathComponent()) }
        let entry = FeedbackEntry(
            date: Date(timeIntervalSince1970: 0), app: "Mail", guide: "area", helpful: true, note: "", overview: "", steps: [])
        try store.append(entry)
        let handle = try FileHandle(forWritingTo: store.file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("not json\n".utf8))
        try handle.close()
        try store.append(entry)
        #expect(store.entries().count == 2)
    }
}
