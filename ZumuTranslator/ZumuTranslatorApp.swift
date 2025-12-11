import LiveKit
import SwiftUI

/// Demo app for testing the Zumu Translator SDK
///
/// This app demonstrates the SDK integration pattern.
/// Integrators should follow this same pattern in their own apps.
@main
struct ZumuTranslatorApp: App {
    var body: some Scene {
        WindowGroup {
            DemoIntegrationView()
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 900)
        #endif
    }
}

/// Demo view showing SDK integration
struct DemoIntegrationView: View {
    @State private var showTranslation = false
    @State private var driverName = ""
    @State private var driverLanguage = "English"
    @State private var passengerName = ""
    @State private var passengerLanguage = "Spanish"

    private let apiKey: String = {
        if let envKey = ProcessInfo.processInfo.environment["ZUMU_API_KEY"] {
            return envKey
        }
        return "zumu_YOUR_API_KEY_HERE"
    }()

    private let supportedLanguages = ["English", "Spanish", "Russian", "Chinese", "Arabic", "Hindi", "Turkish"]

    var body: some View {
        NavigationView {
            Form {
                Section("Driver") {
                    TextField("Name", text: $driverName)
                        .autocapitalization(.words)

                    Picker("Language", selection: $driverLanguage) {
                        ForEach(supportedLanguages, id: \.self) { language in
                            Text(language).tag(language)
                        }
                    }
                }

                Section("Passenger") {
                    TextField("Name", text: $passengerName)
                        .autocapitalization(.words)

                    Picker("Language", selection: $passengerLanguage) {
                        ForEach(supportedLanguages, id: \.self) { language in
                            Text(language).tag(language)
                        }
                    }
                }

                Section {
                    Button(action: { showTranslation = true }) {
                        HStack {
                            Spacer()
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                            Text("Start Translation")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .disabled(driverName.isEmpty || passengerName.isEmpty || apiKey == "zumu_YOUR_API_KEY_HERE")
                }

                if apiKey == "zumu_YOUR_API_KEY_HERE" {
                    Section {
                        Text("⚠️ Configure API key to test")
                            .foregroundColor(.orange)
                        Text("Set ZUMU_API_KEY environment variable or edit ZumuTranslatorApp.swift")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("SDK Demo")
            .fullScreenCover(isPresented: $showTranslation) {
                // THIS IS THE SDK INTEGRATION
                ZumuTranslatorView(
                    config: ZumuTranslator.TranslationConfig(
                        driverName: driverName.isEmpty ? "Driver" : driverName,
                        driverLanguage: driverLanguage,
                        passengerName: passengerName.isEmpty ? "Passenger" : passengerName,
                        passengerLanguage: passengerLanguage,
                        tripId: UUID().uuidString
                    ),
                    apiKey: apiKey
                )
            }
        }
    }
}
