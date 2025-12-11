import SwiftUI

/// Example app demonstrating how to integrate Zumu Translator SDK
///
/// This shows two integration patterns:
/// 1. SwiftUI: Using .sheet() or .fullScreenCover()
/// 2. UIKit: Using ZumuTranslator.present()
///
/// Integrators should copy this pattern into their own apps.

// MARK: - SwiftUI Example

@main
struct ExampleIntegrationApp: App {
    var body: some Scene {
        WindowGroup {
            ExampleSwiftUIView()
        }
    }
}

struct ExampleSwiftUIView: View {
    @State private var showTranslation = false

    // These would come from your app's state/database
    @State private var driverName = ""
    @State private var driverLanguage = "English"
    @State private var passengerName = ""
    @State private var passengerLanguage = "Spanish"

    // Your Zumu API key - store securely in production!
    private let apiKey = ProcessInfo.processInfo.environment["ZUMU_API_KEY"] ?? "zumu_YOUR_API_KEY_HERE"

    var body: some View {
        NavigationView {
            Form {
                Section("Driver") {
                    TextField("Name", text: $driverName)
                    Picker("Language", selection: $driverLanguage) {
                        Text("English").tag("English")
                        Text("Spanish").tag("Spanish")
                        Text("Russian").tag("Russian")
                        Text("Chinese").tag("Chinese")
                    }
                }

                Section("Passenger") {
                    TextField("Name", text: $passengerName)
                    Picker("Language", selection: $passengerLanguage) {
                        Text("Spanish").tag("Spanish")
                        Text("English").tag("English")
                        Text("Russian").tag("Russian")
                        Text("Chinese").tag("Chinese")
                    }
                }

                Section {
                    // THIS IS YOUR INTEGRATION BUTTON
                    Button(action: { showTranslation = true }) {
                        HStack {
                            Spacer()
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                            Text("Start Translation")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .disabled(driverName.isEmpty || passengerName.isEmpty)
                }
            }
            .navigationTitle("Your App")
            // THIS IS HOW YOU PRESENT THE SDK
            .fullScreenCover(isPresented: $showTranslation) {
                ZumuTranslatorView(
                    config: ZumuTranslator.TranslationConfig(
                        driverName: driverName,
                        driverLanguage: driverLanguage,
                        passengerName: passengerName,
                        passengerLanguage: passengerLanguage,
                        tripId: UUID().uuidString
                    ),
                    apiKey: apiKey
                )
            }
        }
    }
}

// MARK: - UIKit Example

#if canImport(UIKit)
import UIKit

class ExampleViewController: UIViewController {

    // Your Zumu API key - store securely in production!
    private let apiKey = ProcessInfo.processInfo.environment["ZUMU_API_KEY"] ?? "zumu_YOUR_API_KEY_HERE"

    // These would come from your app's state/database
    var driverName: String = "John Smith"
    var driverLanguage: String = "English"
    var passengerName: String = "Maria Garcia"
    var passengerLanguage: String = "Spanish"
    var tripId: String?

    override func viewDidLoad() {
        super.viewDidLoad()

        // Setup your UI button
        let startButton = UIButton(type: .system)
        startButton.setTitle("Start Translation", for: .normal)
        startButton.addTarget(self, action: #selector(startTranslationTapped), for: .touchUpInside)

        // Add to your view...
        // (setup constraints, etc)
    }

    // THIS IS HOW YOU START THE SDK FROM UIKIT
    @objc func startTranslationTapped() {
        let config = ZumuTranslator.TranslationConfig(
            driverName: driverName,
            driverLanguage: driverLanguage,
            passengerName: passengerName,
            passengerLanguage: passengerLanguage,
            tripId: tripId ?? UUID().uuidString
        )

        ZumuTranslator.present(
            config: config,
            apiKey: apiKey,
            from: self
        )
    }
}
#endif

// MARK: - Programmatic Example (No Configuration UI)

struct ProgrammaticExampleView: View {
    @State private var showTranslation = false

    var body: some View {
        Button("Start Translation") {
            showTranslation = true
        }
        .fullScreenCover(isPresented: $showTranslation) {
            // Pass configuration directly - no user input needed
            ZumuTranslatorView(
                config: ZumuTranslator.TranslationConfig(
                    driverName: "John Smith",
                    driverLanguage: "English",
                    passengerName: "Maria Garcia",
                    passengerLanguage: "Spanish",
                    tripId: "trip_12345",
                    pickupLocation: "123 Main St",
                    dropoffLocation: "456 Oak Ave"
                ),
                apiKey: ProcessInfo.processInfo.environment["ZUMU_API_KEY"] ?? "zumu_YOUR_API_KEY_HERE"
            )
        }
    }
}
