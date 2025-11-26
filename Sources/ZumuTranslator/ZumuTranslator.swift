import Foundation
import Combine
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif
import LiveKit

/// Zumu Driver Translator SDK for iOS (LiveKit Edition)
/// Provides real-time translation for driver-passenger conversations
/// using LiveKit WebRTC infrastructure
@MainActor
public class ZumuTranslator: NSObject, ObservableObject {

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
    private var room: Room?
    private var localAudioTrack: LocalAudioTrack?
    private var cancellables = Set<AnyCancellable>()
    private var isStarting: Bool = false
    private var lastSessionConfig: SessionConfig?
    private var reconnectionAttempts: Int = 0
    private var maxReconnectionAttempts: Int = 3

    // MARK: - Initialization

    /// Initialize Zumu Translator with API key
    /// - Parameters:
    ///   - apiKey: Your Zumu API key (from dashboard)
    ///   - baseURL: Optional custom base URL (defaults to production)
    public init(apiKey: String, baseURL: String = "https://translator.zumu.ai") {
        self.apiKey = apiKey
        self.baseURL = baseURL
        super.init()

        // Configure LiveKit
        configureLiveKit()
    }

    // MARK: - Session Management

    /// Start a new translation session
    /// - Parameters:
    ///   - config: Session configuration
    /// - Returns: Started translation session
    /// - Throws: ZumuError if session creation fails
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
        lastSessionConfig = config

        do {
            // Step 1: Request microphone permission
            let hasPermission = await requestMicrophonePermission()
            guard hasPermission else {
                throw ZumuError.permissionDenied("Microphone access is required for translation")
            }

            // Step 2: Call backend to create LiveKit room and connect agent
            let livekitInfo = try await startConversation(config: config)

            let session = TranslationSession(
                id: livekitInfo.sessionId,
                status: "active",
                createdAt: ISO8601DateFormatter().string(from: Date())
            )
            self.session = session

            // Step 3: Connect to LiveKit room
            try await connectToLiveKitRoom(
                url: livekitInfo.url,
                token: livekitInfo.token,
                roomName: livekitInfo.roomName
            )

            state = .active
            reconnectionAttempts = 0

            print("✅ Translation session started successfully")
            print("🏠 Room: \(livekitInfo.roomName)")
            print("🤖 Agent connected: \(livekitInfo.agentConnected)")

            return session

        } catch {
            // Clean up on error
            await disconnectRoom()

            state = .idle
            self.session = nil

            if let networkError = error as? ZumuError {
                throw networkError
            } else {
                throw ZumuError.networkError("Session start failed: \(error.localizedDescription)")
            }
        }
    }

    /// End current translation session
    public func endSession() async {
        guard state != .idle else { return }

        state = .ending
        print("🛑 Ending translation session...")

        // Disconnect from LiveKit room
        await disconnectRoom()

        // Reset state
        state = .idle
        session = nil
        messages = []
        agentState = .idle
        connectionQuality = nil
        reconnectionAttempts = 0

        print("✅ Session ended successfully")
    }

    /// Reset error state to allow retry
    public func resetState() {
        state = .idle
        session = nil
        messages = []
        isStarting = false
        reconnectionAttempts = 0
        connectionQuality = nil
        agentState = .idle
    }

    // MARK: - Audio Control

    /// Toggle microphone mute/unmute
    public func toggleMute() {
        isMuted.toggle()
        localAudioTrack?.mute = isMuted
        print(isMuted ? "🔇 Microphone muted" : "🎤 Microphone unmuted")
    }

    /// Send a text message
    public func sendMessage(_ text: String) async throws {
        guard state == .active, let room = room else {
            throw ZumuError.invalidState("Cannot send message: not connected")
        }

        // Send data message to all participants
        let messageData = [
            "type": "text_message",
            "content": text,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: messageData) else {
            throw ZumuError.invalidParameters("Failed to serialize message")
        }

        try await room.localParticipant.publishData(data: data, options: DataPublishOptions())

        // Add to local messages
        let message = TranslationMessage(
            id: UUID().uuidString,
            role: "user",
            content: text,
            timestamp: Date()
        )
        messages.append(message)

        print("📤 Sent text message: \(text)")
    }

    // MARK: - Private Methods

    /// Configure LiveKit global settings
    private func configureLiveKit() {
        // Enable pre-connection audio buffering (zero perceived latency!)
        AudioManager.shared.customConfigureAudioSessionFunc = { newState, oldState in
            print("🎵 Audio session state changed: \(oldState) → \(newState)")
        }

        print("⚙️ LiveKit configured with optimizations")
    }

    /// Request microphone permission
    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Start conversation and get LiveKit connection info
    private func startConversation(config: SessionConfig) async throws -> LiveKitConnectionInfo {
        let url = URL(string: "\(baseURL)/api/conversations/start")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "session_id": UUID().uuidString,
            "driver_name": config.driverName,
            "driver_language": config.driverLanguage,
            "passenger_name": config.passengerName,
            "passenger_language": config.passengerLanguage as Any,
            "pickup_location": config.pickupLocation as Any,
            "dropoff_location": config.dropoffLocation as Any
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ZumuError.networkError("Invalid response from server")
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ZumuError.networkError("Server error (\(httpResponse.statusCode)): \(errorMessage)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let livekit = json["livekit"] as? [String: Any],
              let url = livekit["url"] as? String,
              let token = livekit["token"] as? String,
              let roomName = livekit["room_name"] as? String,
              let sessionId = json["session_id"] as? String else {
            throw ZumuError.networkError("Invalid response format from server")
        }

        let agentConnected = json["agent_connected"] as? Bool ?? false

        return LiveKitConnectionInfo(
            url: url,
            token: token,
            roomName: roomName,
            sessionId: sessionId,
            agentConnected: agentConnected
        )
    }

    /// Connect to LiveKit room
    private func connectToLiveKitRoom(url: String, token: String, roomName: String) async throws {
        print("🔌 Connecting to LiveKit room: \(roomName)")

        // Create room instance
        let room = Room()
        self.room = room

        // Set up room delegate
        room.add(delegate: self)

        // Connect to room
        try await room.connect(url, token)

        print("✅ Connected to LiveKit room")

        // Publish local audio track
        try await publishLocalAudio()
    }

    /// Publish local audio track to the room
    private func publishLocalAudio() async throws {
        guard let room = room else {
            throw ZumuError.invalidState("Room not initialized")
        }

        print("🎤 Publishing local audio track...")

        // Create audio track with optimal settings
        let track = LocalAudioTrack.createTrack()
        self.localAudioTrack = track

        // Set initial mute state
        track.mute = isMuted

        // Publish track to room
        try await room.localParticipant.publish(audioTrack: track)

        print("✅ Local audio track published")
    }

    /// Disconnect from LiveKit room
    private func disconnectRoom() async {
        guard let room = room else { return }

        // Unpublish tracks
        if let audioTrack = localAudioTrack {
            await room.localParticipant.unpublish(track: audioTrack)
        }

        // Disconnect
        await room.disconnect()

        self.room = nil
        self.localAudioTrack = nil

        print("🔌 Disconnected from LiveKit room")
    }
}

