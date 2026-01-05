import SwiftUI
import LiveKit
import LiveKitComponents
import AVFoundation

/// Main SDK entry point for Zumu Translation
///
/// Usage in SwiftUI:
/// ```swift
/// import ZumuTranslator
///
/// Button("Start Translation") {
///     showTranslation = true
/// }
/// .sheet(isPresented: $showTranslation) {
///     ZumuTranslatorView(
///         config: TranslationConfig(
///             driverName: "John",
///             driverLanguage: "English",
///             passengerName: "Maria",
///             passengerLanguage: "Spanish"
///         ),
///         apiKey: "zumu_your_api_key"
///     )
/// }
/// ```
///
/// Usage in UIKit:
/// ```swift
/// import ZumuTranslator
///
/// @IBAction func startTranslationTapped(_ sender: UIButton) {
///     let config = ZumuTranslator.TranslationConfig(
///         driverName: "John",
///         driverLanguage: "English",
///         passengerName: "Maria",
///         passengerLanguage: "Spanish"
///     )
///
///     ZumuTranslator.present(
///         config: config,
///         apiKey: "zumu_your_api_key",
///         from: self
///     )
/// }
/// ```
public class ZumuTranslator {

    // MARK: - Configuration

    /// Translation session configuration
    public struct TranslationConfig {
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
            self.tripId = tripId ?? UUID().uuidString
            self.pickupLocation = pickupLocation
            self.dropoffLocation = dropoffLocation
        }
    }

    // MARK: - UIKit Integration

    /// Present the translation interface from a UIViewController
    ///
    /// - Parameters:
    ///   - config: Translation configuration with driver/passenger details
    ///   - apiKey: Zumu API key
    ///   - baseURL: Optional custom backend URL (defaults to production)
    ///   - from: The view controller to present from
    @MainActor
    public static func present(
        config: TranslationConfig,
        apiKey: String,
        baseURL: String = "https://translator.zumu.ai",
        from viewController: UIViewController
    ) {
        let hostingController = UIHostingController(
            rootView: ZumuTranslatorView(
                config: config,
                apiKey: apiKey,
                baseURL: baseURL
            )
        )

        hostingController.modalPresentationStyle = .fullScreen
        viewController.present(hostingController, animated: true)
    }
}

// MARK: - SwiftUI View

/// Main translation interface view
/// Can be presented as a sheet, fullScreenCover, or NavigationLink destination
public struct ZumuTranslatorView: View {
    public let config: ZumuTranslator.TranslationConfig
    public let apiKey: String
    public let baseURL: String

    // ✅ Changed from @StateObject to @State - allows fresh session creation
    @State private var session: Session?
    @State private var localMedia: LocalMedia?
    // Manual connection state tracking (workaround for @State not observing Session.isConnected)
    @State private var isSessionConnected: Bool = false
    // Prevent duplicate start attempts
    @State private var isConnecting: Bool = false
    // Prevent concurrent session operations (fixes crash on relaunch)
    @State private var isCleaningUp: Bool = false
    @Environment(\.dismiss) private var dismiss

    public init(
        config: ZumuTranslator.TranslationConfig,
        apiKey: String,
        baseURL: String = "https://translator.zumu.ai"
    ) {
        self.config = config
        self.apiKey = apiKey
        self.baseURL = baseURL
        // ✅ Don't create session in init - wait for onAppear
        // This allows creating fresh sessions for each conversation
    }

    // MARK: - Session Lifecycle

