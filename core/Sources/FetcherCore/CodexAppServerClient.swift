import Foundation
#if os(macOS)
import Darwin
#endif

/// Only fixed, safe messages cross this boundary. The server may put OAuth URLs,
/// tokens, or account details in arbitrary errors; never forward its raw payload.
public enum CodexClientError: Error, LocalizedError, CustomStringConvertible, Sendable, Equatable {
    case missingClient, unsupportedVersion, needsLogin, protocolFailure, timedOut
    case loginFailed, browserUnavailable

    public var description: String {
        switch self {
        case .missingClient: return "Install the official Codex CLI to connect."
        case .unsupportedVersion: return "This Codex CLI version is unsupported. Houdini requires Codex 0.150.x."
        case .needsLogin: return "Connect Codex in Houdini."
        case .protocolFailure: return "Codex could not provide subscription data. Try again or reconnect."
        case .timedOut: return "Codex did not respond in time. Try again."
        case .loginFailed: return "Codex sign-in did not complete. Try connecting again."
        case .browserUnavailable: return "The sign-in page could not be opened in your browser."
        }
    }
    public var errorDescription: String? { description }
}

/// Owns a separate Codex home; the official client alone handles OAuth secrets.
/// Each operation closes its subprocess, including timeout and task cancellation.
public struct CodexAppServerClient: Sendable {
    private let executableURL: URL?
    private let stateDirectory: URL?
    private let requestTimeout: TimeInterval
    private let loginTimeout: TimeInterval

    public init(executableURL: URL? = nil, stateDirectory: URL? = nil) {
        self.init(executableURL: executableURL, stateDirectory: stateDirectory,
                  requestTimeout: 20, loginTimeout: 300)
    }

    init(executableURL: URL?, stateDirectory: URL?, requestTimeout: TimeInterval, loginTimeout: TimeInterval) {
        self.executableURL = executableURL
        self.stateDirectory = stateDirectory
        self.requestTimeout = requestTimeout
        self.loginTimeout = loginTimeout
    }

