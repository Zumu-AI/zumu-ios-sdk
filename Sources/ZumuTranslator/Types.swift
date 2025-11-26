import Foundation

// MARK: - Session State

/// Current state of the translation session
public enum SessionState: Equatable {
    case idle          // No active session
    case connecting    // Establishing connection
    case active        // Session in progress
    case disconnected  // Connection lost
    case ending        // Session terminating
    case error(String) // Error occurred
}

// MARK: - Agent State

/// Current state of the AI agent
public enum AgentState: Equatable {
    case idle          // Agent inactive
    case listening     // Agent is listening to user
    case processing    // Processing speech/translation
    case thinking      // Thinking about response
    case speaking      // Agent is speaking
}

// MARK: - Session Configuration

/// Configuration for starting a translation session
public struct SessionConfig {
    public let driverName: String
    public let driverLanguage: String
    public let passengerName: String
    public let passengerLanguage: String?
    public let tripId: String?
    public let pickupLocation: String?
    public let dropoffLocation: String?

    public init(
        driverName: String,
        driverLanguage: String,
        passengerName: String,
        passengerLanguage: String? = nil,
        tripId: String? = nil,
        pickupLocation: String? = nil,
        dropoffLocation: String? = nil
    ) {
        self.driverName = driverName
        self.driverLanguage = driverLanguage
        self.passengerName = passengerName
        self.passengerLanguage = passengerLanguage
        self.tripId = tripId
        self.pickupLocation = pickupLocation
        self.dropoffLocation = dropoffLocation
    }
}

// MARK: - Translation Session

/// Active translation session
public struct TranslationSession: Identifiable {
    public let id: String
    public let status: String
    public let createdAt: String

    public init(id: String, status: String, createdAt: String) {
        self.id = id
        self.status = status
        self.createdAt = createdAt
    }
}

// MARK: - Translation Message

/// A message in the translation conversation
public struct TranslationMessage: Identifiable {
    public let id: String
    public let role: String  // "user", "agent", "system"
    public let content: String
    public let timestamp: Date

    public init(id: String, role: String, content: String, timestamp: Date) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

// MARK: - Connection Quality

/// Connection quality metrics
public enum ConnectionQuality {
    case excellent
    case good
    case poor
}

// MARK: - Errors

/// Zumu SDK errors
public enum ZumuError: Error, LocalizedError {
    case invalidState(String)
    case networkError(String)
    case permissionDenied(String)
    case invalidParameters(String)

    public var errorDescription: String? {
        switch self {
        case .invalidState(let message): return "Invalid state: \(message)"
        case .networkError(let message): return "Network error: \(message)"
        case .permissionDenied(let message): return "Permission denied: \(message)"
        case .invalidParameters(let message): return "Invalid parameters: \(message)"
        }
    }
}
