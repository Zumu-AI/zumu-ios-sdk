import SwiftUI
import LiveKit

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

        // Create session
        let session = Session(
            tokenSource: tokenSource.cached(),
            options: SessionOptions(
                room: Room(
                    roomOptions: RoomOptions(
                        defaultAudioCaptureOptions: AudioCaptureOptions(),
                        defaultAudioPublishOptions: AudioPublishOptions()
                    )
                )
            )
        )

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

            errors()
        }
        .environment(\.translationConfig, config)
        .background(.bg1)
        .animation(.default, value: session.isConnected)
        .onAppear {
            print("🚀 Starting Zumu translation session")
            print("   Driver: \(config.driverName) (\(config.driverLanguage))")
            print("   Passenger: \(config.passengerName) (\(config.passengerLanguage ?? "Auto-detect"))")
        }
    }

    @ViewBuilder
    private func connectingView() -> some View {
        StartView()
    }

    @ViewBuilder
    private func translationInterface() -> some View {
        VoiceInteractionView()
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
