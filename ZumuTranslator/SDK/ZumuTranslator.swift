import SwiftUI
import LiveKit
import LiveKitComponents
import AVFoundation
import Combine

// MARK: - Session Coordinator

/// Singleton that coordinates session lifecycle to prevent overlapping sessions
/// Ensures old session fully disconnects before allowing new session to start
@MainActor
private class SessionCoordinator {
    static let shared = SessionCoordinator()

    private(set) var isSessionActive = false
    private var activeSession: Session?

    private init() {}

    /// Register a new session and ensure old one is cleaned up
    func registerSession(_ session: Session) async {
        print("📋 SessionCoordinator: Registering new session")

        // If there's an active session, end it first
        if let oldSession = activeSession, isSessionActive {
            print("📋 SessionCoordinator: Ending previous session...")
            await oldSession.end()

            // Wait for disconnect to complete
            var attempts = 0
            while oldSession.isConnected && attempts < 20 {
                print("📋 SessionCoordinator: Waiting for disconnect (attempt \(attempts + 1)/20)...")
                try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1s
                attempts += 1
            }

            if oldSession.isConnected {
                print("⚠️ SessionCoordinator: Old session still connected after timeout")
            } else {
                print("✅ SessionCoordinator: Old session disconnected")
            }

            // CRITICAL: Deactivate audio session to free audio resources
            print("📋 SessionCoordinator: Deactivating audio session...")
            let audioSession = AVAudioSession.sharedInstance()
            do {
                try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
                print("✅ SessionCoordinator: Audio session deactivated")
            } catch {
                print("⚠️ SessionCoordinator: Failed to deactivate audio session: \(error)")
            }

            // Extra safety delay to ensure audio engine resources are freed
            try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5s
        }

        // Register new session
        activeSession = session
        isSessionActive = true
        print("✅ SessionCoordinator: New session registered and ready")
    }

    /// Unregister session when it's done
    func unregisterSession(_ session: Session) {
        if activeSession === session {
            print("📋 SessionCoordinator: Unregistering session")
            activeSession = nil
            isSessionActive = false
        }
    }
}

// MARK: - Main SDK Entry Point

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

/// Main translation interface view wrapper
/// Uses Container Pattern with .id() to force complete view recreation for each session
/// Can be presented as a sheet, fullScreenCover, or NavigationLink destination
public struct ZumuTranslatorView: View {
    public let config: ZumuTranslator.TranslationConfig
    public let apiKey: String
    public let baseURL: String

    // Key to force view recreation - new UUID for each session
    @State private var sessionKey = UUID()
    @Environment(\.dismiss) private var dismiss

    public init(
        config: ZumuTranslator.TranslationConfig,
        apiKey: String,
        baseURL: String = "https://translator.zumu.ai"
    ) {
        self.config = config
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    public var body: some View {
        ZumuTranslatorSessionView(
            config: config,
            apiKey: apiKey,
            baseURL: baseURL,
            onDismiss: dismiss
        )
        .id(sessionKey)  // ✅ Forces complete recreation
        .onDisappear {
            // Generate new ID for next appearance - ensures fresh session
            sessionKey = UUID()
        }
    }
}

// MARK: - Session View (Internal)

/// Internal session view that manages LiveKit Session lifecycle
/// Created fresh for each conversation via .id() modifier
private struct ZumuTranslatorSessionView: View {
    // ✅ Proper @StateObject for ObservableObject lifecycle
    @StateObject private var session: Session
    @StateObject private var localMedia: LocalMedia

    // Track if cleanup has been initiated (prevents double cleanup)
    @State private var isCleaningUp = false

    let config: ZumuTranslator.TranslationConfig
    let onDismiss: DismissAction

    // ✅ Create session in init (proper @StateObject pattern)
    init(
        config: ZumuTranslator.TranslationConfig,
        apiKey: String,
        baseURL: String,
        onDismiss: DismissAction
    ) {
        self.config = config
        self.onDismiss = onDismiss

        // Create token source
        let tokenConfig = ZumuTokenSource.TranslationConfig(
            driverName: config.driverName,
            driverLanguage: config.driverLanguage,
            passengerName: config.passengerName,
            passengerLanguage: config.passengerLanguage,
            tripId: config.tripId,
            pickupLocation: config.pickupLocation,
            dropoffLocation: config.dropoffLocation
        )

        let tokenSource = ZumuTokenSource(
            apiKey: apiKey,
            config: tokenConfig,
            baseURL: baseURL
        )

        // Create fresh session
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

        _session = StateObject(wrappedValue: newSession)
        _localMedia = StateObject(wrappedValue: LocalMedia(session: newSession))
    }

    // MARK: - Session Lifecycle

    // MARK: - Simplified Lifecycle (No manual cleanup needed - SwiftUI handles it)

    public var body: some View {
        // ✅ Session always exists (created in init)
        sessionInterface(session: session, localMedia: localMedia)
        .environment(\.translationConfig, config)
        .background(.bg1)
        .onAppear {
            print("🚀 Starting fresh translation session")
            print("   Driver: \(config.driverName) (\(config.driverLanguage))")
            print("   Passenger: \(config.passengerName) (\(config.passengerLanguage ?? "Auto-detect"))")

            // Detect simulator
            #if targetEnvironment(simulator)
            print("⚠️ WARNING: Running on iOS Simulator - WebRTC audio playback may not work!")
            print("⚠️ For full audio functionality, please test on a physical iOS device")
            #endif

            // ✅ Coordinate session lifecycle to prevent overlaps
            Task {
                // Register with coordinator - will wait for old session to cleanup
                await SessionCoordinator.shared.registerSession(session)

                // Now it's safe to start
                print("   Starting new session...")
                await session.start()
            }

            // Force AudioManager configuration
            forceAudioManagerConfiguration()
        }
        // REMOVED: .onChange(of: session.isConnected) - reactive observer causes recursive mutex lock during disconnect
        // All diagnostic tasks removed - any access to session properties during disconnect can cause recursive mutex lock
        .onDisappear {
            print("🔴 Session view disappearing")
            // ✅ Prevent double cleanup if disconnect button already initiated it
            guard !isCleaningUp else {
                print("   Cleanup already initiated, skipping")
                return
            }
            isCleaningUp = true

            // ✅ Following LiveKit pattern: Just call end() and trust async cleanup
            // DON'T poll session.isConnected - causes mutex deadlock during cleanup
            Task {
                print("   Calling session.end()...")
                await session.end()
                print("✅ Session.end() completed")

                // Unregister from coordinator
                SessionCoordinator.shared.unregisterSession(session)
            }
            // SwiftUI will deallocate @StateObject automatically after Tasks are cancelled
        }
    }

    // MARK: - Audio Configuration

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
        // REMOVED: .animation(.default, value: session.isConnected) - reactive observer causes recursive mutex lock during disconnect
    }

    @ViewBuilder
    private func closeButton(session: Session) -> some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    print("🔴 Close button tapped")
                    onDismiss()  // ✅ Simple dismissal - onDisappear handles cleanup
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 36, weight: .regular))
                        .foregroundStyle(.primary.opacity(0.4))
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
                            onDismiss()
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
                // ✅ Simple dismissal - onDisappear handles cleanup
                onDismiss()
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
