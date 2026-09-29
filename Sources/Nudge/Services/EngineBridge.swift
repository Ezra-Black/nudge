import Foundation

struct EngineReply<T: Decodable>: Decodable {
    var ok: Bool
    var data: T?
    var error: String?
}
struct Hello: Decodable { var protocolVersion: Int? }

/// One bundled child process, private pipes, one outstanding command at a time. No listening socket.
final class EngineBridge: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Nudge.engine")
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()

    func call<T: Decodable>(_ command: String, _ fields: [String: Any] = [:], as: T.Type) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    try start()
                    var payload = fields
                    payload["version"] = 1
                    payload["command"] = command
                    var data = try JSONSerialization.data(withJSONObject: payload)
                    data.append(10)
                    try input?.write(contentsOf: data)
                    while !buffer.contains(10) {
                        guard let chunk = output?.availableData, !chunk.isEmpty else {
                            throw NudgeError("Nudge’s guide engine stopped. Quit and reopen Nudge.")
                        }
                        buffer.append(chunk)
                        guard buffer.count < 1_000_000 else { throw NudgeError("The guide engine returned too much data.") }
                    }
                    let end = buffer.firstIndex(of: 10)!
                    let line = buffer[..<end]
                    let reply = try JSONDecoder().decode(EngineReply<T>.self, from: line)
                    buffer.removeSubrange(...end)
                    guard reply.ok, let value = reply.data else { throw NudgeError(reply.error ?? "The guide could not be prepared.") }
                    continuation.resume(returning: value)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    private func start() throws {
        if let process, process.isRunning { return }
        let exe = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/nudge-engine")
        guard FileManager.default.isExecutableFile(atPath: exe.path) else {
            throw NudgeError("Open the built Nudge.app. Its bundled guide engine is missing from this launch.")
        }
        let child = Process()
        child.executableURL = exe
        let toChild = Pipe()
        let fromChild = Pipe()
        child.standardInput = toChild
        child.standardOutput = fromChild
        child.standardError = FileHandle.nullDevice
        try child.run()
        process = child
        input = toChild.fileHandleForWriting
        output = fromChild.fileHandleForReading
        buffer.removeAll()
    }
    func shutdown() {
        queue.async { [self] in
            try? input?.close()
            if process?.isRunning == true { process?.terminate() }
            process = nil
        }
    }
}
