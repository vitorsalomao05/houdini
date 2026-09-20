import AppKit
import Combine
import FetcherCore

enum TrackedSubscription: String, CaseIterable, Identifiable {
    case claude
    case chatgptCodex

    var id: String { rawValue }
    var displayName: String { self == .claude ? "Claude" : "Codex" }
    var shortName: String { self == .claude ? "Claude" : "Codex" }
    var metricChoices: [PrimaryMetricChoice] {
        self == .claude ? PrimaryMetricChoice.allCases : [.auto, .fiveHour, .weekly]
    }
}

/// Selects the source shared by the menu bar, popover and desktop widget.
/// Each official client owns its authentication; Houdini only initiates login.
@MainActor
final class SubscriptionSession: ObservableObject {
    @Published private(set) var selected: TrackedSubscription
    @Published private var codexSigningIn = false
    @Published private var codexError: String?

    let claude: ClaudeSession
    private let codexClient: CodexAppServerClient
    private var codexLoginTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    var onAuthChange: (() -> Void)?

    init(settings: AppSettings, claude: ClaudeSession? = nil,
         codexClient: CodexAppServerClient = .init()) {
        self.selected = settings.subscription
        self.claude = claude ?? ClaudeSession(settings: settings)
        self.codexClient = codexClient
        self.claude.onAuthChange = { [weak self] in
            guard let self, self.selected == .claude else { return }
            self.onAuthChange?()
        }
        self.claude.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        settings.$subscription.dropFirst().removeDuplicates().sink { [weak self] value in
            guard let self else { return }
            self.cancelSignIn()
            self.selected = value
            self.onAuthChange?()
        }.store(in: &cancellables)
    }

    var currentProvider: (any UsageProvider)? {
        switch selected {
        case .claude: return claude.currentProvider
        case .chatgptCodex: return CodexUsageProvider(client: codexClient)
        }
    }

    var displayName: String { selected.displayName }
    var isSigningIn: Bool { selected == .claude ? claude.isSigningIn : codexSigningIn }
    var lastError: String? { selected == .claude ? claude.lastError : codexError }
    var connectionContext: String {
        switch selected {
        case .claude:
            return "Uses Claude Code to open your browser. Signing in updates your Claude Code session."
        case .chatgptCodex:
            return "Shows quota usage and resets reported by the official Codex client."
        }
    }
    var setupLabel: String { selected == .claude ? "Set up Claude Code…" : "Set up Codex…" }
    var setupURL: URL {
        URL(string: selected == .claude
            ? "https://code.claude.com/docs/en/setup"
            : "https://developers.openai.com/codex/cli")!
    }

    func refresh() {
        if selected == .claude { claude.refresh() }
    }

    func signIn() {
        if selected == .claude { claude.signIn(); return }
        guard codexLoginTask == nil else { return }
        codexError = nil
        codexSigningIn = true
        codexLoginTask = Task { [weak self] in
            guard let self else { return }
            defer { self.codexSigningIn = false; self.codexLoginTask = nil }
            do {
                try await self.codexClient.signIn { url in
                    await MainActor.run { NSWorkspace.shared.open(url) }
                }
                try Task.checkCancellation()
                // The model verifies quota access; login completion alone is not
                // displayed as a successful usage reading.
                if self.selected == .chatgptCodex { self.onAuthChange?() }
            } catch is CancellationError {
            } catch let error as CodexClientError {
                self.codexError = error.localizedDescription
            } catch {
                self.codexError = "Codex sign-in did not finish. Try connecting again."
            }
        }
    }

    func cancelSignIn() {
        claude.cancelSignIn()
        codexLoginTask?.cancel()
    }
}
