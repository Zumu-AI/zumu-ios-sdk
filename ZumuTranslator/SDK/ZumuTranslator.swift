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
        print("✅ Creating fresh session instance")

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

        // Create session with minimal options (let LiveKit handle everything)
        let newSession = Session(
            tokenSource: tokenSource.cached()
        )

        let newLocalMedia = LocalMedia(session: newSession)

        // Set state
        self.session = newSession
        self.localMedia = newLocalMedia

        print("✅ Fresh session created - ready for connection")
    }

    /// Complete cleanup of session and media
    /// Called in onDisappear to ensure proper resource deallocation
    private func cleanupSession() async {
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
                let participants = await session.room.allParticipants
                print("🎵 Audio tracks diagnostic:")
                print("🎵 Total participants: \(participants.count)")

                for participant in participants.values {
                    let identity = await participant.identity
                    let kind = await participant.kind
                    print("🎵 Participant: \(identity) (kind: \(kind))")

                    let audioTracks = await participant.audioTracks
                    print("🎵    Audio tracks count: \(audioTracks.count)")

                    for publication in audioTracks {
                        print("🎵       Track SID: \(publication.sid.stringValue)")
                        print("🎵       Subscribed: \(publication.isSubscribed)")
                        print("🎵       Muted: \(publication.isMuted)")
                        print("🎵       Track exists: \(publication.track != nil)")

                        if let track = publication.track as? RemoteAudioTrack {
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
            if session.isConnected {
                translationInterface(session: session, localMedia: localMedia)
            } else {
                connectingView(session: session, localMedia: localMedia)
            }

            // Close button overlay (always visible)
            closeButton(session: session)
                .padding()

            errors(session: session, localMedia: localMedia)
        }
        .animation(.default, value: session.isConnected)
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
                        .font(.system(size: 32))
                        .foregroundStyle(.white)
                        .background(
                            Circle()
                                .fill(.black.opacity(0.5))
                                .frame(width: 32, height: 32)
                        )
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
            // Waveform placeholder - makes start screen match translation UI
            BarAudioVisualizer(audioTrack: nil,
                               agentState: .listening,
                               barCount: 5,
                               barSpacingFactor: 0.05,
                               barMinOpacity: 0.05)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 40)
                .opacity(0.3) // Subtle, just for visual consistency

            VStack {
                Spacer()

                // Context indicator - shows translation participants
                VStack(spacing: 4) {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Driver")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.5))
                            Text("\(config.driverName) (\(config.driverLanguage))")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white.opacity(0.8))
                        }

                        Image(systemName: "arrow.left.arrow.right")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.4))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Passenger")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.5))
                            Text("\(config.passengerName) (\(config.passengerLanguage ?? "Auto"))")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
                .background(Color.black.opacity(0.4))
                .cornerRadius(12)
                .padding(.horizontal, 40)
                .padding(.bottom, 20)

                // Large, prominent start button
                AsyncButton {
                    await session.start()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 24))
                        Text("Start Translation")
                            .font(.system(size: 19, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.blue)
                            .shadow(color: .blue.opacity(0.4), radius: 12, y: 6)
                    )
                    .foregroundColor(.white)
                } busyLabel: {
                    HStack(spacing: 12) {
                        ProgressView()
                            .tint(.white)
                        Text("Connecting...")
                            .font(.system(size: 19, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.blue.opacity(0.8))
                    )
                    .foregroundColor(.white)
                }
                .padding(.horizontal, 40)
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
                // Context indicator - shows what data agent is using
                VStack(spacing: 4) {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Driver")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.5))
                            Text("\(config.driverName) (\(config.driverLanguage))")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white.opacity(0.8))
                        }

                        Image(systemName: "arrow.left.arrow.right")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.4))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Passenger")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.5))
                            Text("\(config.passengerName) (\(config.passengerLanguage ?? "Auto"))")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
                .background(Color.black.opacity(0.4))
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    // Ultra-minimal transcript - just clean text at bottom
                    TranscriptView()
                        .frame(height: 120)
                        .background(Color.black.opacity(0.3)) // Subtle, barely there
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
