import LiveKit
import SwiftUI

@main
struct ZumuTranslatorApp: App {
    // MARK: - Configuration

    /// Zumu API Key - Replace with your actual API key from translator.zumu.ai
    /// For production: Store in Keychain or use environment variables
    private static let apiKey: String = {
        // Option 1: Use environment variable (recommended for development)
        if let envKey = ProcessInfo.processInfo.environment["ZUMU_API_KEY"] {
            return envKey
        }

        // Option 2: Hardcode for testing (replace with your key)
        return "zumu_YOUR_API_KEY_HERE"
    }()

    @State private var session: Session?
    @State private var config: ZumuTokenSource.TranslationConfig?

    var body: some Scene {
        WindowGroup {
            Group {
                if let session = session {
                    AppView()
                        .environmentObject(session)
                        .environmentObject(LocalMedia(session: session))
                        .environment(\.translationConfig, config)
                        .environment(\.voiceEnabled, true)
                        .environment(\.videoEnabled, false)
                        .environment(\.textEnabled, false)
                } else {
                    ConfigurationView(onStart: startSession)
                }
            }
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 900)
        #endif
    }

    private func startSession(config: ZumuTokenSource.TranslationConfig) {
        print("🚀 Starting Zumu translation session")
        print("   Driver: \(config.driverName) (\(config.driverLanguage))")
        print("   Passenger: \(config.passengerName) (\(config.passengerLanguage ?? "Auto-detect"))")

        let tokenSource = ZumuTokenSource(apiKey: Self.apiKey, config: config)

        let session = Session(
            tokenSource: tokenSource.cached(),
            options: SessionOptions(
                room: Room(
                    roomOptions: RoomOptions(
                        // Voice-only configuration
                        defaultAudioCaptureOptions: AudioCaptureOptions(),
                        defaultAudioPublishOptions: AudioPublishOptions()
                    )
                )
            )
        )

        self.session = session
        self.config = config
    }
}
