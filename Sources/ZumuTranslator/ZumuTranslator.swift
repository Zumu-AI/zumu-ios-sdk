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

    /// Current agent state (what the agent is doing)
    @Published public private(set) var agentState: AgentState = .idle

    /// Current conversation messages
    @Published public private(set) var messages: [TranslationMessage] = []

    /// Is microphone muted
    @Published public private(set) var isMuted: Bool = false

    /// Active translation session
    @Published public private(set) var session: TranslationSession?

    /// Connection quality metrics
    @Published public private(set) var connectionQuality: ConnectionQuality?

    // MARK: - Private Properties

    private let apiKey: String
    private let baseURL: String
    private var webSocketTask: URLSessionWebSocketTask?
    private var cancellables = Set<AnyCancellable>()
    private var audioEngine: AVAudioEngine?
    private var audioSession: AVAudioSession?
    private var isStarting: Bool = false
    private var audioPlayer: AVAudioPlayer?
    private var audioQueue: [Data] = []
    private var isPlayingAudio: Bool = false
    private var reconnectionAttempts: Int = 0
    private var maxReconnectionAttempts: Int = 3
    private var lastSessionConfig: SessionConfig?
    private var createdSession: TranslationSession?
    private var lastPingTime: Date?
    private var latencyMeasurements: [Int] = []

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

        // Store config for potential reconnection
        lastSessionConfig = config

        do {
            // Step 1: Create session on Zumu backend
            let session = try await createBackendSession(config: config)
            createdSession = session
            self.session = session
            self.createdSession = session

            // Step 2: Set up audio capture FIRST (before WebSocket)
            // This ensures we're ready to stream audio immediately after connection
            try await setupAudioCapture()
            print("✅ Audio capture ready")

            // Step 3: Start conversation via Zumu API
            let conversationData = try await startConversation(sessionId: session.id)

            // Step 4: Connect WebSocket for real-time communication with handshake
            // Audio is already ready, so we can start streaming immediately
            try await connectWebSocket(signedUrl: conversationData.signedUrl, context: conversationData.context)

            state = .active

            // Reset reconnection attempts on successful connection
            reconnectionAttempts = 0

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
        reconnectionAttempts = 0
        connectionQuality = nil
        latencyMeasurements = []
        lastPingTime = nil
    }

    /// Attempt to reconnect to the session
    /// - Returns: True if reconnection was successful
    @MainActor
    private func attemptReconnection() async -> Bool {
        guard let config = lastSessionConfig,
              let session = createdSession,
              reconnectionAttempts < maxReconnectionAttempts else {
            print("❌ Reconnection not possible: no config or max attempts reached")
            return false
        }

        reconnectionAttempts += 1
        print("🔄 Attempting reconnection (\(reconnectionAttempts)/\(maxReconnectionAttempts))...")

        // Exponential backoff: 1s, 2s, 4s
        let backoffDelay = UInt64(pow(2.0, Double(reconnectionAttempts - 1)) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: backoffDelay)

        do {
            // Clean up previous connection
            webSocketTask?.cancel(with: .goingAway, reason: nil)
            webSocketTask = nil
            stopAudioCapture()

            // Reset to idle to allow startSession to work
            state = .idle
            self.session = nil

            // Attempt to reconnect with same config
            _ = try await startSession(config: config)
            print("✅ Reconnection successful!")
            return true

        } catch {
            print("⚠️ Reconnection attempt \(reconnectionAttempts) failed: \(error.localizedDescription)")

            if reconnectionAttempts >= maxReconnectionAttempts {
                print("❌ Max reconnection attempts reached, giving up")
                state = .error("Connection lost. Please try again.")
                return false
            }

            return false
        }
    }

    /// End the current translation session
    @MainActor
    public func endSession() async {
        guard let session = session else { return }

        state = .ending

        // Disconnect WebSocket
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        // Stop audio capture
        stopAudioCapture()

        // Update backend session status (best effort - don't fail if this doesn't work)
        do {
            try await updateSessionStatus(sessionId: session.id, status: "ended")
            print("✅ Session status updated to 'ended'")
        } catch {
            print("⚠️ Failed to update session status (non-critical): \(error.localizedDescription)")
            // Continue anyway - WebSocket and audio are already closed
        }

        // Reset state and reconnection tracking (user intentionally ended session)
        self.session = nil
        self.messages = []
        self.reconnectionAttempts = 0
        self.lastSessionConfig = nil
        self.createdSession = nil
        self.agentState = .idle
        self.connectionQuality = nil
        self.latencyMeasurements = []
        self.lastPingTime = nil
        state = .idle
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

        // Parse context for WebSocket handshake
        var context: [String: String] = [:]
        if let contextDict = json["context"] as? [String: Any] {
            for (key, value) in contextDict {
                context[key] = "\(value)"
            }
        }

        return ConversationData(
            signedUrl: json["signed_url"] as! String,
            context: context
        )
    }

    private func connectWebSocket(signedUrl: String, context: [String: String]) async throws {
        guard let url = URL(string: signedUrl) else {
            throw ZumuError.networkError("Invalid WebSocket URL")
        }

        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()

        print("🔌 WebSocket connected, sending initial handshake...")

        // Send initial handshake with agent variables (CRITICAL for ElevenLabs)
        let handshake: [String: Any] = [
            "type": "conversation_initiation_client_data",
            "conversation_config_override": [
                "agent": [
                    "prompt": [
                        "variables": context
                    ]
                ]
            ]
        ]

        do {
            let handshakeData = try JSONSerialization.data(withJSONObject: handshake)
            try await webSocketTask?.send(.data(handshakeData))
            print("✅ Handshake sent successfully")
        } catch {
            webSocketTask?.cancel(with: .goingAway, reason: nil)
            webSocketTask = nil
            throw ZumuError.networkError("Failed to send WebSocket handshake: \(error.localizedDescription)")
        }

        // Start receiving messages immediately after handshake
        Task {
            await receiveWebSocketMessages()
        }

        // Start connection quality monitoring
        Task {
            await monitorConnectionQuality()
        }

        // Give server time to acknowledge handshake
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        // Verify connection is still active
        guard webSocketTask != nil else {
            throw ZumuError.networkError("WebSocket connection failed after handshake")
        }

        print("✅ WebSocket connection established and stable")
    }

    private func monitorConnectionQuality() async {
        // Send ping every 5 seconds to measure latency
        while let task = webSocketTask, state == .active || state == .connecting {
            do {
                // Record ping time
                await MainActor.run {
                    self.lastPingTime = Date()
                }

                // Send ping
                let ping: [String: String] = ["type": "ping"]
                let pingData = try JSONSerialization.data(withJSONObject: ping)
                try await task.send(.data(pingData))
                print("📡 Sent ping for latency measurement")

                // Wait 5 seconds before next ping
                try await Task.sleep(nanoseconds: 5_000_000_000)

            } catch {
                print("⚠️ Failed to send ping: \(error.localizedDescription)")
                break
            }
        }
    }

    private func receiveWebSocketMessages() async {
        print("📡 Starting WebSocket message receiver...")

        while let task = webSocketTask {
            do {
                let message = try await task.receive()

                switch message {
                case .data(let data):
                    await handleWebSocketData(data)
                case .string(let text):
                    print("📨 Received text message: \(text.prefix(200))...")
                    if let data = text.data(using: .utf8) {
                        await handleWebSocketData(data)
                    }
                @unknown default:
                    break
                }
            } catch {
                // WebSocket disconnected - attempt automatic reconnection
                print("❌ WebSocket error: \(error.localizedDescription)")
                await MainActor.run {
                    // Only handle reconnection if we were in an active session
                    // If we were connecting, the error will be caught by startSession
                    if self.state == .active {
                        print("⚠️ WebSocket connection lost during active session")
                        self.state = .disconnected
                        self.agentState = .idle

                        // Attempt automatic reconnection
                        Task { @MainActor in
                            let reconnected = await self.attemptReconnection()

                            if !reconnected {
                                // Reconnection failed - transition to error state
                                if self.state != .error("Connection lost. Please try again.") {
                                    self.state = .error("Connection lost after \(self.reconnectionAttempts) attempts")
                                }
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

    private func handleWebSocketData(_ data: Data) async {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("⚠️ Failed to parse WebSocket message")
            return
        }

        if let type = json["type"] as? String {
            print("📨 Received: \(type)")

            // Handshake acknowledgment
            if type == "conversation_initiation_metadata" {
                print("✅ Connection established")
                await MainActor.run {
                    self.agentState = .listening
                }
                return
            }

            // Audio from agent - agent is speaking
            if type == "audio" || type == "agent_audio_chunk" {
                if let audioBase64 = json["audio"] as? String,
                   let audioData = Data(base64Encoded: audioBase64) {
                    print("🔊 Playing agent audio (\(audioData.count) bytes)")
                    await MainActor.run {
                        self.agentState = .speaking
                    }
                    await playAudioChunk(audioData)
                }
                return
            }

            // User transcript - user finished speaking, agent will process
            if type == "user_transcript" {
                if let transcript = json["transcript"] as? String {
                    let msg = TranslationMessage(role: "user", content: transcript)
                    await MainActor.run {
                        self.messages.append(msg)
                        self.agentState = .thinking
                        print("👤 User: \(transcript)")
                    }
                }
                return
            }

            // Tentative user transcript - user is speaking
            if type == "tentative_user_transcript" {
                await MainActor.run {
                    self.agentState = .processing
                }
                return
            }

            // Agent response - agent formulated response, about to speak
            if type == "agent_response" {
                if let response = json["response"] as? String {
                    let msg = TranslationMessage(role: "agent", content: response)
                    await MainActor.run {
                        self.messages.append(msg)
                        print("🤖 Agent: \(response)")
                    }
                }
                return
            }

            // Interruption - user spoke while agent was speaking
            if type == "interruption" {
                print("⚠️ Interrupted")
                await MainActor.run {
                    self.audioQueue.removeAll()
                    self.audioPlayer?.stop()
                    self.agentState = .processing
                }
                return
            }

            // Ping/pong for connection health
            if type == "ping" {
                // Server sent ping, respond with pong
                Task {
                    let pong: [String: String] = ["type": "pong"]
                    if let pongData = try? JSONSerialization.data(withJSONObject: pong) {
                        try? await self.webSocketTask?.send(.data(pongData))
                    }
                }
                return
            }

            // Pong response - calculate latency
            if type == "pong" {
                await MainActor.run {
                    if let pingTime = self.lastPingTime {
                        let latencyMs = Int(Date().timeIntervalSince(pingTime) * 1000)
                        print("📊 Latency: \(latencyMs)ms")

                        // Keep last 10 measurements for averaging
                        self.latencyMeasurements.append(latencyMs)
                        if self.latencyMeasurements.count > 10 {
                            self.latencyMeasurements.removeFirst()
                        }

                        // Calculate average latency
                        let avgLatency = self.latencyMeasurements.reduce(0, +) / self.latencyMeasurements.count

                        // Update connection quality
                        self.connectionQuality = ConnectionQuality(latencyMs: avgLatency)
                        print("📊 Average latency: \(avgLatency)ms - Quality: \(self.connectionQuality?.quality.rawValue ?? "unknown")")

                        self.lastPingTime = nil
                    }
                }
                return
            }
        }
    }

    private func playAudioChunk(_ audioData: Data) async {
        await MainActor.run {
            self.audioQueue.append(audioData)
        }

        if !isPlayingAudio {
            await processAudioQueue()
        }
    }

    private func processAudioQueue() async {
        await MainActor.run {
            self.isPlayingAudio = true
        }

        while !audioQueue.isEmpty {
            let audioData = await MainActor.run {
                return self.audioQueue.isEmpty ? nil : self.audioQueue.removeFirst()
            }

            guard let data = audioData else { break }

            do {
                let player = try AVAudioPlayer(data: data)
                await MainActor.run {
                    self.audioPlayer = player
                }
                player.prepareToPlay()
                player.play()

                while player.isPlaying {
                    try? await Task.sleep(nanoseconds: 10_000_000)
                }
            } catch {
                print("⚠️ Audio playback error: \(error.localizedDescription)")
            }
        }

        await MainActor.run {
            self.isPlayingAudio = false
            // Return to listening state after agent finishes speaking
            if self.state == .active {
                self.agentState = .listening
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
            guard let self = self, let webSocketTask = self.webSocketTask, !self.isMuted else { return }

            // Convert audio buffer to PCM data
            let audioData = self.bufferToData(buffer: buffer)

            // Encode as base64 for protocol compatibility
            let base64Audio = audioData.base64EncodedString()

            // Wrap in protocol message format
            let message: [String: Any] = [
                "type": "user_audio_chunk",
                "audio": base64Audio
            ]

            // Send as JSON
            Task {
                do {
                    let jsonData = try JSONSerialization.data(withJSONObject: message)
                    try await webSocketTask.send(.data(jsonData))
                } catch {
                    print("⚠️ Failed to send audio: \(error.localizedDescription)")
                }
            }
        }
    }

    private func stopAudioCapture() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioPlayer?.stop()
        try? audioSession?.setActive(false)
        audioEngine = nil
        audioSession = nil
        audioPlayer = nil
        audioQueue.removeAll()
        isPlayingAudio = false
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

// MARK: - Agent State

/// Represents what the agent is currently doing
public enum AgentState: Equatable {
    case idle           // No active session
    case listening      // Agent is listening to user
    case processing     // Processing user speech (transcribing)
    case thinking       // Agent is formulating response
    case speaking       // Agent is responding/translating
}

// MARK: - Connection Quality

/// Connection quality metrics
public struct ConnectionQuality: Equatable {
    public let latencyMs: Int?
    public let packetsLost: Int?
    public let quality: Quality

    public enum Quality: String {
        case excellent = "excellent"  // < 100ms
        case good = "good"            // 100-300ms
        case fair = "fair"            // 300-500ms
        case poor = "poor"            // > 500ms
    }

    public init(latencyMs: Int?, packetsLost: Int? = nil) {
        self.latencyMs = latencyMs
        self.packetsLost = packetsLost

        if let latency = latencyMs {
            if latency < 100 {
                self.quality = .excellent
            } else if latency < 300 {
                self.quality = .good
            } else if latency < 500 {
                self.quality = .fair
            } else {
                self.quality = .poor
            }
        } else {
            self.quality = .good
        }
    }
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
    let context: [String: String]
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
