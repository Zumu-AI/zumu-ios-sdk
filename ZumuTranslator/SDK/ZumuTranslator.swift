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

    @StateObject private var session: Session
    @StateObject private var localMedia: LocalMedia
    @Environment(\.dismiss) private var dismiss

    public init(
        config: ZumuTranslator.TranslationConfig,
        apiKey: String,
        baseURL: String = "https://translator.zumu.ai"
    ) {
        self.config = config
        self.apiKey = apiKey
        self.baseURL = baseURL

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

        // Create session (audio routing handled by AVAudioSession)
        let session = Session(
            tokenSource: tokenSource.cached(),
            options: SessionOptions(
                room: Room(
                    roomOptions: RoomOptions(
                        defaultAudioCaptureOptions: AudioCaptureOptions(),
                        defaultAudioPublishOptions: AudioPublishOptions(),
                        dynacast: true,
                        stopLocalTrackOnUnpublish: false
                    )
                )
            )
        )

        // Configure Room audio manager to enable playback
        session.room.audioManager.isSpeakerOutputPreferred = true

        _session = StateObject(wrappedValue: session)
        _localMedia = StateObject(wrappedValue: LocalMedia(session: session))
    }

    public var body: some View {
        ZStack(alignment: .top) {
            if session.isConnected {
                translationInterface()
            } else {
                connectingView()
            }

            // Close button overlay (always visible)
            closeButton()
                .padding()

            errors()
        }
        .environment(\.translationConfig, config)
        .background(.bg1)
        .animation(.default, value: session.isConnected)
        .onAppear {
            print("🚀 Starting Zumu translation session")
            print("   Driver: \(config.driverName) (\(config.driverLanguage))")
            print("   Passenger: \(config.passengerName) (\(config.passengerLanguage ?? "Auto-detect"))")

            // Configure audio session for speaker output
            configureAudioSession()
        }
        .onChange(of: session.isConnected) { oldValue, newValue in
            if newValue {
                // Reconfigure audio when session connects
                print("🔗 Session connected - ensuring speaker output")
                configureAudioSession()

                // Log audio tracks
                Task {
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // Wait 1 second
                    let participants = await session.room.allParticipants
                    print("🎵 Audio tracks status:")
                    for participant in participants.values {
                        print("   Participant: \(participant.identity ?? "unknown")")
                        let audioTracks = await participant.audioTracks
                        for (_, publication) in audioTracks {
                            print("      Track: \(publication.sid ?? "no-sid")")
                            print("      Subscribed: \(publication.isSubscribed)")
                            print("      Muted: \(publication.isMuted)")
                            if let track = publication.track {
                                print("      Track enabled: \(track.isEnabled)")
                            }
                        }
                    }
                }
            }
        }
        .onDisappear {
            print("🔴 SDK dismissed - cleaning up audio session")
            // Deactivate audio session when SDK closes
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                print("❌ Failed to deactivate audio session: \(error)")
            }
        }
    }

    // MARK: - Audio Configuration

    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // Configure for voice chat with speaker output
            try audioSession.setCategory(
                .playAndRecord,
                mode: .videoChat,  // videoChat mode works better for remote audio
                options: [
                    .defaultToSpeaker,
                    .allowBluetooth,
                    .allowBluetoothA2DP,
                    .mixWithOthers
                ]
            )
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            // Explicitly override audio route to speaker
            try audioSession.overrideOutputAudioPort(.speaker)

            print("🔊 Audio session configured: speaker output enabled")
            print("🔊 Current route: \(audioSession.currentRoute.outputs.map { $0.portType.rawValue })")
        } catch {
            print("❌ Failed to configure audio session: \(error)")
        }
    }

    @ViewBuilder
    private func closeButton() -> some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    Task { @MainActor in
                        print("🔴 Close button tapped")
                        // End session first (if connected)
                        if session.isConnected {
                            print("🔴 Ending session...")
                            do {
                                await session.end()
                                // Wait briefly for cleanup
                                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                            } catch {
                                print("⚠️ Session end error (non-fatal): \(error)")
                            }
                        }
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
    private func connectingView() -> some View {
        VStack(spacing: 8 * 4) {
            Spacer()

            // Translation icon
            Image(systemName: "translate")
                .font(.system(size: 60))
                .foregroundStyle(.blue)
                .padding(.bottom, 20)

            // Translation context
            VStack(spacing: 12) {
                Text("AI Translation Ready")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                // Driver info
                HStack(spacing: 8) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.blue)
                    Text("\(config.driverName)")
                        .fontWeight(.medium)
                    Text("(\(config.driverLanguage))")
                        .foregroundStyle(.secondary)
                }

                // Translation arrow
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 24))
                    .foregroundStyle(.gray)
                    .padding(.vertical, 4)

                // Passenger info
                HStack(spacing: 8) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.green)
                    Text("\(config.passengerName)")
                        .fontWeight(.medium)
                    Text("(\(config.passengerLanguage ?? "Auto-detect"))")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)

            // Connect button
            AsyncButton {
                await session.start()
            } label: {
                HStack {
                    Image(systemName: "mic.fill")
                    Text("Start Translation")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            } busyLabel: {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                    Text("Connecting...")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.blue.opacity(0.8))
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .padding(.horizontal, 40)
            .padding(.top, 20)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environmentObject(session)
        .environmentObject(localMedia)
    }

    @ViewBuilder
    private func translationInterface() -> some View {
        VoiceInteractionView()
            .environmentObject(session)
            .environmentObject(localMedia)
            .overlay(alignment: .bottom) {
                listeningIndicator()
                    .padding()
            }
            .safeAreaInset(edge: .bottom) {
                ControlBar(chat: .constant(false))
                    .environmentObject(session)
                    .environmentObject(localMedia)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                    .onDisconnect {
                        // Dismiss when user taps disconnect
                        dismiss()
                    }
            }
    }

    @ViewBuilder
    private func listeningIndicator() -> some View {
        ZStack {
            if session.messages.isEmpty,
               !localMedia.isCameraEnabled,
               !localMedia.isScreenShareEnabled
            {
                Text("Translation ready. Start speaking...")
                    .font(.system(size: 15))
                    .shimmering()
                    .transition(.blurReplace)
            }
        }
        .animation(.default, value: session.messages.isEmpty)
    }

    @ViewBuilder
    private func errors() -> some View {
        if let error = session.error {
            ErrorView(error: error) { session.dismissError() }
        }

        if let agentError = session.agent.error {
            ErrorView(error: agentError) {
                Task {
                    await session.end()
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