    public func fetch() async throws -> [UsageMetric] {
        #if os(macOS)
        let channel = try await connect()
        defer { channel.close() }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await requireChatGPT(channel)
            let result = try await channel.request("account/rateLimits/read", params: [:], timeout: requestTimeout)
            guard let data = try? JSONSerialization.data(withJSONObject: result) else {
                throw CodexClientError.protocolFailure
            }
            return try CodexUsageProvider.parse(data)
        } onCancel: { channel.cancel() }
        #else
        throw CodexClientError.missingClient
        #endif
    }

    public func signIn(openURL: @escaping @Sendable (URL) async -> Bool) async throws {
        #if os(macOS)
        let channel = try await connect()
        defer { channel.close() }
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let result = try await channel.request("account/login/start", params: ["type": "chatgpt"], timeout: requestTimeout)
            guard result["type"] as? String == "chatgpt",
                  let loginID = result["loginId"] as? String, !loginID.isEmpty,
                  let address = result["authUrl"] as? String,
                  let url = Self.validatedAuthorizationURL(address) else {
                throw CodexClientError.protocolFailure
            }
            guard await openURL(url) else { throw CodexClientError.browserUnavailable }
            let deadline = CodexProcessChannel.deadline(after: loginTimeout)
            while true {
                let frame = try await channel.nextFrame(until: deadline)
                guard frame["method"] as? String == "account/login/completed",
                      let params = frame["params"] as? [String: Any],
                      params["loginId"] as? String == loginID else { continue }
                guard params["success"] as? Bool == true else { throw CodexClientError.loginFailed }
                try await requireChatGPT(channel)
                return
            }
        } onCancel: { channel.cancel() }
        #else
        throw CodexClientError.missingClient
        #endif
    }

    static func validatedAuthorizationURL(_ address: String) -> URL? {
        guard let url = URL(string: address), let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "https", components.user == nil, components.password == nil,
              components.port == nil || components.port == 443,
              let host = components.host?.lowercased(),
              ["auth.openai.com", "auth.chatgpt.com", "chatgpt.com"].contains(host) else { return nil }
        return url
    }

    #if os(macOS)
    private func requireChatGPT(_ channel: CodexProcessChannel) async throws {
        let result = try await channel.request("account/read", params: ["refreshToken": false], timeout: requestTimeout)
        guard let account = result["account"] as? [String: Any], account["type"] as? String == "chatgpt" else {
            throw CodexClientError.needsLogin
        }
    }

    private func connect() async throws -> CodexProcessChannel {
        try Task.checkCancellation()
        let executable = try resolveExecutable()
        let directory = try prepareDirectory()
        let environment = Self.processEnvironment(directory: directory)
        let probe = try CodexProcessChannel(executable: executable, arguments: ["--version"], directory: directory, environment: environment)
        let version: Data
        do {
            version = try await withTaskCancellationHandler {
                try await probe.nextLine(until: CodexProcessChannel.deadline(after: requestTimeout))
            } onCancel: { probe.cancel() }
        } catch { probe.close(); throw error }
        probe.close()
        // Bound support to the protocol/storage implementation inspected at
        // rust-v0.150.1. Widen after validating a newer generated schema.
        guard let versionString = String(data: version, encoding: .utf8),
              versionString.range(of: #"^codex-cli 0\.150\.[0-9]+$"#, options: .regularExpression) != nil else {
            throw CodexClientError.unsupportedVersion
        }
        try Task.checkCancellation()
        let channel = try CodexProcessChannel(
            executable: executable,
            arguments: ["-c", "cli_auth_credentials_store=\"keyring\"", "-c", "analytics.enabled=false", "app-server", "--stdio"],
            directory: directory, environment: environment
        )
        do {
            try await withTaskCancellationHandler {
                try Task.checkCancellation()
                let result = try await channel.request("initialize", params: [
                    "clientInfo": ["name": "houdini", "title": "Houdini", "version": "0.1.0"]
                ], timeout: requestTimeout)
                guard let serverHome = result["codexHome"] as? String,
                      URL(fileURLWithPath: serverHome).resolvingSymlinksInPath().standardizedFileURL.path == directory.path else {
                    throw CodexClientError.protocolFailure
                }
                try channel.send(["method": "initialized", "params": [:]])
            } onCancel: { channel.cancel() }
            return channel
        } catch { channel.close(); throw error }
    }

    private func resolveExecutable() throws -> URL {
        let userDirectory = FileManager.default.homeDirectoryForCurrentUser
        let candidates = executableURL.map { [$0] } ?? [
            userDirectory.appendingPathComponent(".local/bin/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex")
        ]
        guard let candidate = candidates.first(where: { $0.isFileURL && FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw CodexClientError.missingClient
        }
        return candidate
    }

    private func prepareDirectory() throws -> URL {
        let manager = FileManager.default
        let userDirectory = manager.homeDirectoryForCurrentUser
        let proposed = stateDirectory ?? userDirectory.appendingPathComponent("Library/Application Support/Houdini/Codex", isDirectory: true)
        let canonical = proposed.resolvingSymlinksInPath().standardizedFileURL
        let personal = userDirectory.appendingPathComponent(".codex", isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
        guard canonical.isFileURL, canonical.path != personal.path,
              !canonical.path.hasPrefix(personal.path + "/") else { throw CodexClientError.protocolFailure }
        do {
            try manager.createDirectory(at: canonical, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: canonical.path)
        } catch { throw CodexClientError.protocolFailure }
        return canonical
    }

    static func processEnvironment(directory: URL) -> [String: String] {
        // An allowlist avoids inheriting tokens, proxies, alternate providers,
        // injected node options, or the development session's CODEX_HOME.
        ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
         "CODEX_HOME": directory.path, "LANG": "en_US.UTF-8"]
    }
    #endif
}

