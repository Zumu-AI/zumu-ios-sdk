import Foundation
import Combine
import AVFoundation
import UIKit

/// Zumu Driver Translator SDK for iOS
/// Provides real-time translation for driver-passenger conversations
public class ZumuTranslator: ObservableObject {

    // MARK: - Published Properties

    /// Current session state
    @Published public private(set) var state: SessionState = .idle

    /// Current conversation messages
    @Published public private(set) var messages: [TranslationMessage] = []

    /// Is microphone muted
    @Published public private(set) var isMuted: Bool = false

    /// Active translation session
    @Published public private(set) var session: TranslationSession?

    // MARK: - Private Properties

    private let apiKey: String
    private let baseURL: String
    private var webSocketTask: URLSessionWebSocketTask?
    private var cancellables = Set<AnyCancellable>()
    private var audioEngine: AVAudioEngine?
    private var audioSession: AVAudioSession?
    private var isStarting: Bool = false

    // MARK: - Initialization

    /// Initialize Zumu Translator with API key
    /// - Parameters:
    ///   - apiKey: Your Zumu API key (from dashboard)
    ///   - baseURL: Optional custom base URL (defaults to production)
    public init(apiKey: String, baseURL: String = "https://translator.zumu.ai") {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    // MARK: - Session Management

    /// Start a new translation session
    /// - Parameters:
    ///   - config: Session configuration
    /// - Returns: Started translation session
    /// - Throws: ZumuError if session creation fails
    @MainActor
    public func startSession(config: SessionConfig) async throws -> TranslationSession {
        // Prevent race conditions from double-clicks
        guard !isStarting else {
            throw ZumuError.invalidState("Session start already in progress")
        }

        guard state == .idle else {
            throw ZumuError.invalidState("Cannot start session while in state: \(state)")
        }

        isStarting = true
        defer { isStarting = false }

        state = .connecting
        var createdSession: TranslationSession?

        do {
            // Step 1: Create session on Zumu backend
            let session = try await createBackendSession(config: config)
            createdSession = session
            self.session = session

            // Step 2: Start conversation via Zumu API
            let conversationData = try await startConversation(sessionId: session.id)

            // Step 3: Connect WebSocket for real-time communication
            try await connectWebSocket(signedUrl: conversationData.signedUrl)

            // Step 4: Set up audio capture
            try await setupAudioCapture()

            state = .active
            return session

        } catch {
            // Clean up WebSocket if it was created
            webSocketTask?.cancel(with: .goingAway, reason: nil)
            webSocketTask = nil

            // Clean up audio if it was initialized
            stopAudioCapture()

            // Clean up partial session if created
            if let session = createdSession {
                try? await updateSessionStatus(sessionId: session.id, status: "failed")
            }

            // Reset to idle to allow retry (enterprise-grade error recovery)
            state = .idle
            self.session = nil

            // Provide more detailed error context
            if let networkError = error as? ZumuError {
                throw networkError
            } else {
                throw ZumuError.networkError("Session start failed: \(error.localizedDescription)")
            }
        }
    }

    /// Reset error state to allow retry
    /// Call this when you want to retry after an error
    @MainActor
    public func resetState() {
        state = .idle
        session = nil
        messages = []
        isStarting = false
    }

    /// End the current translation session
    @MainActor
    public func endSession() async {
        guard let session = session else { return }

        state = .ending

        do {
            // Disconnect WebSocket
            webSocketTask?.cancel(with: .goingAway, reason: nil)
            webSocketTask = nil

            // Stop audio capture
            stopAudioCapture()

            // Update backend session status
            try await updateSessionStatus(sessionId: session.id, status: "ended")

            // Reset state
            self.session = nil
            self.messages = []
            state = .idle

        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Send a text message in the conversation
    /// - Parameter text: Message text
    @MainActor
    public func sendMessage(_ text: String) async throws {
        guard webSocketTask != nil else {
            throw ZumuError.invalidState("No active conversation")
        }

        let message = ["type": "text", "content": text]
        let data = try JSONSerialization.data(withJSONObject: message)
        try await webSocketTask?.send(.data(data))
    }

    /// Toggle microphone mute
    @MainActor
    public func toggleMute() {
        guard audioEngine != nil else { return }

        if isMuted {
            audioEngine?.inputNode.removeTap(onBus: 0)
        } else {
            setupAudioTap()
        }

        isMuted.toggle()
    }

    // MARK: - Private Methods

    private func createBackendSession(config: SessionConfig) async throws -> TranslationSession {
        let url = URL(string: "\(baseURL)/api/sessions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "driver_name": config.driverName,
            "driver_language": config.driverLanguage,
            "passenger_name": config.passengerName,
            "passenger_language": config.passengerLanguage as Any,
            "trip_id": config.tripId,
            "pickup_location": config.pickupLocation as Any,
            "dropoff_location": config.dropoffLocation as Any,
            "client_info": [
                "platform": "iOS",
                "sdk_version": "1.0.0",
                "device": UIDevice.current.model
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let errorBody = String(data: data, encoding: .utf8) ?? "No response body"
            throw ZumuError.apiError("Failed to create session (HTTP \(statusCode)): \(errorBody)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        return TranslationSession(
            id: json["session_id"] as! String,
            status: json["status"] as! String,
            createdAt: json["created_at"] as! String
        )
    }

    private func startConversation(sessionId: String) async throws -> ConversationData {
        let url = URL(string: "\(baseURL)/api/conversations/start")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["session_id": sessionId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let errorBody = String(data: data, encoding: .utf8) ?? "No response body"
            throw ZumuError.apiError("Failed to start conversation (HTTP \(statusCode)): \(errorBody)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        return ConversationData(
            signedUrl: json["signed_url"] as! String
        )
    }

    private func connectWebSocket(signedUrl: String) async throws {
        guard let url = URL(string: signedUrl) else {
            throw ZumuError.networkError("Invalid WebSocket URL")
        }

        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()

        // Verify connection is established by sending a ping
        do {
            try await webSocketTask?.sendPing { error in
                if let error = error {
                    print("WebSocket ping failed: \(error)")
                }
            }
        } catch {
            webSocketTask?.cancel(with: .goingAway, reason: nil)
            webSocketTask = nil
            throw ZumuError.networkError("Failed to establish WebSocket connection: \(error.localizedDescription)")
        }

        // Start receiving messages
        Task {
            await receiveWebSocketMessages()
        }
    }

    private func receiveWebSocketMessages() async {
        while let task = webSocketTask {
            do {
                let message = try await task.receive()

                switch message {
                case .data(let data):
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let content = json["content"] as? String,
                       let role = json["role"] as? String {
                        let msg = TranslationMessage(role: role, content: content)
                        await MainActor.run {
                            self.messages.append(msg)
                        }
                    }
                case .string(let text):
                    if let data = text.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let content = json["content"] as? String,
                       let role = json["role"] as? String {
                        let msg = TranslationMessage(role: role, content: content)
                        await MainActor.run {
                            self.messages.append(msg)
                        }
                    }
                @unknown default:
                    break
                }
            } catch {
                // WebSocket disconnected - reset to idle for automatic retry capability
                await MainActor.run {
                    // Only transition to disconnected if we were active
                    // If we were connecting, the error will be caught by startSession
                    if self.state == .active {
                        print("WebSocket connection lost: \(error.localizedDescription)")
                        self.state = .disconnected

                        // Auto-reset to idle after a brief moment to allow retry
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                            if self.state == .disconnected {
                                self.state = .idle
                                self.session = nil
                                self.webSocketTask = nil
                            }
                        }
                    }
                }
                break
            }
        }
    }

    private func setupAudioCapture() async throws {
        do {
            audioSession = AVAudioSession.sharedInstance()

            // Configure audio session with retry on failure
            var retryCount = 0
            while retryCount < 3 {
                do {
                    try audioSession?.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
                    try audioSession?.setActive(true, options: [.notifyOthersOnDeactivation])
                    break
                } catch {
                    retryCount += 1
                    if retryCount >= 3 {
                        throw error
                    }
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                }
            }

            audioEngine = AVAudioEngine()
            setupAudioTap()

            // Start audio engine with retry
            retryCount = 0
            while retryCount < 3 {
                do {
                    try audioEngine?.start()
                    break
                } catch {
                    retryCount += 1
                    if retryCount >= 3 {
                        throw error
                    }
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                }
            }
        } catch {
            // Clean up on audio setup failure
            stopAudioCapture()
            throw ZumuError.networkError("Failed to initialize audio: \(error.localizedDescription)")
        }
    }

    private func setupAudioTap() {
        guard let audioEngine = audioEngine else { return }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, time in
            guard let self = self, let webSocketTask = self.webSocketTask else { return }

            // Convert audio buffer to data
            let audioData = self.bufferToData(buffer: buffer)

            // Send audio data via WebSocket
            Task {
                try? await webSocketTask.send(.data(audioData))
            }
        }
    }

    private func stopAudioCapture() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        try? audioSession?.setActive(false)
        audioEngine = nil
        audioSession = nil
    }

    private func bufferToData(buffer: AVAudioPCMBuffer) -> Data {
        let audioBuffer = buffer.audioBufferList.pointee.mBuffers
        return Data(bytes: audioBuffer.mData!, count: Int(audioBuffer.mDataByteSize))
    }

    private func updateSessionStatus(sessionId: String, status: String) async throws {
        let url = URL(string: "\(baseURL)/api/sessions/\(sessionId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["status": status]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let errorBody = String(data: data, encoding: .utf8) ?? "No response body"
            throw ZumuError.apiError("Failed to update session (HTTP \(statusCode)): \(errorBody)")
        }
    }
}

// MARK: - Session State

public enum SessionState: Equatable {
    case idle
    case connecting
    case active
    case disconnected
    case ending
    case error(String)
}

// MARK: - Models

public struct SessionConfig {
    public let driverName: String
    public let driverLanguage: String
    public let passengerName: String
    public let passengerLanguage: String?
    public let tripId: String
    public let pickupLocation: String?
    public let dropoffLocation: String?

    public init(
        driverName: String,
        driverLanguage: String,
        passengerName: String,
        passengerLanguage: String? = nil,
        tripId: String,
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

public struct TranslationSession {
    public let id: String
    public let status: String
    public let createdAt: String
}

public struct TranslationMessage: Identifiable {
    public let id: UUID
    public let role: String
    public let content: String
    public let timestamp: Date

    init(role: String, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
}

struct ConversationData {
    let signedUrl: String
}

// MARK: - Errors

public enum ZumuError: LocalizedError {
    case invalidState(String)
    case apiError(String)
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidState(let message):
            return "Invalid state: \(message)"
        case .apiError(let message):
            return "API error: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}
