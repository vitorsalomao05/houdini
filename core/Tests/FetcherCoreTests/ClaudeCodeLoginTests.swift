#if os(macOS)
import Testing
import Foundation
import Darwin
@testable import FetcherCore

@Suite struct ClaudeCodeLoginTests {
    @Test func launchesOfficialArgumentsWithClosedInputAndDiscardsOutput() async throws {
        let fixture = try LoginFixture(script: """
            [ "$#" -eq 3 ] || exit 11
            [ "$1" = auth ] || exit 12
            [ "$2" = login ] || exit 13
            [ "$3" = --claudeai ] || exit 14
            read input && exit 15
            printf 'FAKE-SECRET-MUST-NOT-BE-SURFACED'
            printf 'FAKE-SECRET-MUST-NOT-BE-SURFACED' >&2
            exit 0
            """)
        defer { fixture.remove() }
        try await ClaudeCodeLogin(executableURL: fixture.executable).signIn()
    }

    @Test func failureDoesNotExposeClientOutput() async throws {
        let fixture = try LoginFixture(script: """
            printf 'FAKE-SECRET-MUST-NOT-BE-SURFACED'
            printf 'FAKE-SECRET-MUST-NOT-BE-SURFACED' >&2
            exit 9
            """)
        defer { fixture.remove() }
        do {
            try await ClaudeCodeLogin(executableURL: fixture.executable).signIn()
            Issue.record("Expected nonzero exit to fail")
        } catch {
            #expect(error as? ClaudeCodeLogin.LoginError == .failed)
            #expect(!error.localizedDescription.contains("FAKE-SECRET"))
            #expect(!String(describing: error).contains("FAKE-SECRET"))
        }
    }

    @Test func missingOrNonExecutableClientIsSafe() async throws {
        let fixture = try LoginFixture(script: "exit 0")
        defer { fixture.remove() }
        let missing = fixture.directory.appendingPathComponent("missing")
        await #expect(throws: ClaudeCodeLogin.LoginError.missingClient) {
            try await ClaudeCodeLogin(executableURL: missing).signIn()
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fixture.executable.path)
        await #expect(throws: ClaudeCodeLogin.LoginError.missingClient) {
            try await ClaudeCodeLogin(executableURL: fixture.executable).signIn()
        }
    }

    @Test func locatorSkipsDirectoriesAndPreservesCandidateOrder() throws {
        let first = try LoginFixture(script: "exit 0")
        let second = try LoginFixture(script: "exit 0")
        defer { first.remove(); second.remove() }
        let missing = first.directory.appendingPathComponent("missing")
        #expect(ClaudeCodeLogin.findExecutable(candidateURLs: [missing, first.directory, second.executable, first.executable]) == second.executable)
        #expect(ClaudeCodeLogin.findExecutable(candidateURLs: [missing, first.directory]) == nil)
    }

    @Test func timeoutWaitsForItsChildToExit() async throws {
        let fixture = try LoginFixture(longRunning: true)
        defer { fixture.remove() }
        await #expect(throws: ClaudeCodeLogin.LoginError.timedOut) {
            try await ClaudeCodeLogin(executableURL: fixture.executable, timeout: .seconds(2)).signIn()
        }
        let pid = try fixture.readPID()
        #expect(Darwin.kill(pid, 0) == -1)
        #expect(errno == ESRCH)
    }

    @Test func timeoutAlsoStopsChildThatIgnoresTermination() async throws {
        let fixture = try LoginFixture(longRunning: true, ignoresTermination: true)
        defer { fixture.remove() }
        await #expect(throws: ClaudeCodeLogin.LoginError.timedOut) {
            try await ClaudeCodeLogin(executableURL: fixture.executable, timeout: .seconds(2)).signIn()
        }
        #expect(Darwin.kill(try fixture.readPID(), 0) == -1)
    }

    @Test func cancellationStopsOnlyItsChild() async throws {
        let fixture = try LoginFixture(longRunning: true)
        let otherFixture = try LoginFixture(longRunning: true)
        defer { fixture.remove(); otherFixture.remove() }
        let other = Process()
        other.executableURL = otherFixture.executable
        try other.run()
        defer { if other.isRunning { other.terminate(); other.waitUntilExit() } }
        let task = Task { try await ClaudeCodeLogin(executableURL: fixture.executable).signIn() }
        defer { task.cancel() }
        try await fixture.waitForPID()
        task.cancel()
        await #expect(throws: ClaudeCodeLogin.LoginError.cancelled) { try await task.value }
        #expect(Darwin.kill(try fixture.readPID(), 0) == -1)
        #expect(other.isRunning)
    }

    @Test func cancellationBeforeLaunchDoesNotStartClient() async throws {
        let fixture = try LoginFixture(longRunning: true)
        defer { fixture.remove() }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await ClaudeCodeLogin(executableURL: fixture.executable).signIn()
        }
        await #expect(throws: ClaudeCodeLogin.LoginError.cancelled) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: fixture.pidFile.path))
    }
}

private struct LoginFixture: Sendable {
    let directory: URL
    let executable: URL
    var pidFile: URL { directory.appendingPathComponent("child.pid") }

    init(script: String = "", longRunning: Bool = false, ignoresTermination: Bool = false) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("Houdini Login \(UUID().uuidString)")
        executable = directory.appendingPathComponent("fake claude")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let body = longRunning
            ? "printf '%s' \"$$\" > '\(directory.appendingPathComponent("child.pid").path)'\nexec /bin/sleep 30"
            : script
        let signalSetup = ignoresTermination ? "trap '' TERM\n" : ""
        try ("#!/bin/sh\n" + signalSetup + body + "\n").write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    }

    func waitForPID() async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while (try? String(contentsOf: pidFile, encoding: .utf8)).flatMap(pid_t.init) == nil {
            guard ContinuousClock.now < deadline else {
                throw CocoaError(.fileReadUnknown)
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func readPID() throws -> pid_t {
        try #require(pid_t(String(contentsOf: pidFile, encoding: .utf8)))
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}
#endif