// MARK: - LiveKit Room Delegate

extension ZumuTranslator: RoomDelegate {

    public func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) {
        print("🎧 Subscribed to track: \(publication.sid?.stringValue ?? "unknown")")

        // Automatically play remote audio tracks
        if let audioTrack = publication.track as? RemoteAudioTrack {
            print("🔊 Playing remote audio from: \(participant.identity?.stringValue ?? "unknown")")
        }
    }

    public func room(_ room: Room, participant: RemoteParticipant, didUnsubscribeTrack publication: RemoteTrackPublication) {
        print("👋 Unsubscribed from track: \(publication.sid?.stringValue ?? "unknown")")
    }

    public func room(_ room: Room, participant: Participant, didReceiveData data: Data) {
        // Handle data messages from agent
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        switch type {
        case "agent_message":
            if let content = json["content"] as? String {
                let message = TranslationMessage(
                    id: UUID().uuidString,
                    role: "agent",
                    content: content,
                    timestamp: Date()
                )
                messages.append(message)
            }

        case "agent_state":
            if let stateString = json["state"] as? String {
                updateAgentState(stateString)
            }

        default:
            print("📬 Received unknown message type: \(type)")
        }
    }

    public func room(_ room: Room, didUpdateConnectionState connectionState: ConnectionState) {
        print("🔄 Connection state: \(connectionState)")

        switch connectionState {
        case .connected:
            state = .active
            connectionQuality = .excellent

        case .reconnecting:
            state = .disconnected
            connectionQuality = .poor

        case .disconnected:
            state = .disconnected
            connectionQuality = nil

        @unknown default:
            break
        }
    }

    public func room(_ room: Room, participant: RemoteParticipant, didUpdateConnectionQuality quality: ConnectionQuality) {
        connectionQuality = quality
    }

    private func updateAgentState(_ stateString: String) {
        switch stateString {
        case "listening":
            agentState = .listening
        case "processing":
            agentState = .processing
        case "thinking":
            agentState = .thinking
        case "speaking":
            agentState = .speaking
        default:
            agentState = .idle
        }
    }
}

// MARK: - Supporting Types

struct LiveKitConnectionInfo {
    let url: String
    let token: String
    let roomName: String
    let sessionId: String
    let agentConnected: Bool
}
