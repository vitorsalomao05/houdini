import Foundation
import Testing
@testable import FetcherCore
#if os(macOS)
import Darwin
#endif

@Suite struct CodexUsageParserTests {
    @Test func preservesBucketsAndMissingWindowMetadata() throws {
        let data = Data(#"{"rateLimits":{"primary":{"usedPercent":99}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":0,"windowDurationMins":300,"resetsAt":1900000000},"secondary":null},"review":{"limitName":"Review","primary":{"usedPercent":32},"secondary":{"usedPercent":50,"windowDurationMins":10080}}}}"#.utf8)
        let metrics = try CodexUsageProvider.parse(data)
        #expect(metrics.count == 3)
        #expect(metrics.map(\.pct) == [0, 32, 50])
        #expect(metrics.map(\.label) == ["codex · 5-hour", "Review · Primary", "Review · 7-day"])
        #expect(metrics[0].resetAt == Date(timeIntervalSince1970: 1_900_000_000))
        #expect(metrics[1].resetAt == nil)
        #expect(metrics.allSatisfy { $0.providerId == "chatgpt-codex" && $0.limit == nil })
    }

    @Test func emptyAndSparseAreNotZero() throws {
        #expect(try CodexUsageProvider.parse(Data(#"{"rateLimits":{}}"#.utf8)).isEmpty)
        let metrics = try CodexUsageProvider.parse(Data(#"{"rateLimits":{"secondary":{"usedPercent":15}},"rateLimitsByLimitId":{}}"#.utf8))
        #expect(metrics.count == 1)
        #expect(metrics.first?.label == "codex · Secondary")
        #expect(metrics.first?.resetAt == nil)
    }

    @Test(arguments: [
        #"{"rateLimits":{"primary":{}}}"#,
        #"{"rateLimits":{"primary":{"usedPercent":-1}}}"#,
        #"{"rateLimits":{"primary":{"usedPercent":10,"windowDurationMins":0}}}"#,
        #"{"rateLimits":{"primary":{"usedPercent":10,"resetsAt":-1}}}"#,
        #"{"rateLimits":{"primary":{"usedPercent":"FAKE-SECRET"}}}"#
    ]) func malformedPayloadHasSafeError(payload: String) {
        #expect(throws: CodexClientError.protocolFailure) {
            try CodexUsageProvider.parse(Data(payload.utf8))
        }
    }

    @Test func reportedOverageAndDistinctBucketIDsArePreserved() throws {
        let metrics = try CodexUsageProvider.parse(Data(#"{"rateLimits":{},"rateLimitsByLimitId":{"a":{"limitName":"Review","primary":{"usedPercent":110}},"b":{"limitName":"Review","primary":{"usedPercent":20}}}}"#.utf8))
        #expect(metrics.map(\.label) == ["Review (a) · Primary", "Review (b) · Primary"])
        #expect(metrics.first?.pct == 110)
    }

    @Test func authorizationURLIsHTTPSAndExactHost() {
        #expect(CodexAppServerClient.validatedAuthorizationURL("https://auth.openai.com/oauth/authorize?state=fake") != nil)
        #expect(CodexAppServerClient.validatedAuthorizationURL("https://chatgpt.com/auth") != nil)
        for url in ["http://auth.openai.com", "https://auth.openai.com.evil.test", "https://user@auth.openai.com", "file:///tmp/foo", "https://evil.test", "https://auth.openai.com:9999"] {
            #expect(CodexAppServerClient.validatedAuthorizationURL(url) == nil)
        }
    }
}

#if os(macOS)
/// Real pipe/Process boundary against a synthetic executable. Never launches
/// Codex, contacts the network, or reads the system Keychain.
private struct FakeCodex {
    let root: URL
    let client: CodexAppServerClient
    let requests: URL
    let pid: URL

    // Use the production request budget for protocol assertions. On a fresh
    // Xcode runner, Python's first launch alone can consume most of two seconds;
    // that bootstrap is not the protocol failure these tests are exercising.
    init(mode: String = "success", timeout: TimeInterval = 20) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("houdini-fake-codex-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let script = root.appendingPathComponent("codex")
        requests = root.appendingPathComponent("requests.jsonl")
        pid = root.appendingPathComponent("pid")
        let protocolBody = #"""
        #!/usr/bin/python3
        import sys, json, os
        mode = 'MODE'
        if '--version' in sys.argv:
            print('codex-cli 0.149.0' if mode == 'old' else 'codex-cli 0.150.1', flush=True)
            sys.exit(0)
        root = os.path.dirname(__file__)
        with open(root + '/pid', 'w') as f: f.write(str(os.getpid()))
        with open(root + '/environment.json', 'w') as f: json.dump(dict(os.environ), f)
        with open(root + '/arguments.json', 'w') as f: json.dump(sys.argv, f)
        def emit(value):
            text = json.dumps(value) + '\n'
            if mode == 'fragmented':
                for start in range(0, len(text), 7):
                    sys.stdout.write(text[start:start+7]); sys.stdout.flush()
            else:
                sys.stdout.write(text); sys.stdout.flush()
        for line in sys.stdin:
            request = json.loads(line)
            with open(root + '/requests.jsonl', 'a') as f: f.write(line)
            method = request['method']
            if method == 'initialized': continue
            if mode == 'eof': sys.exit(0)
            if mode == 'oversize': print('x' * 1100000, flush=True); continue
            if mode == 'error':
                emit({'id':request['id'], 'error':{'code':-1,'message':'FAKE-SECRET'}}); continue
            if method == 'initialize':
                result = {'codexHome': '/wrong-home' if mode == 'wrongHome' else os.environ['CODEX_HOME']}
            elif method == 'account/login/start':
                emit({'method':'account/login/completed','params':{'loginId':'another-login','success':False}})
                emit({'method':'account/login/completed','params':{'loginId':'fixture-login','success':True}})
                result = {'type':'chatgpt','loginId':'fixture-login','authUrl':'https://auth.openai.com/oauth/authorize?state=fake'}
            elif method == 'account/read':
                result = {'account': None if mode == 'signedOut' else {'type':'apiKey' if mode == 'apiKey' else 'chatgpt'}}
            elif method == 'account/rateLimits/read':
                result = {'rateLimits':{'limitId':'codex','primary':{'usedPercent':25,'windowDurationMins':300}}}
            else:
                sys.exit(5)
            emit({'id':request['id'],'result':result})
        """#.replacingOccurrences(of: "MODE", with: mode)
        // Timeout/cancellation only need a child that never responds. Keep that
        // fixture on shell builtins to avoid Python/Xcode bootstrap overhead.
        let stalledBody = #"""
        #!/bin/sh
        if [ "$1" = "--version" ]; then
            printf '%s\n' 'codex-cli 0.150.1'
            exit 0
        fi
        printf '%s' "$$" > "${0%/*}/pid"
        while IFS= read -r line; do :; done
        """#
        let body = mode == "timeout" ? stalledBody : protocolBody
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        client = CodexAppServerClient(executableURL: script, stateDirectory: root.appendingPathComponent("state"), requestTimeout: timeout, loginTimeout: timeout)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
    func requestMethods() throws -> [String] {
        try String(contentsOf: requests, encoding: .utf8).split(separator: "\n").map {
            let object = try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any]
            return object["method"] as! String
        }
    }
}

@Suite struct CodexAppServerTransportTests {
    @Test(arguments: ["success", "fragmented"])
    func fetchUsesOnlyAccountAndLimits(mode: String) async throws {
        let fake = try FakeCodex(mode: mode)
        defer { fake.remove() }
        let metrics = try await fake.client.fetch()
        #expect(metrics.first?.pct == 25)
        #expect(try fake.requestMethods() == ["initialize", "initialized", "account/read", "account/rateLimits/read"])
        let environment = try JSONSerialization.jsonObject(with: Data(contentsOf: fake.root.appendingPathComponent("environment.json"))) as! [String: String]
        #expect(environment["CODEX_HOME"] == fake.root.appendingPathComponent("state").resolvingSymlinksInPath().path)
        #expect(environment["OPENAI_API_KEY"] == nil)
        #expect(environment["CODEX_ACCESS_TOKEN"] == nil)
        #expect(environment["HTTP_PROXY"] == nil)
        let arguments = try JSONSerialization.jsonObject(with: Data(contentsOf: fake.root.appendingPathComponent("arguments.json"))) as! [String]
        #expect(arguments.contains("cli_auth_credentials_store=\"keyring\""))
    }

    @Test func signInKeepsEarlyCompletionAndIgnoresOtherLogin() async throws {
        let fake = try FakeCodex()
        defer { fake.remove() }
        try await fake.client.signIn { url in url.host == "auth.openai.com" }
        #expect(try fake.requestMethods() == ["initialize", "initialized", "account/login/start", "account/read"])
    }

    @Test func browserFailureIsTyped() async throws {
        let fake = try FakeCodex()
        defer { fake.remove() }
        await #expect(throws: CodexClientError.browserUnavailable) {
            try await fake.client.signIn { _ in false }
        }
    }

    @Test(arguments: ["signedOut", "apiKey"])
    func rejectsNonChatGPTBeforeRateRequest(mode: String) async throws {
        let fake = try FakeCodex(mode: mode)
        defer { fake.remove() }
        await #expect(throws: CodexClientError.needsLogin) { try await fake.client.fetch() }
        #expect(!(try fake.requestMethods()).contains("account/rateLimits/read"))
    }

    @Test(arguments: ["eof", "oversize", "error", "wrongHome"])
    func malformedTransportFailsSafely(mode: String) async throws {
        let fake = try FakeCodex(mode: mode)
        defer { fake.remove() }
        do {
            _ = try await fake.client.fetch()
            Issue.record("Expected protocol failure")
        } catch {
            #expect(error as? CodexClientError == .protocolFailure)
            #expect(!String(describing: error).contains("FAKE-SECRET"))
        }
    }

    @Test func oldClientNeverStartsServer() async throws {
        let fake = try FakeCodex(mode: "old")
        defer { fake.remove() }
        await #expect(throws: CodexClientError.unsupportedVersion) { try await fake.client.fetch() }
        #expect(!FileManager.default.fileExists(atPath: fake.pid.path))
    }

    @Test func timeoutAndCancellationStopChild() async throws {
        for cancel in [false, true] {
            // The shell fixture consumes requests but never responds; only
            // the client's timeout/cancellation can finish this operation.
            // The same budget also covers the version probe. A five-second
            // override could expire before the server starts on a busy runner,
            // so no server PID would exist to verify cleanup. Keep the production
            // budget for both paths and retain the PID/termination assertions.
            let fake = try FakeCodex(mode: "timeout")
            defer { fake.remove() }
            let task = Task { try await fake.client.fetch() }
            defer { task.cancel() }
            if cancel {
                let deadline = ContinuousClock.now + .seconds(20)
                while !FileManager.default.fileExists(atPath: fake.pid.path),
                      ContinuousClock.now < deadline {
                    try await Task.sleep(for: .milliseconds(20))
                }
                // Cancelling during interpreter bootstrap would not prove the
                // app-server child is stopped; require server readiness first.
                try #require(FileManager.default.fileExists(atPath: fake.pid.path))
                task.cancel()
            }
            do {
                _ = try await task.value
                Issue.record("Expected cancellation or timeout")
            } catch {
                if cancel { #expect(error is CancellationError) }
                else { #expect(error as? CodexClientError == .timedOut) }
            }
            let childPID = try #require(Int32(String(contentsOf: fake.pid, encoding: .utf8)))
            for _ in 0..<50 {
                if kill(childPID, 0) != 0 { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(kill(childPID, 0) != 0)
        }
    }
}
#endif
