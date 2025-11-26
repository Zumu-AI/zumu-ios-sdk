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
    internal let baseURL: String
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
    private var isWebSocketConnected: Bool = false
    private var audioSendErrorCount: Int = 0

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
            // Step 1: Start conversation (creates session and returns WebSocket URL)
            let conversationData = try await startConversation(config: config)

            let session = TranslationSession(
                id: conversationData.sessionId,
                status: "active",
                createdAt: ISO8601DateFormatter().string(from: Date())
            )
            createdSession = session
            self.session = session
            self.createdSession = session

            // Step 2: Connect WebSocket for real-time communication with handshake
            try await connectWebSocket(signedUrl: conversationData.signedUrl, context: conversationData.context)

            // Step 3: Set up audio capture
            try await setupAudioCapture()

            state = .active

            // Reset reconnection attempts on successful connection
            reconnectionAttempts = 0

            return session

        } catch {
            // Clean up WebSocket if it was created
            webSocketTask?.cancel(with: .goingAway, reason: nil)
            webSocketTask = nil
            isWebSocketConnected = false

            // Clean up audio if it was initialized
            stopAudioCapture()

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
        isWebSocketConnected = false
        audioSendErrorCount = 0
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
            isWebSocketConnected = false
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
        guard session != nil else { return }

        state = .ending

        // Disconnect WebSocket (this signals the backend that session has ended)
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        // Stop audio capture
        stopAudioCapture()

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
        self.isWebSocketConnected = false
        self.audioSendErrorCount = 0
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

    private func startConversation(config: SessionConfig) async throws -> ConversationData {
        let url = URL(string: "\(baseURL)/api/conversations/start")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "session_id": config.tripId,
            "driver_name": config.driverName,
            "driver_language": config.driverLanguage,
            "passenger_name": config.passengerName,
            "passenger_language": config.passengerLanguage as Any,
            "pickup_location": config.pickupLocation as Any,
            "dropoff_location": config.dropoffLocation as Any
        ]

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
            sessionId: json["session_id"] as! String,
            conversationId: json["conversation_id"] as? String,
            context: context
        )
    }

    private func connectWebSocket(signedUrl: String, context: [String: String]) async throws {
        guard let url = URL(string: signedUrl) else {
            throw ZumuError.networkError("Invalid WebSocket URL")
        }

        // Configure URLSession with proper timeouts and keep-alive
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData

        let session = URLSession(configuration: config)
        webSocketTask = session.webSocketTask(with: url)

        // Set maximum message size (10MB for audio)
        webSocketTask?.maximumMessageSize = 10 * 1024 * 1024

        webSocketTask?.resume()

        // IMPORTANT: Never log the host to protect trade secrets
        print("🔌 Establishing secure WebSocket connection...")

        await MainActor.run {
            self.isWebSocketConnected = false  // Not fully connected until handshake completes
        }

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
            let nsError = error as NSError
            print("❌ Failed to send handshake - Error domain: \(nsError.domain), code: \(nsError.code)")
            print("   \(error.localizedDescription)")
            webSocketTask?.cancel(with: .goingAway, reason: nil)
            webSocketTask = nil
            await MainActor.run {
                self.isWebSocketConnected = false
            }
            throw ZumuError.networkError("Failed to send WebSocket handshake: \(error.localizedDescription)")
        }

        // Start receiving messages immediately after handshake
        Task {
            await receiveWebSocketMessages()
        }

        // DISABLED: Connection quality monitoring (was causing premature disconnects)
        // Task {
        //     await monitorConnectionQuality()
        // }

        // Give server time to acknowledge handshake
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // Verify connection is still active
        guard webSocketTask != nil else {
            throw ZumuError.networkError("WebSocket connection failed after handshake")
        }

        print("✅ WebSocket connection established and ready")
    }

    private func monitorConnectionQuality() async {
        // Wait for handshake to fully complete before starting pings
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        // Send ping every 10 seconds to measure latency
        while let task = webSocketTask, state == .active {
            do {
                // Only ping if we're actually connected
                guard await MainActor.run(body: { self.isWebSocketConnected }) else {
                    print("📡 Skipping ping - WebSocket not connected")
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // Wait 1s and check again
                    continue
                }

                // Record ping time
                await MainActor.run {
                    self.lastPingTime = Date()
                }

                // Send ping
                let ping: [String: String] = ["type": "ping"]
                let pingData = try JSONSerialization.data(withJSONObject: ping)
                try await task.send(.data(pingData))
                print("📡 Sent ping for latency measurement")

                // Wait 10 seconds before next ping (longer interval to reduce overhead)
                try await Task.sleep(nanoseconds: 10_000_000_000)

            } catch {
                let nsError = error as NSError
                print("⚠️ Failed to send ping: \(error.localizedDescription)")
                print("   Error domain: \(nsError.domain), code: \(nsError.code)")

                // Mark as disconnected
                await MainActor.run {
                    self.isWebSocketConnected = false
                }
                break
            }
        }
        print("📡 Connection quality monitor stopped")
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
                let nsError = error as NSError
                print("❌ WebSocket disconnected: \(error.localizedDescription)")
                print("   Error domain: \(nsError.domain), code: \(nsError.code)")

                // Check for specific error codes
                if nsError.code == 57 { // ENOTCONN - Socket is not connected
                    print("   💡 Socket was not connected - likely closed by peer or network issue")
                } else if nsError.code == 54 { // ECONNRESET - Connection reset by peer
                    print("   💡 Connection reset by peer")
                } else if nsError.domain == "NSPOSIXErrorDomain" {
                    print("   💡 Network/socket level error")
                }

                await MainActor.run {
                    // Mark as disconnected
                    self.isWebSocketConnected = false

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

        print("📡 WebSocket message receiver stopped")
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
                print("✅ WebSocket handshake completed - enabling audio with stabilization delay...")

                // Enable audio in a separate Task after a brief delay
                // This keeps the receive loop active to prevent connection timeout
                Task {
                    // Give the connection a moment to stabilize
                    try? await Task.sleep(nanoseconds: 500_000_000) // 500ms

                    await MainActor.run {
                        self.isWebSocketConnected = true
                        self.agentState = .listening
                        self.audioSendErrorCount = 0
                    }

                    print("🎤 Audio transmission enabled after stabilization period")
                }

                // Don't block the receive loop - let it continue processing messages
                return
            }

            // Error messages from server
            if type == "error" {
                let errorMsg = json["message"] as? String ?? "Unknown error"
                let errorCode = json["code"] as? String ?? "unknown"
                print("❌ Server error [\(errorCode)]: \(errorMsg)")
                await MainActor.run {
                    self.state = .error("Server error: \(errorMsg)")
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
            guard let self = self else { return }

            // Check if we should send audio (WebSocket connected, not muted, in active state)
            guard self.isWebSocketConnected,
                  !self.isMuted,
                  self.state == .active,
                  let webSocketTask = self.webSocketTask else {
                return
            }

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

                    // Reset error count on successful send
                    await MainActor.run {
                        self.audioSendErrorCount = 0
                    }
                } catch {
                    await MainActor.run {
                        self.audioSendErrorCount += 1

                        // Log detailed error information
                        let nsError = error as NSError
                        print("⚠️ Failed to send audio (attempt \(self.audioSendErrorCount)): \(error.localizedDescription)")
                        print("   Error domain: \(nsError.domain), code: \(nsError.code)")

                        // Mark WebSocket as disconnected if we get socket errors
                        if nsError.domain == NSPOSIXErrorDomain ||
                           error.localizedDescription.contains("Socket") ||
                           error.localizedDescription.contains("canceled") {
                            print("🔌 WebSocket appears to be disconnected - marking connection as lost")
                            self.isWebSocketConnected = false

                            // Trigger reconnection if we have multiple consecutive failures
                            if self.audioSendErrorCount >= 3 && self.state == .active {
                                print("❌ Multiple consecutive audio send failures - triggering reconnection")
                                self.state = .disconnected
                            }
                        }
                    }
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
    let sessionId: String
    let conversationId: String?
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
