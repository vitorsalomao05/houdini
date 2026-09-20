import Foundation

// Normalized data model shared by every frontend. The UI never special-cases a
// provider; it reads `Capabilities` and renders whatever `UsageMetric`s arrive.
// Contract mirrors PROVIDERS.md.

/// How a provider authenticates against its backend.
public enum AuthMethod: String, Sendable, Codable {
    case keychainOAuth
    case sessionCookie
    case adminApiKey
}

/// What a provider can actually supply. UI/registry adapt to these flags (ADR-007).
public struct Capabilities: OptionSet, Sendable, Codable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let usagePct      = Capabilities(rawValue: 1 << 0)
    public static let resetTimer    = Capabilities(rawValue: 1 << 1)
    public static let dollarBalance = Capabilities(rawValue: 1 << 2)
}

/// One normalized usage figure (e.g. the 5-hour window, the weekly window, or an
/// overage dollar balance). Optional fields let each provider fill only what it
/// can supply — synthesized Codable omits the `nil` ones from JSON.
public struct UsageMetric: Sendable, Codable, Equatable {
    public let label: String        // "5-hour", "Weekly", "Opus weekly", "Extra usage ($)"
    public var pct: Double?          // 0–100
    public var used: Double?
    public var limit: Double?
    public var resetAt: Date?
    public var dollars: Double?
    /// The provider's quota-window duration, when supplied. A reset timestamp
    /// alone does not establish the window's length.
    public var windowDurationMinutes: Int?
    public let providerId: String

    public init(
        label: String,
        pct: Double? = nil,
        used: Double? = nil,
        limit: Double? = nil,
        resetAt: Date? = nil,
        dollars: Double? = nil,
        providerId: String,
        windowDurationMinutes: Int? = nil
    ) {
        self.label = label
        self.pct = pct
        self.used = used
        self.limit = limit
        self.resetAt = resetAt
        self.dollars = dollars
        self.providerId = providerId
        self.windowDurationMinutes = windowDurationMinutes
    }
}

/// A point-in-time, normalized result for one provider. Consumed by every frontend.
public struct UsageSnapshot: Sendable, Codable {
    public let providerId: String
    public let displayName: String
    public let capturedAt: Date
    public let metrics: [UsageMetric]

    public init(providerId: String, displayName: String, capturedAt: Date, metrics: [UsageMetric]) {
        self.providerId = providerId
        self.displayName = displayName
        self.capturedAt = capturedAt
        self.metrics = metrics
    }
}
