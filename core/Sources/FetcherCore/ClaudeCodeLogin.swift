#if os(macOS)
import Foundation
import Darwin

/// Starts the installed, unmodified Claude Code client's browser login.
///
/// Call only after an explicit connection action. Claude Code owns its existing
/// configuration and credentials; Houdini neither reads the login output nor
/// implements OAuth. Successful process exit still needs a provider check.
public struct ClaudeCodeLogin: Sendable {
    public enum LoginError: Error, Equatable, LocalizedError {
        case missingClient
        case failed
        case cancelled
        case timedOut

        public var errorDescription: String? {
            switch self {
            case .missingClient: "Claude Code is not installed or cannot be opened."
            case .failed: "Claude Code could not complete sign-in. Try signing in from your terminal."
            case .cancelled: "Claude Code sign-in was cancelled."
            case .timedOut: "Claude Code sign-in timed out. Try signing in from your terminal."
            }
        }
    }

    private let executableURL: URL
    private let timeout: Duration

    public init(executableURL: URL, timeout: Duration = .seconds(300)) {
        self.executableURL = executableURL
        self.timeout = timeout
    }

    /// Resolves usual native/Homebrew install locations without invoking a shell.
    /// Explicit candidates let callers support another user-selected installation.
    public static func findExecutable(candidateURLs: [URL]? = nil) -> URL? {
        let candidates = candidateURLs ?? [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude"),
        ]
        return candidates.first(where: isExecutableFile)
    }

    public func signIn() async throws {
        let session = LoginProcess(executableURL: executableURL, timeout: timeout)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                session.start(continuation)
            }
        } onCancel: {
            session.cancel()
        }
    }

    fileprivate static func isExecutableFile(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
            && FileManager.default.isExecutableFile(atPath: url.path)
    }
}

/// All mutable process state belongs to `queue`. Process launch/wait never blocks
/// the main actor; completion, timeout, and cancellation are serialized here.
private final class LoginProcess: @unchecked Sendable {
    private let queue = DispatchQueue(label: "org.salomao.houdini.claude-login")
    private let executableURL: URL
    private let timeout: Duration
    private var process: Process?
    private var continuation: CheckedContinuation<Void, any Error>?
    private var stopReason: ClaudeCodeLogin.LoginError?
    private var timeoutWork: DispatchWorkItem?
    private var forceStopWork: DispatchWorkItem?
    private var finished = false

    init(executableURL: URL, timeout: Duration) {
        self.executableURL = executableURL
        self.timeout = timeout
    }

    func start(_ continuation: CheckedContinuation<Void, any Error>) {
        queue.async { [self] in
            self.continuation = continuation
            if let stopReason = self.stopReason {
                self.finish(.failure(stopReason))
                return
            }
            guard ClaudeCodeLogin.isExecutableFile(self.executableURL) else {
                self.finish(.failure(ClaudeCodeLogin.LoginError.missingClient))
                return
            }
            guard self.timeout > .zero else {
                self.finish(.failure(ClaudeCodeLogin.LoginError.timedOut))
                return
            }

            let process = Process()
            process.executableURL = self.executableURL
            process.arguments = ["auth", "login", "--claudeai"]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { [weak self] _ in
                guard let self else { return }
                self.queue.async { self.didTerminate() }
            }
            self.process = process
            do {
                try process.run()
            } catch {
                // Never expose Foundation errors: they may include paths or output.
                self.finish(.failure(ClaudeCodeLogin.LoginError.failed))
                return
            }

            let work = DispatchWorkItem { [weak self] in self?.stop(.timedOut) }
            self.timeoutWork = work
            let components = self.timeout.components
            let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
            self.queue.asyncAfter(deadline: .now() + seconds, execute: work)
        }
    }

    func cancel() {
        queue.async { self.stop(.cancelled) }
    }

    private func stop(_ reason: ClaudeCodeLogin.LoginError) {
        guard !finished, stopReason == nil else { return }
        stopReason = reason
        // Cancellation may arrive before start installs its continuation.
        guard let process, process.isRunning else { return }
        process.terminate()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let process = self.process, process.isRunning else { return }
            // Escalate only this child; never signal a process group or another CLI.
            Darwin.kill(process.processIdentifier, SIGKILL)
        }
        forceStopWork = work
        queue.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func didTerminate() {
        guard let process, !finished else { return }
        if let stopReason {
            finish(.failure(stopReason))
        } else if process.terminationReason == .exit && process.terminationStatus == 0 {
            finish(.success(()))
        } else {
            finish(.failure(ClaudeCodeLogin.LoginError.failed))
        }
    }

    private func finish(_ result: Result<Void, any Error>) {
        guard !finished else { return }
        finished = true
        timeoutWork?.cancel()
        forceStopWork?.cancel()
        process?.terminationHandler = nil
        process = nil
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(with: result)
    }
}
#endif