#if os(macOS)
/// Reads are serialized by the operation that owns this channel. Only cancel /
/// close run concurrently; their state and process lifecycle use the lock.
private final class CodexProcessChannel: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let lock = NSLock()
    private var cancelled = false
    private var closed = false
    private var buffer = Data()
    private var nextID = 0
    private var deferredNotifications: [[String: Any]] = []
    private static let maximumFrameBytes = 1_048_576

    init(executable: URL, arguments: [String], directory: URL, environment: [String: String]) throws {
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw CodexClientError.missingClient }
        // A closed child stdin is an error, never a SIGPIPE in the host app.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
    }

    static func deadline(after seconds: TimeInterval) -> TimeInterval {
        ProcessInfo.processInfo.systemUptime + seconds
    }

    func cancel() {
        lock.withLock { cancelled = true }
        close()
    }

    func close() {
        lock.withLock {
            guard !closed else { return }
            closed = true
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
        }
        // Escalation remains scoped to this Process object, avoiding PID reuse.
        let child = process
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        }
    }

    func send(_ message: [String: Any]) throws {
        try checkCancellation()
        guard var data = try? JSONSerialization.data(withJSONObject: message) else { throw CodexClientError.protocolFailure }
        data.append(0x0a)
        do { try input.fileHandleForWriting.write(contentsOf: data) }
        catch { try checkCancellation(); throw CodexClientError.protocolFailure }
    }

    func request(_ method: String, params: [String: Any], timeout: TimeInterval) async throws -> [String: Any] {
        nextID += 1
        let id = nextID
        try send(["id": id, "method": method, "params": params])
        let deadline = Self.deadline(after: timeout)
        while true {
            let frame = try await readFrame(until: deadline)
            if let responseID = frame["id"] as? Int {
                guard responseID == id, frame["error"] == nil,
                      let result = frame["result"] as? [String: Any] else { throw CodexClientError.protocolFailure }
                return result
            }
            // Keep login completion even when it arrives before login/start's
            // response. Other notifications are irrelevant to a one-shot read.
            if frame["method"] as? String == "account/login/completed" {
                guard deferredNotifications.count < 8 else { throw CodexClientError.protocolFailure }
                deferredNotifications.append(frame)
            }
        }
    }

    func nextFrame(until deadline: TimeInterval) async throws -> [String: Any] {
        if !deferredNotifications.isEmpty { return deferredNotifications.removeFirst() }
        return try await readFrame(until: deadline)
    }

    private func readFrame(until deadline: TimeInterval) async throws -> [String: Any] {
        let line = try await nextLine(until: deadline)
        guard let frame = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            throw CodexClientError.protocolFailure
        }
        return frame
    }

    func nextLine(until deadline: TimeInterval) async throws -> Data {
        // poll/read run on a bounded-duration worker, never on the UI executor.
        try await Task.detached { try self.readLine(until: deadline) }.value
    }

    private func checkCancellation() throws {
        if lock.withLock({ cancelled }) { throw CancellationError() }
    }

    private func readLine(until deadline: TimeInterval) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 8_192)
        while true {
            try checkCancellation()
            if let newline = buffer.firstIndex(of: 0x0a) {
                guard newline <= Self.maximumFrameBytes else { throw CodexClientError.protocolFailure }
                var line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                if line.last == 0x0d { line.removeLast() }
                return line
            }
            guard buffer.count <= Self.maximumFrameBytes else { throw CodexClientError.protocolFailure }
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw CodexClientError.timedOut }
            var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 100)
            if ready < 0 { if errno == EINTR { continue }; throw CodexClientError.protocolFailure }
            if ready == 0 { continue }
            let count = read(descriptor.fd, &bytes, bytes.count)
            guard count > 0 else {
                try checkCancellation()
                if count < 0 && errno == EINTR { continue }
                throw CodexClientError.protocolFailure
            }
            buffer.append(contentsOf: bytes.prefix(count))
        }
    }
}
#endif