    /// Create a fresh session instance
    /// Called in onAppear to ensure clean state for each conversation
    private func createFreshSession() {
        // Guard against concurrent access
        guard !isCleaningUp else {
            print("⚠️ Skipping createFreshSession - cleanup in progress")
            return
        }

        print("✅ Creating fresh session instance")

        // Reset connection state for fresh start
        self.isSessionConnected = false
        self.isConnecting = false

        // Create ZumuTokenSource configuration
        let tokenConfig = ZumuTokenSource.TranslationConfig(
            driverName: config.driverName,
            driverLanguage: config.driverLanguage,
            passengerName: config.passengerName,
            passengerLanguage: config.passengerLanguage,
            tripId: config.tripId,
            pickupLocation: config.pickupLocation,
            dropoffLocation: config.dropoffLocation
        )

        // Create token source
        let tokenSource = ZumuTokenSource(
            apiKey: apiKey,
            config: tokenConfig,
            baseURL: baseURL
        )

        // Create session with fresh token (no caching - each open is a new conversation)
        let newSession = Session(
            tokenSource: tokenSource,
            options: SessionOptions(
                room: Room(
                    roomOptions: RoomOptions(
                        defaultAudioCaptureOptions: AudioCaptureOptions(),
                        defaultAudioPublishOptions: AudioPublishOptions()
                    )
                )
            )
        )

        let newLocalMedia = LocalMedia(session: newSession)

        // Set state
        self.session = newSession
        self.localMedia = newLocalMedia

        print("✅ Fresh session created - ready for connection")

        // Auto-start the session after a brief delay
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s delay for initialization
            print("🚀 Auto-starting connection for fresh conversation...")
            await newSession.start()
        }
    }

    /// Complete cleanup of session and media
    /// Called in onDisappear to ensure proper resource deallocation
    private func cleanupSession() async {
        // Set flag to prevent concurrent operations
        isCleaningUp = true
        defer { isCleaningUp = false }  // Always reset flag when done

        print("🧹 Starting session cleanup")

        guard let session = session else {
            print("🧹 No session to cleanup")
            return
        }

        if session.isConnected {
            print("🧹 Ending connected session...")
            await session.end()
        }

        // Allow cleanup time for WebRTC to fully teardown
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second

        // Nil references to trigger deallocation
        self.session = nil
        self.localMedia = nil
        self.isSessionConnected = false  // Reset manual state
        self.isConnecting = false  // Reset connecting flag

        print("✅ Session cleanup complete")
    }

    public var body: some View {
        // ✅ Guard rendering until session is created
        Group {
            if let session = session, let localMedia = localMedia {
                // Session exists - show interface
                sessionInterface(session: session, localMedia: localMedia)
            } else {
                // No session yet - show loading
                loadingView()
            }
        }
        .environment(\.translationConfig, config)
        .background(.bg1)
        .onAppear {
            print("🚀 Starting Zumu translation session")
            print("   Driver: \(config.driverName) (\(config.driverLanguage))")
            print("   Passenger: \(config.passengerName) (\(config.passengerLanguage ?? "Auto-detect"))")

            // Detect simulator
            #if targetEnvironment(simulator)
            print("⚠️ WARNING: Running on iOS Simulator - WebRTC audio playback may not work!")
            print("⚠️ For full audio functionality, please test on a physical iOS device")
            #endif

            // ✅ Create fresh session instance
            createFreshSession()

            // Force AudioManager configuration BEFORE connecting
            forceAudioManagerConfiguration()
        }
        .onChange(of: session?.isConnected) { oldValue, newValue in
            // ✅ Handle optional session
            guard let session = session, newValue == true else { return }

            print("🔗 Session connected")

            // Reconfigure AudioManager after connection
            forceAudioManagerConfiguration()

            // Log comprehensive audio state
            Task {
                await logAudioState(session: session)
            }

            // Wait for agent track, then force max volume
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // Wait 2 seconds
                await forceTrackVolume(session: session)
            }

            // Log audio tracks - wait longer for agent to publish
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000) // Wait 3 seconds for agent to publish
                let participants = session.room.allParticipants
                print("🎵 Audio tracks diagnostic:")
                print("🎵 Total participants: \(participants.count)")

                for participant in participants.values {
                    let identity = participant.identity
                    let kind = participant.kind
                    // Make optionals explicit to avoid debug-description interpolation
                    let identityDesc = identity?.stringValue ?? "nil"
                    let kindDesc = kind.description

                    print("🎵 Participant: \(identityDesc) (kind: \(kindDesc))")

                    let audioTracks = participant.audioTracks
                    print("🎵    Audio tracks count: \(audioTracks.count)")

                    for publication in audioTracks {
                        print("🎵       Track SID: \(publication.sid.stringValue)")
                        print("🎵       Subscribed: \(publication.isSubscribed)")
                        print("🎵       Muted: \(publication.isMuted)")
                        print("🎵       Track exists: \(publication.track != nil)")

                        if publication.track is RemoteAudioTrack {
                            print("🎵       RemoteAudioTrack found!")
                        }
                    }
                }

                // Also check session.agent directly
                if let agentTrack = session.agent.audioTrack {
                    print("🎵 Session.agent.audioTrack EXISTS: \(agentTrack)")
                } else {
                    print("🎵 Session.agent.audioTrack is NIL")
                }
            }
        }
        .onDisappear {
            print("🔴 SDK dismissed - cleaning up session")
            // ✅ Use new cleanup method
            Task {
                await cleanupSession()
            }
            // AudioManager will handle audio session cleanup automatically
            // Do NOT manually deactivate AVAudioSession as it conflicts with AudioManager
        }
    }

    // MARK: - Audio Debugging & Configuration

    private func logAudioState(session: Session) async {
        print("🔊 ===== COMPREHENSIVE AUDIO DIAGNOSTICS =====")

        // 1. AVAudioSession State
        let audioSession = AVAudioSession.sharedInstance()
        let route = audioSession.currentRoute
        print("🔊 AVAudioSession:")
        print("🔊   Category: \(audioSession.category.rawValue)")
        print("🔊   Mode: \(audioSession.mode.rawValue)")
        print("🔊   Route: \(route.outputs.map { $0.portType.rawValue }.joined(separator: ", "))")
        print("🔊   Volume: \(audioSession.outputVolume)")
        print("🔊   Is other audio playing: \(audioSession.isOtherAudioPlaying)")

        // 2. AudioManager State (CRITICAL)
        print("🔊 AudioManager:")
        print("🔊   Auto config enabled: \(AudioManager.shared.audioSession.isAutomaticConfigurationEnabled)")
        print("🔊   Engine running: \(AudioManager.shared.isEngineRunning)")
        print("🔊   Manual rendering mode: \(AudioManager.shared.isManualRenderingMode)")
        print("🔊   Speaker output preferred: \(AudioManager.shared.isSpeakerOutputPreferred)")

        // 3. Mixer State
        print("🔊 Mixer:")
        print("🔊   Output volume: \(AudioManager.shared.mixer.outputVolume)")

        // 4. Remote Audio Track State
        if let agentTrack = session.agent.audioTrack as? RemoteAudioTrack {
            print("🔊 Remote Track:")
            print("🔊   Track volume: \(agentTrack.volume)")
            print("🔊   Track: \(agentTrack)")
        } else {
            print("🔊 ❌ Agent audio track is NIL or wrong type")
        }

        print("🔊 =========================================")
    }

    private func forceAudioManagerConfiguration() {
        print("🔧 Forcing AudioManager configuration...")

        // Ensure automatic configuration is enabled
        AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = true
        print("🔧 ✅ Auto configuration enabled")

        // Ensure speaker output is preferred
        AudioManager.shared.isSpeakerOutputPreferred = true
        print("🔧 ✅ Speaker output preferred set")

        // Ensure engine availability is enabled (both input and output)
        do {
            try AudioManager.shared.setEngineAvailability(.default)
            print("🔧 ✅ Engine availability set to default (input and output enabled)")
        } catch {
            print("🔧 ⚠️ Failed to set engine availability: \(error)")
        }

        // Ensure manual rendering is OFF
        if AudioManager.shared.isManualRenderingMode {
            print("🔧 ⚠️ Manual rendering mode is ON - this prevents automatic playback!")
            do {
                try AudioManager.shared.setManualRenderingMode(false)
                print("🔧 ✅ Manual rendering mode disabled")
            } catch {
                print("🔧 ⚠️ Failed to disable manual rendering mode: \(error)")
            }
        }

        // Set mixer output volume to max
        AudioManager.shared.mixer.outputVolume = 1.0
        print("🔧 ✅ Mixer output volume set to 1.0")

        print("🔧 AudioManager configuration complete")
    }

    private func forceTrackVolume(session: Session) async {
        if let agentTrack = session.agent.audioTrack as? RemoteAudioTrack {
            print("🔊 Setting agent track volume to MAXIMUM")
            agentTrack.volume = 1.0
            print("🔊 ✅ Agent track volume: \(agentTrack.volume)")
        }
    }

    // MARK: - View Helpers

    /// Loading view shown while session is being created
    @ViewBuilder
    private func loadingView() -> some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)

            Text("Initializing...")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Main session interface with session/localMedia passed as parameters
    @ViewBuilder
    private func sessionInterface(session: Session, localMedia: LocalMedia) -> some View {
        ZStack(alignment: .top) {
            if isSessionConnected {
                translationInterface(session: session, localMedia: localMedia)
            } else {
                connectingView(session: session, localMedia: localMedia)
            }

            // Close button overlay (always visible)
            closeButton(session: session)
                .padding()

            errors(session: session, localMedia: localMedia)
        }
        .animation(.default, value: isSessionConnected)
        .task {
            // Monitor session connection state
            // This is a workaround because @State doesn't observe properties within Session
            print("🔍 Starting session connection monitor...")
            while !Task.isCancelled {
                let connected = session.isConnected
                if connected != isSessionConnected {
                    print("🔍 Session connection state changed: \(isSessionConnected) → \(connected)")
                    isSessionConnected = connected

                    // Reset connecting flag when connection state changes
                    if connected {
                        print("✅ Connection established, resetting isConnecting flag")
                        isConnecting = false
                    }
                }
                // Check every 100ms
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            print("🔍 Session connection monitor stopped")
        }
    }

    @ViewBuilder
    private func closeButton(session: Session) -> some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    Task { @MainActor in
                        print("🔴 Close button tapped")
                        // Use the cleanup method
                        await cleanupSession()
                        print("🔴 Dismissing view...")
                        dismiss()
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 36, weight: .regular))
                        .foregroundStyle(.black.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .zIndex(1000)
    }

    @ViewBuilder
    private func connectingView(session: Session, localMedia: LocalMedia) -> some View {
        ZStack {
            // Subtle waveform placeholder - minimal presence
            BarAudioVisualizer(audioTrack: nil,
                               agentState: .listening,
                               barCount: 5,
                               barSpacingFactor: 0.08,
                               barMinOpacity: 0.05)
                .frame(maxWidth: .infinity, maxHeight: 280)
                .padding(.horizontal, 60)
                .opacity(0.2) // Very subtle

            VStack {
                Spacer()

                // Clean text - adaptive for dark mode
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DRIVER")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .tracking(1.2)
                        Text("\(config.driverName) · \(config.driverLanguage)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                    }

                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.tertiary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("PASSENGER")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .tracking(1.2)
                        Text("\(config.passengerName) · \(config.passengerLanguage ?? "Auto")")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)

                // Auto-connecting indicator
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(.secondary)
                    Text("Connecting...")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environmentObject(session)
        .environmentObject(localMedia)
    }

    @ViewBuilder
    private func translationInterface(session: Session, localMedia: LocalMedia) -> some View {
        VoiceInteractionView()
            .environmentObject(session)
            .environmentObject(localMedia)
            .safeAreaInset(edge: .top, spacing: 0) {
                // Clean, minimal text - adaptive for dark mode
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DRIVER")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .tracking(1.2)
                        Text("\(config.driverName) · \(config.driverLanguage)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                    }

                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.tertiary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("PASSENGER")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .tracking(1.2)
                        Text("\(config.passengerName) · \(config.passengerLanguage ?? "Auto")")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    // Clean transcript - no background, larger text, only last 2 messages
                    TranscriptView()
                        .frame(minHeight: 140, maxHeight: 180)
                        .padding(.bottom, 24)
                        .environmentObject(session)

                    // Control bar
                    ControlBar(chat: .constant(false))
                        .environmentObject(session)
                        .environmentObject(localMedia)
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                        .onDisconnect {
                            dismiss()
                        }
                }
            }
    }

    @ViewBuilder
    private func errors(session: Session, localMedia: LocalMedia) -> some View {
        if let error = session.error {
            ErrorView(error: error) { session.dismissError() }
        }

        if let agentError = session.agent.error {
            ErrorView(error: agentError) {
                Task {
                    await cleanupSession()
                    dismiss()
                }
            }
        }

        if let mediaError = localMedia.error {
            ErrorView(error: mediaError) { localMedia.dismissError() }
        }
    }
}

// MARK: - Environment Extensions

extension EnvironmentValues {
    @Entry var translationConfig: ZumuTranslator.TranslationConfig?
}

// MARK: - ControlBar Disconnect Handler

extension View {
    func onDisconnect(perform action: @escaping () -> Void) -> some View {
        self.environment(\.onDisconnect, action)
    }
}
